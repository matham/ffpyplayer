''' TODO:
Check how to deal with errors, and maybe make ffmpeg specific error codes?
Implement opt_default() so that we can set any user options using av_dict
Do we need OpenCL support?
show_banner(argc, argv, options) at start
provide full cross format image buffer conversion libs
av_dlog ?
exceptions need to be included in function definition
right now copy occurs at queue, at conversion to python and at blit.
provide link between audio to video filters
display bitmap based subtitles

need to call Py_DECREF to prevent memory leak in video_image_display is a cython bug, or feature?

'''

''' Things to watch out for when proting from c to cython:
In c the &,^,| operators are weaker than comparisons (<= etc.), in python it's reversed.
Macro function gets inlined in c, with variables names replaced to the current context
    variables. Pointers should be used in the macro replacement function to refer to
    the original variables. Use inline for them.
In c, a macro can work for arguments of type float, int, etc. simultanously because
    it just gets substituted. When porting a macro function you have to make a function
    for each input argument type combination that it's used on.
When you get cython errors about python objects it means you forgot to define some
    struct/variable which you used.
In c, if either numerator or denominator is a float, the result is also a float.
    In python, only if the denuminator is a float will the result be a float.
When converting loops from for (x=0;x<10;x++) to for x in range(10) make sure
    the code is not changing x in the loop since it won't work for python.
In cython you cannot use 0 instead of NULL, so for e.g. int *ptr = ...
    we have to check if ptr == NULL: instead of if not ptr:
When passing a string to c code which is kept, you have to keep python string in memory
'''

cdef extern from "stdarg.h":
    ctypedef struct va_list:
        pass
from libc.stdint cimport int64_t, uint64_t, int32_t, uint32_t, uint16_t,\
int16_t, uint8_t, int8_t, uintptr_t

ctypedef int (*lockmgr_func)(void **, AVLockOp)
ctypedef int (*int_void_func)(void *)

ctypedef float FFTSample

include "sdl.pxi"
include "ff_defs_comp.pxi"


