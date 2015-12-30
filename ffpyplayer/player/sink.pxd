
include "includes/ffmpeg.pxi"

from ffpyplayer.threading cimport MTMutex

cdef class VideoSink(object):
    cdef AVPixelFormat pix_fmt

    cdef AVPixelFormat _get_out_pix_fmt(VideoSink self) nogil
    cdef object get_out_pix_fmt(VideoSink self)
    cdef void set_out_pix_fmt(VideoSink self, AVPixelFormat out_fmt)
    cdef int subtitle_display(VideoSink self, AVSubtitle *sub) nogil except 1


cdef struct VideoSettings:
    unsigned sws_flags

    AVInputFormat *file_iformat
    char *input_filename
    int screen_width
    int screen_height
    uint8_t audio_volume
    int muted
    int audio_disable
    int video_disable
    int subtitle_disable
    const char* wanted_stream_spec[<int>AVMEDIA_TYPE_NB]
    int seek_by_bytes
    int show_status
    int av_sync_type
    int64_t start_time
    int64_t duration
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
    const char **vfilters_list
    int nb_vfilters
    char *afilters
    char *avfilters

    int autorotate

    #/* current context */
    int64_t audio_callback_time

    SwsContext *img_convert_ctx
    AVDictionary *format_opts
    AVDictionary *codec_opts
    AVDictionary *resample_opts
    AVDictionary *sws_dict
    AVDictionary *swr_opts
