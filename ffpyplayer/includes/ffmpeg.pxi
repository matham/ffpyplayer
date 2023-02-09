
from libc.stdint cimport int64_t, uint64_t, int32_t, uint32_t, uint16_t,\
int16_t, uint8_t, int8_t, uintptr_t

cdef extern from "stdarg.h":
    ctypedef struct va_list:
        pass

ctypedef int (*lockmgr_func)(void **, int)
ctypedef int (*int_void_func)(void *) except? 1

ctypedef float FFTSample

include "ff_consts.pxi"
include "sdl.pxi"


cdef:
    extern from * nogil:
        struct AVPacket:
            uint8_t *data
            int64_t pos
            int64_t pts
            int64_t dts
            int size
            int stream_index
            int flags
            int64_t duration
        enum AVMediaType:
            AVMEDIA_TYPE_UNKNOWN = -1,  #///< Usually treated as AVMEDIA_TYPE_DATA
            AVMEDIA_TYPE_VIDEO,
            AVMEDIA_TYPE_AUDIO,
            AVMEDIA_TYPE_DATA,          #///< Opaque data information usually continuous
            AVMEDIA_TYPE_SUBTITLE,
            AVMEDIA_TYPE_ATTACHMENT,    #///< Opaque data information usually sparse
            AVMEDIA_TYPE_NB,
        struct AVBufferRef:
            pass
        int av_compare_ts(int64_t, AVRational, int64_t, AVRational)
        const char* av_get_media_type_string(AVMediaType)
        const int av_log2(unsigned int)

    extern from "libavformat/avio.h" nogil:
        int AVIO_FLAG_WRITE
        int avio_check(const char *, int)
        int avio_open2(AVIOContext **, const char *, int, const AVIOInterruptCB *,
                       AVDictionary **)
        int avio_close(AVIOContext *)
        struct AVIOContext:
            int error
            int eof_reached
        struct AVIOInterruptCB:
            int (*callback)(void*)
            void *opaque
        int avio_feof(AVIOContext *)
        int64_t avio_tell(AVIOContext *)

    extern from "libavutil/fifo.h" nogil:
        struct AVFifoBuffer:
            uint8_t *buffer
        int av_fifo_space(const AVFifoBuffer *)
        int av_fifo_grow(AVFifoBuffer *, unsigned int)
        int av_fifo_generic_write(AVFifoBuffer *, void *, int, int (*)(void*, void*, int))
        AVFifoBuffer *av_fifo_alloc(unsigned int)
        int av_fifo_size(const AVFifoBuffer *)
        int av_fifo_generic_read(AVFifoBuffer *, void *, int, void (*)(void*, void*, int))
        void av_fifo_freep(AVFifoBuffer **)

    extern from "libavutil/eval.h" nogil:
        double av_strtod(const char *, char **)

    extern from "libavutil/avstring.h" nogil:
         size_t av_strlcpy(char *, const char *, size_t)
         size_t av_strlcatf(char *, size_t, const char *, ...)
         char *av_asprintf(const char *, ...)

    extern from "libavutil/display.h" nogil:
        double av_display_rotation_get (const int32_t [])

    extern from "libavutil/mathematics.h" nogil:
        int64_t av_rescale_q(int64_t, AVRational, AVRational)

    extern from "libavutil/pixdesc.h" nogil:
        struct AVPixFmtDescriptor:
            const char *name
            uint8_t nb_components
        const char *av_get_pix_fmt_name(AVPixelFormat)
        AVPixelFormat av_get_pix_fmt(const char *)
        const AVPixFmtDescriptor *av_pix_fmt_desc_next(const AVPixFmtDescriptor *)
        AVPixelFormat av_pix_fmt_desc_get_id(const AVPixFmtDescriptor *)
        const AVPixFmtDescriptor *av_pix_fmt_desc_get(AVPixelFormat)

    extern from "libavutil/imgutils.h" nogil:
        int av_image_alloc(uint8_t **, int *, int, int, AVPixelFormat, int)
        int av_image_fill_linesizes(int *, AVPixelFormat, int)
        void av_image_copy(uint8_t **, int *, const uint8_t **, const int *,
                           AVPixelFormat, int, int)
        int av_image_fill_pointers(uint8_t **, AVPixelFormat, int, uint8_t *,
                                   const int *linesizes)
        int av_image_fill_arrays(uint8_t **, int *, const uint8_t *,
                                 AVPixelFormat, int, int, int)

    extern from "libavutil/dict.h" nogil:
        int AV_DICT_MATCH_CASE
        int AV_DICT_DONT_OVERWRITE
        int AV_DICT_IGNORE_SUFFIX
        int AV_DICT_DONT_STRDUP_VAL
        struct AVDictionaryEntry:
            char *key
            char *value
        void av_dict_free(AVDictionary **)
        AVDictionaryEntry * av_dict_get(AVDictionary *, const char *,
                                        const AVDictionaryEntry *, int)

    extern from "libavutil/samplefmt.h" nogil:
        enum AVSampleFormat:
            AV_SAMPLE_FMT_S16,
            AV_SAMPLE_FMT_NONE,
        AVSampleFormat av_get_packed_sample_fmt(AVSampleFormat)
        const char *av_get_sample_fmt_name(AVSampleFormat)
        int av_samples_get_buffer_size(int *, int, int, AVSampleFormat, int)
        int av_get_bytes_per_sample(AVSampleFormat)

    extern from "libavutil/time.h" nogil:
        int av_usleep(unsigned)
        int64_t av_gettime_relative()

    extern from "libavutil/cpu.h" nogil:
        int av_get_cpu_flags()
        int av_parse_cpu_caps(unsigned *, const char *)
        void av_force_cpu_flags(int)

    extern from * nogil:
        void av_free(void *)
        void av_freep(void *)
        void *av_malloc(size_t)
        void *av_realloc_array(void *, size_t, size_t)
        char *av_strdup(const char *)
        int av_get_channel_layout_nb_channels(uint64_t)
        void av_get_channel_layout_string(char *, int, int, uint64_t)
        int64_t av_get_default_channel_layout(int)
        int av_clip(int a, int amin, int amax)
        int64_t AV_CH_LAYOUT_STEREO_DOWNMIX

        struct AVRational:
            int num #///< numerator
            int den #///< denominator
        double av_q2d(AVRational)
        int av_find_nearest_q_idx(AVRational, const AVRational*)

        int AV_LOG_QUIET
        int AV_LOG_PANIC
        int AV_LOG_FATAL
        int AV_LOG_ERROR
        int AV_LOG_WARNING
        int AV_LOG_INFO
        int AV_LOG_VERBOSE
        int AV_LOG_DEBUG
        int AV_LOG_TRACE
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
        int av_dict_set_int(AVDictionary **, const char *, int64_t, int)

        void av_max_alloc(size_t)

        void *av_mallocz(size_t)

        int AVERROR(int)
        int AVUNERROR(int)

        enum AVPictureType:
            AV_PICTURE_TYPE_NONE
        char av_get_picture_type_char(AVPictureType)
        void av_frame_unref(AVFrame *)
        void av_frame_free(AVFrame **)
        void av_frame_move_ref(AVFrame *, AVFrame *)
        AVFrame* av_frame_clone(const AVFrame *)
        int av_frame_copy_props(AVFrame *, const AVFrame *)
        int av_frame_get_buffer(AVFrame *, int)
        unsigned av_int_list_length_for_size(unsigned, const void *, uint64_t)
        int av_opt_set_bin(void *, const char *, const uint8_t *, int, int)

        AVFrame *av_frame_alloc()
        int64_t av_frame_get_pkt_pos(const AVFrame *)
        int av_frame_get_channels(const AVFrame *)

        int AVERROR_EOF
        int AVERROR_OPTION_NOT_FOUND
        int av_strerror(int, char *, size_t)

        void *av_x_if_null(const void *p, const void *x)

        int64_t AV_TIME_BASE
        AVRational AV_TIME_BASE_Q

        struct AVClass:
            pass

    extern from "libavformat/avformat.h" nogil:
        int AVSEEK_FLAG_BYTE
        int AVFMT_NOBINSEARCH
        int AVFMT_NOGENSEARCH
        int AVFMT_NO_BYTE_SEEK
        int AVFMT_FLAG_GENPTS
        int AVFMT_TS_DISCONT
        int AV_DISPOSITION_ATTACHED_PIC
        int AVFMT_GLOBALHEADER
        int AVFMT_VARIABLE_FPS
        int AVFMT_NOTIMESTAMPS
        int AVFMT_NOFILE
        int AVFMT_RAWPICTURE
        struct AVChapter:
            int id
            AVRational time_base
            int64_t start
            int64_t end
            AVDictionary *metadata
        struct AVInputFormat:
            int (*read_seek)(AVFormatContext *, int, int64_t, int)
            int (*get_device_list)(AVFormatContext *, AVDeviceInfoList *)
            int (*create_device_capabilities)(AVFormatContext *, AVDeviceCapabilitiesQuery *)
            int flags
            const char *name
            const char *long_name
            const char *extensions
        struct AVCodecTag:
            pass
        struct AVOutputFormat:
            const char *name
            const char *long_name
            const char *extensions
            int flags
            AVCodecID video_codec
            const AVCodecTag* const* codec_tag
        struct AVFormatContext:
            AVInputFormat *iformat
            AVOutputFormat *oformat
            AVStream **streams
            AVProgram **programs
            unsigned int nb_streams
            unsigned int nb_programs
            AVIOContext *pb
            AVDictionary *metadata
            AVIOInterruptCB interrupt_callback
            int flags
            int64_t start_time
            int bit_rate
            int64_t duration
            unsigned int nb_chapters
            AVChapter **chapters
            char *url
        struct AVStream:
            int index
            AVRational time_base
            int64_t start_time
            AVDiscard discard
            AVPacket attached_pic
            int disposition
            AVRational avg_frame_rate
            AVRational r_frame_rate
            AVDictionary *metadata
            AVCodecParameters *codecpar
        struct AVProgram:
            int id
            unsigned int nb_stream_indexes
            unsigned int *stream_index
        enum  AVPacketSideDataType:
            AV_PKT_DATA_DISPLAYMATRIX
        void av_format_inject_global_side_data(AVFormatContext *)
        int avformat_network_init()
        int avformat_network_deinit()
        AVInputFormat *av_find_input_format(const char *)
        AVRational av_guess_sample_aspect_ratio(AVFormatContext *, AVStream *, AVFrame *)
        AVRational av_guess_frame_rate(AVFormatContext *, AVStream *, AVFrame *)
        int avformat_match_stream_specifier(AVFormatContext *, AVStream *,
                                            const char *)
        AVFormatContext *avformat_alloc_context()
        int avformat_open_input(AVFormatContext **, const char *, AVInputFormat *, AVDictionary **)
        void avformat_close_input(AVFormatContext **)
        int avformat_find_stream_info(AVFormatContext *, AVDictionary **)
        int avformat_seek_file(AVFormatContext *, int, int64_t, int64_t, int64_t, int)
        int av_find_best_stream(AVFormatContext *, AVMediaType, int, int, AVCodec **, int)
        void av_dump_format(AVFormatContext *, int, const char *, int)
        int av_read_pause(AVFormatContext *)
        int av_read_play(AVFormatContext *)
        int av_read_frame(AVFormatContext *, AVPacket *)
        AVProgram *av_find_program_from_stream(AVFormatContext *, AVProgram *, int)
        int avformat_write_header(AVFormatContext *, AVDictionary **)
        int av_write_trailer(AVFormatContext *)
        int avformat_alloc_output_context2(AVFormatContext **, AVOutputFormat *,
                                           const char *, const char *)
        AVStream *avformat_new_stream(AVFormatContext *, const AVCodec *)
        int av_interleaved_write_frame(AVFormatContext *, AVPacket *)
        void avformat_free_context(AVFormatContext *)
        uint8_t *av_stream_get_side_data (AVStream *, AVPacketSideDataType, int *)
        const AVOutputFormat *av_muxer_iterate(void **)
        const AVInputFormat *av_demuxer_iterate(void **)

    extern from "libavdevice/avdevice.h" nogil:
        void avdevice_register_all()
        struct AVDeviceInfo:
            char *device_name
            char *device_description
        struct AVDeviceInfoList:
            AVDeviceInfo **devices
            int nb_devices
            int default_device
        struct AVDeviceCapabilitiesQuery:
            pass

    extern from "libswscale/swscale.h" nogil:
        int SWS_BICUBIC
        struct SwsContext:
            pass
        struct SwsFilter:
            pass
        const AVClass *sws_get_class()
        SwsContext *sws_getContext(int, int, AVPixelFormat, int, int, AVPixelFormat,
                                   int, SwsFilter *, SwsFilter *, const double *)
        SwsContext *sws_getCachedContext(SwsContext *, int, int, AVPixelFormat,
                                        int, int, AVPixelFormat, int, SwsFilter *,
                                        SwsFilter *, const double *)
        int sws_scale(SwsContext *, const uint8_t *const [], const int[], int, int,
                      uint8_t *const [], const int[])
        void sws_freeContext(SwsContext *)

    extern from "libavutil/frame.h" nogil:
        enum AVFrameSideDataType:
            AV_FRAME_DATA_DISPLAYMATRIX,
        struct AVFrameSideData:
            uint8_t *data
        AVFrameSideData *av_frame_get_side_data(const AVFrame *, AVFrameSideDataType)

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
        int av_opt_eval_flags(void *, const AVOption *, const char *, int *)
        int av_opt_get_int(void *, const char *, int, int64_t *)
        int av_opt_set_int(void *, const char *, int64_t, int)
        int av_opt_set_image_size(void *, const char *, int, int, int)
        int av_opt_set(void *, const char *, const char *, int)
        const AVOption *av_opt_find(void *, const char *, const char *, int, int)

    extern from "libavcodec/packet.h" nogil:
        int av_packet_ref(AVPacket *, const AVPacket *)
        void av_packet_unref(AVPacket *)
        void av_packet_move_ref(AVPacket *, AVPacket *)
        AVPacket *av_packet_alloc()
        void av_packet_free(AVPacket **)

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

    extern from "libavcodec/version.h" nogil:
        pass

    extern from "libswresample/swresample.h" nogil:
        struct SwrContext:
            pass
        void swr_free(SwrContext **)
        SwrContext *swr_alloc_set_opts(SwrContext *, int64_t, AVSampleFormat,
                                       int, int64_t, AVSampleFormat, int, int, void *)
        int swr_init(SwrContext *)
        int swr_set_compensation(SwrContext *, int, int)
        int swr_convert(SwrContext *, uint8_t **, int, const uint8_t ** , int)

    extern from "libavcodec/avcodec.h" nogil:
        int AV_CODEC_FLAG2_FAST
        int AV_CODEC_CAP_DR1
        int AV_CODEC_FLAG_GLOBAL_HEADER
        int AV_PKT_FLAG_KEY
        int AV_CODEC_CAP_DELAY
        struct AVCodec:
            const char *name
            int capabilities
            const AVClass *priv_class
            AVCodecID id
            uint8_t max_lowres
            const AVRational *supported_framerates
            const AVPixelFormat *pix_fmts
            AVMediaType type
        struct AVCodecContext:
            int width
            int height
            int64_t pts_correction_num_faulty_pts  # Number of incorrect PTS values so far
            int64_t pts_correction_num_faulty_dts  # Number of incorrect DTS values so far
            AVRational sample_aspect_ratio
            AVRational time_base
            const AVCodec *codec
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
            AVPixelFormat pix_fmt
            AVFrame *coded_frame
            AVRational pkt_timebase
        struct AVCodecParameters:
            AVCodecID codec_id
            AVMediaType codec_type
            AVRational sample_aspect_ratio
            int sample_rate
            int channels
        struct AVSubtitle:
            uint16_t format
            uint32_t start_display_time # relative to packet pts, in ms
            uint32_t end_display_time   # relative to packet pts, in ms
            unsigned num_rects
            AVSubtitleRect **rects
            int64_t pts
        struct AVFrame:
            int top_field_first
            int interlaced_frame
            AVPictureType pict_type
            AVRational sample_aspect_ratio
            int width, height
            int format
            int key_frame
            int64_t pts
            int64_t pkt_pts
            int64_t pkt_dts
            int sample_rate
            int nb_samples
            uint64_t channel_layout
            uint8_t **extended_data
            int64_t best_effort_timestamp
            uint8_t **data
            int *linesize
            int channels
            int64_t pkt_pos
            AVBufferRef **buf
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
        AVRational av_codec_get_pkt_timebase(const AVCodecContext *)
        int64_t av_frame_get_best_effort_timestamp(const AVFrame *)
        int av_codec_get_max_lowres(const AVCodec *)
        void av_codec_set_lowres(AVCodecContext *, int)
        int avcodec_parameters_from_context(AVCodecParameters *, const AVCodecContext *)
        int av_dup_packet(AVPacket *)
        void av_packet_unref(AVPacket *)
        void avsubtitle_free(AVSubtitle *)
        void av_fast_malloc(void *, unsigned int *, size_t)
        void avcodec_register_all()
        int avcodec_close(AVCodecContext *)
        int avcodec_send_packet(AVCodecContext *, const AVPacket *)
        int avcodec_receive_frame(AVCodecContext *, AVFrame *)
        void avcodec_flush_buffers(AVCodecContext *)
        void av_init_packet(AVPacket *)
        int avcodec_parameters_to_context(AVCodecContext *, const AVCodecParameters *)
        void av_codec_set_pkt_timebase(AVCodecContext *, AVRational)
        void av_picture_copy(AVPicture *, const AVPicture *,
                             AVPixelFormat, int, int)
        AVFrame* av_frame_alloc()
        int avcodec_decode_subtitle2(AVCodecContext *, AVSubtitle *,
                                     int *, AVPacket *)
        int avcodec_decode_audio4(AVCodecContext *, AVFrame *, int *, const AVPacket *)
        enum AVCodecID:
            AV_CODEC_ID_NONE
            AV_CODEC_ID_RAWVIDEO
        AVCodec *avcodec_find_decoder(AVCodecID)
        AVCodec *avcodec_find_encoder(AVCodecID)
        AVCodec *avcodec_find_encoder_by_name(const char *)
        AVCodec *avcodec_find_decoder_by_name(const char *)
        const AVClass *avcodec_get_class()
        AVCodecContext *avcodec_alloc_context3(const AVCodec *)
        void avcodec_free_context(AVCodecContext **)
        int avcodec_open2(AVCodecContext *, const AVCodec *, AVDictionary **)
        enum AVDiscard:
            AVDISCARD_DEFAULT,
            AVDISCARD_ALL
        int av_copy_packet(AVPacket *, AVPacket *)
        struct AVCodecDescriptor:
            AVCodecID id
            const char *name
            AVMediaType type
        const AVCodecDescriptor *avcodec_descriptor_get(AVCodecID)
        const AVCodecDescriptor *avcodec_descriptor_next(const AVCodecDescriptor *)
        const AVCodecDescriptor *avcodec_descriptor_get_by_name(const char *)
        AVPixelFormat avcodec_find_best_pix_fmt_of_list(AVPixelFormat *, AVPixelFormat,
                                                        int, int *)
        int avpicture_fill(AVPicture *, const uint8_t *, AVPixelFormat, int, int)
        int avcodec_encode_video2(AVCodecContext *, AVPacket *, const AVFrame *, int *)
        const char *avcodec_get_name(AVCodecID)
        const AVCodec *av_codec_iterate(void **)
        int av_codec_is_encoder(const AVCodec *)
        int av_codec_is_decoder(const AVCodec *)
        int avcodec_send_frame(AVCodecContext *, const AVFrame *)
        int avcodec_receive_packet(AVCodecContext *, AVPacket *)

    extern from "libavfilter/avfilter.h" nogil:
        struct AVFilterContext:
            AVFilterLink **inputs
        struct AVFilterLink:
            AVRational time_base
            int sample_rate
            int channels
            uint64_t channel_layout
            AVRational frame_rate
        struct AVFilterGraph:
            char *scale_sws_opts
            unsigned nb_filters
            AVFilterContext **filters
            int nb_threads
        struct AVFilterInOut:
            char *name
            AVFilterContext *filter_ctx
            int pad_idx
            AVFilterInOut *next
        struct AVFilter:
            pass
        int avfilter_link_get_channels(AVFilterLink *)
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
        int av_buffersink_get_frame_flags(AVFilterContext *, AVFrame *, int)
        AVRational av_buffersink_get_time_base(const AVFilterContext *)
        AVRational av_buffersink_get_frame_rate(const AVFilterContext *)
        int av_buffersink_get_sample_rate(const AVFilterContext *)
        int av_buffersink_get_channels(const AVFilterContext *)
        uint64_t av_buffersink_get_channel_layout(const AVFilterContext *)

    extern from "libavfilter/buffersrc.h" nogil:
        int av_buffersrc_add_frame(AVFilterContext *, AVFrame *)

    extern from "clib/misc.h" nogil:
        uint8_t INDENT
        uint8_t SHOW_VERSION
        uint8_t SHOW_CONFIG
        void print_all_libs_info(int, int)
        int opt_default(
            const char *, const char *, SwsContext *, AVDictionary **, AVDictionary **,
            AVDictionary **, AVDictionary **, AVDictionary **)
        int get_plane_sizes(int *, int *, AVPixelFormat, int, const int *)

cdef enum:
    AV_SYNC_AUDIO_MASTER, # default choice
    AV_SYNC_VIDEO_MASTER,
    AV_SYNC_EXTERNAL_CLOCK, # synchronize to an external clock