cdef:
    extern from * nogil:
        struct AVPacket:
            uint8_t *data
            int64_t pos
            int64_t pts
            int64_t dts
            int size
            int stream_index
        enum AVMediaType:
            AVMEDIA_TYPE_UNKNOWN = -1,  #///< Usually treated as AVMEDIA_TYPE_DATA
            AVMEDIA_TYPE_VIDEO,
            AVMEDIA_TYPE_AUDIO,
            AVMEDIA_TYPE_DATA,          #///< Opaque data information usually continuous
            AVMEDIA_TYPE_SUBTITLE,
            AVMEDIA_TYPE_ATTACHMENT,    #///< Opaque data information usually sparse
            AVMEDIA_TYPE_NB,

    extern from "libavutil/avstring.h" nogil:
         size_t av_strlcpy(char *, const char *, size_t)
         size_t av_strlcatf(char *, size_t, const char *, ...)
         char *av_asprintf(const char *, ...)

    extern from "libavutil/mathematics.h" nogil:
        int64_t av_rescale_q(int64_t, AVRational, AVRational)

    extern from "libavutil/pixdesc.h" nogil:
        const char *av_get_pix_fmt_name(AVPixelFormat)

    extern from "libavutil/imgutils.h" nogil:
        int av_image_alloc(uint8_t **, int *, int, int, AVPixelFormat, int)

    extern from "libavutil/dict.h" nogil:
        int AV_DICT_IGNORE_SUFFIX
        int AV_DICT_DONT_STRDUP_VAL
        struct AVDictionaryEntry:
            char *key
            char *value
        void av_dict_free(AVDictionary **)
        AVDictionaryEntry * av_dict_get(AVDictionary *, const char *,
                                        const AVDictionaryEntry *, int)

    extern from "libavutil/parseutils.h" nogil:
        pass

    extern from "libavutil/samplefmt.h" nogil:
        enum AVSampleFormat:
            AV_SAMPLE_FMT_S16,
            AV_SAMPLE_FMT_NONE,
        AVSampleFormat av_get_packed_sample_fmt(AVSampleFormat)
        const char *av_get_sample_fmt_name(AVSampleFormat)
        int av_samples_get_buffer_size(int *, int, int, AVSampleFormat, int)
        int av_get_bytes_per_sample(AVSampleFormat)

    extern from "libavutil/avassert.h" nogil:
        pass

    extern from "libavutil/time.h" nogil:
        int64_t av_gettime()
        int av_usleep(unsigned)

    extern from * nogil:
        void av_free(void *)
        void av_freep(void *)
        void *av_malloc(size_t)
        char *av_strdup(const char *)
        int av_get_channel_layout_nb_channels(uint64_t)
        void av_get_channel_layout_string(char *, int, int, uint64_t)
        int64_t av_get_default_channel_layout(int)
        int av_clip(int a, int amin, int amax)
        int64_t AV_CH_LAYOUT_STEREO_DOWNMIX
        
        struct AVRational:
            int num #///< numerator
            int den #///< denominator
        inline double av_q2d(AVRational)

        int AV_LOG_QUIET
        int AV_LOG_PANIC
        int AV_LOG_FATAL
        int AV_LOG_ERROR
        int AV_LOG_WARNING
        int AV_LOG_INFO
        int AV_LOG_VERBOSE
        int AV_LOG_DEBUG
        int AV_LOG_SKIP_REPEATED
        void av_log(void *, int, const char *, ...)
        void av_log_set_flags(int)
        void av_log_set_level(int)
        void av_log_set_callback(void (*)(void*, int, const char*, va_list))
        void av_log_default_callback(void*, int, const char*, va_list)
        void av_log_format_line(void *, int, const char *, va_list, char *, int, int *)
        
        enum AVPixelFormat:
            AV_PIX_FMT_YUV420P,
            AV_PIX_FMT_RGB24,
            AV_PIX_FMT_NONE,
        
        int64_t AV_NOPTS_VALUE
        
        struct AVDictionary:
            pass
        int av_dict_set(AVDictionary **, const char *, const char *, int)
        
        void av_max_alloc(size_t)
        
        int av_get_cpu_flags()
        int av_parse_cpu_caps(unsigned *, const char *)
        void av_force_cpu_flags(int)
        void *av_mallocz(size_t)
        
        int AVERROR(int)
        int AVUNERROR(int)
        
        enum AVPictureType:
            pass
        char av_get_picture_type_char(AVPictureType)
        void av_frame_unref(AVFrame *)
        void av_frame_free(AVFrame **)
        void av_frame_move_ref(AVFrame *, AVFrame *)
        unsigned av_int_list_length_for_size(unsigned, const void *, uint64_t)
        int av_opt_set_bin(void *, const char *, const uint8_t *, int, int)
        
        AVFrame *av_frame_alloc()
        int64_t av_frame_get_pkt_pos(const AVFrame *)
        int av_frame_get_channels(const AVFrame *)
        
        int AVERROR_EOF
        int AVERROR_OPTION_NOT_FOUND
        int av_strerror(int, char *, size_t)
        
        inline void *av_x_if_null(const void *p, const void *x)
        
        int64_t AV_TIME_BASE
        
        struct AVClass:
            pass
        struct AVIOContext:
            int error
            int eof_reached
        struct AVIOInterruptCB:
            int (*callback)(void*)
            void *opaque
        int url_feof(AVIOContext *)
        inline int64_t avio_tell(AVIOContext *)

    extern from "libavformat/avformat.h" nogil:
        int AVSEEK_FLAG_BYTE
        int AVFMT_NOBINSEARCH
        int AVFMT_NOGENSEARCH
        int AVFMT_NO_BYTE_SEEK
        int AVFMT_FLAG_GENPTS
        int AVFMT_TS_DISCONT
        int AV_DISPOSITION_ATTACHED_PIC
        struct AVInputFormat:
            int (*read_seek)(AVFormatContext *, int, int64_t, int)
            int flags
            const char *name
        struct AVOutputFormat:
            pass
        struct AVFormatContext:
            AVInputFormat *iformat
            AVOutputFormat *oformat
            AVStream **streams
            unsigned int nb_streams
            char filename[1024]
            AVIOContext *pb
            AVDictionary *metadata
            AVIOInterruptCB interrupt_callback
            int flags
            int64_t start_time
            int bit_rate
            int64_t duration
        struct AVStream:
            AVCodecContext *codec
            AVRational time_base
            int64_t start_time
            AVDiscard discard
            AVPacket attached_pic
            int disposition
        void av_register_all()
        int avformat_network_init()
        int avformat_network_deinit()
        AVInputFormat *av_find_input_format(const char *)
        AVRational av_guess_sample_aspect_ratio(AVFormatContext *, AVStream *, AVFrame *)
        AVRational av_guess_frame_rate(AVFormatContext *, AVStream *, AVFrame *)
        int avformat_match_stream_specifier(AVFormatContext *, AVStream *,
                                            const char *)
        AVFormatContext *avformat_alloc_context()
        int avformat_open_input(AVFormatContext **, const char *, AVInputFormat *, AVDictionary **) with gil
        void avformat_close_input(AVFormatContext **)
        int avformat_find_stream_info(AVFormatContext *, AVDictionary **) with gil
        int avformat_seek_file(AVFormatContext *, int, int64_t, int64_t, int64_t, int)
        int av_find_best_stream(AVFormatContext *, AVMediaType, int, int, AVCodec **, int)
        void av_dump_format(AVFormatContext *, int, const char *, int)
        int av_read_pause(AVFormatContext *)
        int av_read_play(AVFormatContext *)
        int av_read_frame(AVFormatContext *, AVPacket *) with gil

    extern from "libavdevice/avdevice.h" nogil:
        void avdevice_register_all()

    extern from "libswscale/swscale.h" nogil:
        int SWS_BICUBIC
        struct SwsContext:
            pass
        struct SwsFilter:
            pass
        SwsContext *sws_getContext(int, int, AVPixelFormat, int, int, AVPixelFormat,
                                   int, SwsFilter *, SwsFilter *, const double *)
        SwsContext *sws_getCachedContext(SwsContext *, int, int, AVPixelFormat,
                                        int, int, AVPixelFormat, int, SwsFilter *,
                                        SwsFilter *, const double *)
        int sws_scale(SwsContext *, const uint8_t *const [], const int[], int, int,
                      uint8_t *const [], const int[])
        void sws_freeContext(SwsContext *)

    extern from "libavutil/opt.h" nogil:
        int AV_OPT_SEARCH_CHILDREN
        int AV_OPT_FLAG_ENCODING_PARAM
        int AV_OPT_FLAG_DECODING_PARAM
        int AV_OPT_FLAG_VIDEO_PARAM
        int AV_OPT_FLAG_AUDIO_PARAM
        int AV_OPT_FLAG_SUBTITLE_PARAM
        int AV_OPT_SEARCH_FAKE_OBJ
        struct AVOption:
            pass
        int av_opt_get_int(void *, const char *, int, int64_t *)
        int av_opt_set_int(void *, const char *, int64_t, int)
        int av_opt_set_image_size(void *, const char *, int, int, int)
        const AVOption *av_opt_find(void *, const char *, const char *, int, int)

    extern from "libavcodec/avfft.h" nogil:
        enum RDFTransformType:
            DFT_R2C,
            IDFT_C2R,
            IDFT_R2C,
            DFT_C2R,
        struct RDFTContext:
            pass
        void av_rdft_end(RDFTContext *)
        RDFTContext *av_rdft_init(int, RDFTransformType)
        void av_rdft_calc(RDFTContext *, FFTSample *)

    extern from "libswresample/swresample.h" nogil:
        struct SwrContext:
            pass
        void swr_free(SwrContext **)
        SwrContext *swr_alloc_set_opts(SwrContext *, int64_t, AVSampleFormat,
                                       int, int64_t, AVSampleFormat, int, int, void *)
        int swr_init(SwrContext *)
        int swr_set_compensation(SwrContext *, int, int)
        int swr_convert(SwrContext *, uint8_t **, int, const uint8_t ** , int)

    #if CONFIG_AVFILTER
    extern from "libavfilter/avcodec.h" nogil:
        int CODEC_FLAG_EMU_EDGE
        int CODEC_FLAG2_FAST
        int CODEC_CAP_DR1
        struct AVCodec:
            int capabilities
            const AVClass *priv_class
            AVCodecID id
            uint8_t max_lowres
        struct AVCodecContext:
            int64_t pts_correction_num_faulty_pts  # Number of incorrect PTS values so far
            int64_t pts_correction_num_faulty_dts  # Number of incorrect DTS values so far
            AVRational sample_aspect_ratio
            AVRational time_base
            AVCodecID codec_id
            AVMediaType codec_type
            int workaround_bugs
            int lowres
            int error_concealment
            int flags
            int flags2
            int sample_rate
            int channels
            uint64_t channel_layout
            AVSampleFormat sample_fmt
        struct AVSubtitle:
            uint16_t format
            uint32_t start_display_time # relative to packet pts, in ms
            uint32_t end_display_time   # relative to packet pts, in ms
            unsigned num_rects
            AVSubtitleRect **rects
            int64_t pts
        struct AVFrame:
            AVPictureType pict_type
            AVRational sample_aspect_ratio
            int width, height
            int format
            int64_t pts
            int64_t pkt_pts
            int64_t pkt_dts
            int sample_rate
            int nb_samples
            uint64_t channel_layout
            uint8_t **extended_data
            uint8_t **data
            int *linesize
        struct AVPicture:
            uint8_t **data
            int *linesize
        struct AVSubtitleRect:
            int x         #///< top left corner  of pict, undefined when pict is not set
            int y         #///< top left corner  of pict, undefined when pict is not set
            int w         #///< width            of pict, undefined when pict is not set
            int h         #///< height           of pict, undefined when pict is not set
            AVPicture pict
            int nb_colors
            char *text
            char *ass
            AVSubtitleType type
        enum AVSubtitleType:
            SUBTITLE_NONE
            SUBTITLE_BITMAP
            SUBTITLE_TEXT
            SUBTITLE_ASS
        int64_t av_frame_get_best_effort_timestamp(const AVFrame *)
        int av_dup_packet(AVPacket *)
        void av_free_packet(AVPacket *)
        void avcodec_free_frame(AVFrame **)
        void avsubtitle_free(AVSubtitle *)
        void av_fast_malloc(void *, unsigned int *, size_t)
        void avcodec_register_all()
        int avcodec_close(AVCodecContext *)
        int avcodec_decode_video2(AVCodecContext *, AVFrame *, int *, const AVPacket *)
        void avcodec_flush_buffers(AVCodecContext *)
        int av_lockmgr_register(lockmgr_func)
        void av_init_packet(AVPacket *)
        enum AVLockOp:
            AV_LOCK_CREATE,
            AV_LOCK_OBTAIN,
            AV_LOCK_RELEASE,
            AV_LOCK_DESTROY,
        void av_picture_copy(AVPicture *, const AVPicture *,
                             AVPixelFormat, int, int)
        AVFrame *avcodec_alloc_frame()
        void avcodec_get_frame_defaults(AVFrame *)
        int avcodec_decode_subtitle2(AVCodecContext *, AVSubtitle *,
                                     int *, AVPacket *)
        int avcodec_decode_audio4(AVCodecContext *, AVFrame *, int *, const AVPacket *)
        enum AVCodecID:
            pass
        AVCodec *avcodec_find_decoder(AVCodecID)
        AVCodec *avcodec_find_encoder(AVCodecID)
        AVCodec *avcodec_find_decoder_by_name(const char *)
        const AVClass *avcodec_get_class()
        int avcodec_open2(AVCodecContext *, const AVCodec *, AVDictionary **)
        enum AVDiscard:
            AVDISCARD_DEFAULT,
            AVDISCARD_ALL
        int av_copy_packet(AVPacket *, AVPacket *)

    extern from "libavfilter/avfilter.h" nogil:
        struct AVFilterContext:
            AVFilterLink **inputs
        struct AVFilterLink:
            AVRational time_base
            int sample_rate
            int channels
            uint64_t channel_layout
        struct AVFilterGraph:
            char *scale_sws_opts
        struct AVFilterInOut:
            char *name
            AVFilterContext *filter_ctx
            int pad_idx
            AVFilterInOut *next
        struct AVFilter:
            pass
        void avfilter_register_all()
        AVFilterInOut *avfilter_inout_alloc()
        void avfilter_inout_free(AVFilterInOut **)
        int avfilter_graph_parse_ptr(AVFilterGraph *, const char *,
                                     AVFilterInOut **, AVFilterInOut **,
                                     void *)
        int avfilter_link(AVFilterContext *, unsigned,
                          AVFilterContext *, unsigned)
        int avfilter_graph_config(AVFilterGraph *, void *)
        int avfilter_graph_create_filter(AVFilterContext **, const AVFilter *,
                                         const char *, const char *, void *,
                                         AVFilterGraph *)
        AVFilter *avfilter_get_by_name(const char *)
        void avfilter_graph_free(AVFilterGraph **)
        AVFilterGraph *avfilter_graph_alloc()

    extern from "libavfilter/buffersink.h" nogil:
        pass

    extern from "libavfilter/buffersrc.h" nogil:
        int av_buffersrc_add_frame(AVFilterContext *, AVFrame *)
        int av_buffersink_get_frame_flags(AVFilterContext *, AVFrame *, int)
    #endif

cdef:
    struct MyAVPacketList:
        AVPacket pkt
        MyAVPacketList *next
        int serial
    struct VideoPicture:
        double pts             # presentation timestamp for this picture
        int64_t pos            # byte position in file
        AVFrame *pict
        int width, height  # source height & width
        int allocated
        int reallocate
        int serial
        AVRational sar
    struct SubPicture:
        double pts # presentation time stamp for this picture
        AVSubtitle sub
        int serial
    struct AudioParams:
        int freq
        int channels
        int64_t channel_layout
        AVSampleFormat fmt
    enum:
        AV_SYNC_AUDIO_MASTER, # default choice
        AV_SYNC_VIDEO_MASTER,
        AV_SYNC_EXTERNAL_CLOCK, # synchronize to an external clock
