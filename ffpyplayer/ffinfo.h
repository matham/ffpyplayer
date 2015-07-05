
#ifndef _FFINFO_H
#define _FFINFO_H

#include "ffconfig.h"
#include "libavfilter/avcodec.h"
#include "libavformat/avformat.h"
#include "libavdevice/avdevice.h"
#include "libswscale/swscale.h"
#include "libswresample/swresample.h"
#include "libavutil/opt.h"
#include "libavutil/avstring.h"
#include "libavutil/pixdesc.h"


#if CONFIG_POSTPROC
#include "libpostproc/postprocess.h"
#endif

#ifndef AV_LOG_TRACE
#define AV_LOG_TRACE    56
#endif


#define INDENT        1
#define SHOW_VERSION  2
#define SHOW_CONFIG   4

#define PRINT_LIB_INFO(libname, LIBNAME, flags, level)                  \
    if (CONFIG_##LIBNAME) {                                             \
        const char *indent = flags & INDENT? "  " : "";                 \
        if (flags & SHOW_VERSION) {                                     \
            unsigned int version = libname##_version();                 \
            av_log(NULL, level,                                         \
                   "%slib%-11s %2d.%3d.%3d / %2d.%3d.%3d\n",            \
                   indent, #libname,                                    \
                   LIB##LIBNAME##_VERSION_MAJOR,                        \
                   LIB##LIBNAME##_VERSION_MINOR,                        \
                   LIB##LIBNAME##_VERSION_MICRO,                        \
                   version >> 16, version >> 8 & 0xff, version & 0xff); \
        }                                                               \
        if (flags & SHOW_CONFIG) {                                      \
            const char *cfg = libname##_configuration();                \
            av_log(NULL, level, "%s%-11s configuration: %s\n",   	   	\
                    indent, #libname, cfg);                         	\
        }                                                               \
    }

#define FLAGS (o->type == AV_OPT_TYPE_FLAGS) ? AV_DICT_APPEND : 0

static void print_all_libs_info(int flags, int level)
{
#if CONFIG_AVUTIL
    PRINT_LIB_INFO(avutil,   AVUTIL,   flags, level);
#endif
#if CONFIG_AVCODEC
    PRINT_LIB_INFO(avcodec,  AVCODEC,  flags, level);
#endif
#if CONFIG_AVFORMAT
    PRINT_LIB_INFO(avformat, AVFORMAT, flags, level);
#endif
#if CONFIG_AVDEVICE
    PRINT_LIB_INFO(avdevice, AVDEVICE, flags, level);
#endif
#if CONFIG_AVFILTER
    PRINT_LIB_INFO(avfilter, AVFILTER, flags, level);
#endif
#if CONFIG_SWSCALE
    PRINT_LIB_INFO(swscale,  SWSCALE,  flags, level);
#endif
#if CONFIG_SWRESAMPLE
    PRINT_LIB_INFO(swresample,SWRESAMPLE,  flags, level);
#endif
#if CONFIG_POSTPROC
    PRINT_LIB_INFO(postproc, POSTPROC, flags, level);
#endif
}



static const AVOption *opt_find(void *obj, const char *name, const char *unit,
                            int opt_flags, int search_flags)
{
    const AVOption *o = av_opt_find(obj, name, unit, opt_flags, search_flags);
    if(o && !o->flags)
        return NULL;
    return o;
}

#define FLAGS (o->type == AV_OPT_TYPE_FLAGS) ? AV_DICT_APPEND : 0
static int opt_default(const char *opt, const char *arg,
        struct SwsContext *sws_opts, AVDictionary **swr_opts,
        AVDictionary **format_opts, AVDictionary **codec_opts)
{
    const AVOption *o;
    int consumed = 0;
    char opt_stripped[128];
    const char *p;
    const AVClass *cc = avcodec_get_class(), *fc = avformat_get_class();
#if CONFIG_SWRESAMPLE
    struct SwrContext *swr;
#endif
    const AVClass *sc, *swr_class;
    int ret;

    if (!strcmp(opt, "debug") || !strcmp(opt, "fdebug"))
        av_log_set_level(AV_LOG_DEBUG);

    if (!(p = strchr(opt, ':')))
        p = opt + strlen(opt);
    av_strlcpy(opt_stripped, opt, FFMIN(sizeof(opt_stripped), p - opt + 1));

    if ((o = opt_find(&cc, opt_stripped, NULL, 0,
                         AV_OPT_SEARCH_CHILDREN | AV_OPT_SEARCH_FAKE_OBJ)) ||
        ((opt[0] == 'v' || opt[0] == 'a' || opt[0] == 's') &&
         (o = opt_find(&cc, opt + 1, NULL, 0, AV_OPT_SEARCH_FAKE_OBJ)))) {
        av_dict_set(codec_opts, opt, arg, FLAGS);
        consumed = 1;
    }
    if ((o = opt_find(&fc, opt, NULL, 0,
                         AV_OPT_SEARCH_CHILDREN | AV_OPT_SEARCH_FAKE_OBJ))) {
        av_dict_set(format_opts, opt, arg, FLAGS);
        if (consumed)
            av_log(NULL, AV_LOG_VERBOSE, "Routing option %s to both codec and muxer layer\n", opt);
        consumed = 1;
    }
#if CONFIG_SWSCALE
    sc = sws_get_class();
    if (sws_opts && !consumed && opt_find(&sc, opt, NULL, 0,
                         AV_OPT_SEARCH_CHILDREN | AV_OPT_SEARCH_FAKE_OBJ)) {
        // XXX we only support sws_flags, not arbitrary sws options
        ret = av_opt_set(sws_opts, opt, arg, 0);
        if (ret < 0) {
            av_log(NULL, AV_LOG_ERROR, "Error setting option %s.\n", opt);
            return ret;
        }
        consumed = 1;
    }
#endif
#if CONFIG_SWRESAMPLE
    swr_class = swr_get_class();
    if (swr_opts && !consumed && (o=opt_find(&swr_class, opt, NULL, 0,
                                    AV_OPT_SEARCH_CHILDREN | AV_OPT_SEARCH_FAKE_OBJ))) {
        swr = swr_alloc();
        ret = av_opt_set(swr, opt, arg, 0);
        swr_free(&swr);
        if (ret < 0) {
            av_log(NULL, AV_LOG_ERROR, "Error setting option %s.\n", opt);
            return ret;
        }
        av_dict_set(swr_opts, opt, arg, FLAGS);
        consumed = 1;
    }
#endif

    if (consumed)
        return 0;
    return AVERROR_OPTION_NOT_FOUND;
}

static int get_plane_sizes(int size[4], int required_plane[4], enum AVPixelFormat pix_fmt,
        int height, const int linesizes[4])
{
    int i, total_size;
    memset(required_plane, 0, sizeof(required_plane[0])*4);

    const AVPixFmtDescriptor *desc = av_pix_fmt_desc_get(pix_fmt);
    memset(size, 0, sizeof(size[0])*4);

    if (!height)
        return AVERROR(EINVAL);

    if (!desc || desc->flags & AV_PIX_FMT_FLAG_HWACCEL)
        return AVERROR(EINVAL);

    if (linesizes[0] > (INT_MAX - 1024) / height)
        return AVERROR(EINVAL);
    size[0] = linesizes[0] * height;

    if (desc->flags & AV_PIX_FMT_FLAG_PAL ||
        desc->flags & AV_PIX_FMT_FLAG_PSEUDOPAL) {
        size[1] = 256 * 4;
        required_plane[0] = 1;
        return size[0] + size[1];
    }

    for (i = 0; i < 4; i++)
        required_plane[desc->comp[i].plane] = 1;

    total_size = size[0];
    for (i = 1; i < 4 && required_plane[i]; i++) {
        int h, s = (i == 1 || i == 2) ? desc->log2_chroma_h : 0;
        h = (height + (1 << s) - 1) >> s;
        if (linesizes[i] > INT_MAX / h)
            return AVERROR(EINVAL);
        size[i] = h * linesizes[i];
        if (total_size > INT_MAX - size[i])
            return AVERROR(EINVAL);
        total_size += size[i];
    }

    return total_size;
}

#endif
