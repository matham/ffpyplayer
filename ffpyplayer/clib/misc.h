
#ifndef _FFINFO_H
#define _FFINFO_H

#include "../includes/ffconfig.h"
#include "libavcodec/avcodec.h"
#include "libavfilter/avfilter.h"
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

void print_all_libs_info(int flags, int level);

const AVOption *opt_find(void *obj, const char *name, const char *unit,
                            int opt_flags, int search_flags);

int opt_default(const char *opt, const char *arg,
    struct SwsContext *sws_opts, AVDictionary **sws_dict, AVDictionary **swr_opts,
    AVDictionary **resample_opts, AVDictionary **format_opts, AVDictionary **codec_opts);

int get_plane_sizes(int size[4], int required_plane[4], enum AVPixelFormat pix_fmt,
    int height, const int linesizes[4]);

#endif
