
include "ff_defs.pxi"

from ffpyplayer.ffthreading cimport MTMutex

cdef class VideoSink(object):
    cdef object callback
    cdef AVPixelFormat pix_fmt

    cdef AVPixelFormat _get_out_pix_fmt(VideoSink self) nogil
    cdef object get_out_pix_fmt(VideoSink self)
    cdef void set_out_pix_fmt(VideoSink self, AVPixelFormat out_fmt)
    cdef int request_thread(VideoSink self, uint8_t type) nogil except 1
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

    int autorotate

    #/* current context */
    int64_t audio_callback_time

    SwsContext *img_convert_ctx
    SwsContext *sws_opts
    AVDictionary *format_opts
    AVDictionary *codec_opts
    AVDictionary *swr_opts
