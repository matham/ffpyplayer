
include "ff_defs.pxi"

cdef enum Video_lib:
    SDL_Video,
    Py_Video

cimport ffcore
from ffcore cimport VideoState
cimport ffthreading
from ffthreading cimport MTMutex

cdef class VideoSink(object):
    cdef Video_lib lib
    cdef MTMutex alloc_mutex
    cdef MTMutex settings_mutex
    cdef object callback
    cdef int requested_alloc
    cdef double remaining_time

    cdef AVPixelFormat * get_out_pix_fmts(VideoSink self) nogil
    cdef void request_thread(VideoSink self, void *data, uint8_t type) nogil
    cdef int peep_alloc(VideoSink self) nogil
    cdef int video_open(VideoSink self, int force_set_video_mode, VideoPicture *vp,
                        VideoSettings *player, int *width, int *height) nogil
    cdef void alloc_picture(VideoSink self, VideoPicture *vp, VideoSettings *player,
                            int *width, int *height) nogil
    cdef void free_alloc(VideoSink self, VideoPicture *vp) nogil
    cdef void copy_picture(VideoSink self, VideoPicture *vp, AVFrame *src_frame,
                           VideoSettings *player) nogil
    cdef void video_image_display(VideoSink self, SDL_Surface *screen, VideoState ist) nogil
    cdef void SDL_Initialize(VideoSink self, VideoState vs) nogil
    cdef void event_loop(VideoSink self, VideoState vs) nogil
    

cdef struct VideoSettings:
    int64_t sws_flags

    AVInputFormat *file_iformat
    char *input_filename
    char *window_title
    int fs_screen_width
    int fs_screen_height
    int default_width
    int default_height
    int screen_width
    int screen_height
    int audio_disable
    int video_disable
    int subtitle_disable
    int wanted_stream[<int>AVMEDIA_TYPE_NB]
    int seek_by_bytes
    int display_disable
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
    int exit_on_keydown
    int exit_on_mousedown
    int loop
    int framedrop
    int infinite_buffer
    ShowMode show_mode
    char *audio_codec_name
    char *subtitle_codec_name
    char *video_codec_name
    double rdftspeed
    int64_t cursor_last_shown
    int cursor_hidden
    #IF CONFIG_AVFILTER:
    char *vfilters
    char *afilters
    
    #/* current context */
    int is_full_screen
    int64_t audio_callback_time
    
    
    SDL_Surface *screen
    
    SwsContext *img_convert_ctx
    SwsContext *sws_opts
    AVDictionary *swr_opts
    AVDictionary *format_opts, *codec_opts, *resample_opts
    int dummy



cdef void calculate_display_rect(SDL_Rect *rect, int scr_xleft, int scr_ytop,
                                 int scr_width, int scr_height, VideoPicture *vp) nogil
cdef void duplicate_right_border_pixels(SDL_Overlay *bmp) nogil
cdef void video_audio_display(SDL_Surface *screen, VideoState s, int64_t *audio_callback_time) nogil
cdef inline void fill_rectangle(SDL_Surface *screen, int x, int y, int w,
                                int h, int color, int update) nogil