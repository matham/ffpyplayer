
include "ff_defs.pxi"

cimport ffthreading
from ffthreading cimport MTMutex

cdef class VideoSink(object):
    cdef MTMutex alloc_mutex
    cdef object callback
    cdef int requested_alloc
    cdef int use_ref

    cdef AVPixelFormat * get_out_pix_fmts(VideoSink self) nogil
    cdef void set_out_pix_fmt(VideoSink self, AVPixelFormat out_fmt) nogil
    cdef int request_thread(VideoSink self, uint8_t type) nogil except 1
    cdef int peep_alloc(VideoSink self) nogil except 1
    cdef int alloc_picture(VideoSink self, VideoPicture *vp) nogil except 1
    cdef void free_alloc(VideoSink self, VideoPicture *vp) nogil
    cdef int copy_picture(VideoSink self, VideoPicture *vp, AVFrame *src_frame,
                           VideoSettings *player) nogil except 1
    cdef object video_image_display(VideoSink self, VideoPicture *vp) with gil
    cdef int subtitle_display(VideoSink self, AVSubtitle *sub) nogil except 1


cdef struct VideoSettings:
    int64_t sws_flags

    AVInputFormat *file_iformat
    char input_filename[1024]
    int screen_width
    int screen_height
    uint8_t volume
    int audio_disable
    int video_disable
    int subtitle_disable
    int use_ref
    int wanted_stream[<int>AVMEDIA_TYPE_NB]
    int seek_by_bytes
    int show_status
    int av_sync_type
    int64_t start_time
    int64_t duration
    int workaround_bugs
    int fast
    int genpts
    int lowres
    int error_concealment
    int decoder_reorder_pts
    int autoexit
    int loop
    int framedrop
    int infinite_buffer
    char *audio_codec_name
    char *subtitle_codec_name
    char *video_codec_name
    char *vfilters
    char *afilters
    char *avfilters

    #/* current context */
    int64_t audio_callback_time

    SwsContext *img_convert_ctx
    SwsContext *sws_opts
    AVDictionary *format_opts, *codec_opts, *swr_opts
