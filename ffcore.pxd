
include 'ff_defs.pxi'

cimport ffqueue
from ffqueue cimport FFPacketQueue
cimport ffthreading
from ffthreading cimport MTGenerator, MTThread, MTMutex, MTCond
cimport ffclock
from ffclock cimport Clock
from cpython.ref cimport PyObject


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
    
    SwsContext *sws_opts
    AVDictionary *swr_opts
    AVDictionary *format_opts, *codec_opts, *resample_opts
    int dummy



cdef class VideoState(object):
    cdef:
        MTThread read_tid
        MTThread video_tid
        AVInputFormat *iformat
        int no_background
        int abort_request
        int force_refresh
        int paused
        int last_paused
        int queue_attachments_req
        int seek_req
        int seek_flags
        int64_t seek_pos
        int64_t seek_rel
        int read_pause_return
        AVFormatContext *ic
        int realtime
        int audio_finished
        int video_finished
    
        Clock audclk
        Clock vidclk
        Clock extclk
    
        int audio_stream
    
        int av_sync_type
    
        double audio_clock
        int audio_clock_serial
        double audio_diff_cum # used for AV difference average computation
        double audio_diff_avg_coef
        double audio_diff_threshold
        int audio_diff_avg_count
        AVStream *audio_st
        FFPacketQueue audioq
        int audio_hw_buf_size
        uint8_t silence_buf[AUDIO_BUFFER_SIZE]
        uint8_t *audio_buf
        uint8_t *audio_buf1
        unsigned int audio_buf_size # in bytes
        unsigned int audio_buf1_size
        int audio_buf_index # in bytes
        int audio_write_buf_size
        int audio_buf_frames_pending
        AVPacket audio_pkt_temp
        AVPacket audio_pkt
        int audio_pkt_temp_serial
        int audio_last_serial
        AudioParams audio_src
        IF CONFIG_AVFILTER:
            AudioParams audio_filter_src
        AudioParams audio_tgt
        SwrContext *swr_ctx
        int frame_drops_early
        int frame_drops_late
        AVFrame *frame
        int64_t audio_frame_next_pts
        ShowMode show_mode

        int16_t sample_array[SAMPLE_ARRAY_SIZE]
        int sample_array_index
        int last_i_start
        RDFTContext *rdft
        int rdft_bits
        FFTSample *rdft_data
        int xpos
        double last_vis_time
    
        MTThread subtitle_tid
        int subtitle_stream
        AVStream *subtitle_st
        FFPacketQueue subtitleq
        SubPicture subpq[SUBPICTURE_QUEUE_SIZE]
        int subpq_size, subpq_rindex, subpq_windex
        MTCond subpq_cond
    
        double frame_timer
        double frame_last_pts
        double frame_last_duration
        double frame_last_dropped_pts
        double frame_last_returned_time
        double frame_last_filter_delay
        int64_t frame_last_dropped_pos
        int frame_last_dropped_serial
        int video_stream
        AVStream *video_st
        FFPacketQueue videoq
        int64_t video_current_pos      # current displayed file pos
        double max_frame_duration      # maximum duration of a frame - above this, we consider the jump a timestamp discontinuity
        VideoPicture pictq[VIDEO_PICTURE_QUEUE_SIZE]
        int pictq_size, pictq_rindex, pictq_windex
        MTCond pictq_cond
        IF not CONFIG_AVFILTER:
            SwsContext *img_convert_ctx
        SDL_Rect last_display_rect
    
        char filename[1024]
        int width, height, xleft, ytop
        int step
    
        IF CONFIG_AVFILTER:
            AVFilterContext *in_video_filter   # the first filter in the video chain
            AVFilterContext *out_video_filter  # the last filter in the video chain
            AVFilterContext *in_audio_filter   # the first filter in the audio chain
            AVFilterContext *out_audio_filter  # the last filter in the audio chain
            AVFilterGraph *agraph              # audio filter graph
    
        int last_video_stream, last_audio_stream, last_subtitle_stream
    
        MTCond continue_read_thread
        MTGenerator mt_gen
        VideoSettings *player
        int64_t last_time
        
        double last_clock
        PyObject *self_id
        
        bytes py_pat
        bytes py_m
        
        
    cdef void cInit(VideoState self, MTGenerator mt_gen, char *input_filename,
                    AVInputFormat *file_iformat, int av_sync_type, VideoSettings *player) nogil
    cdef int video_open(VideoState self, int force_set_video_mode, VideoPicture *vp) nogil
    cdef void video_display(VideoState self) nogil
    cdef int get_master_sync_type(VideoState self) nogil
    cdef double get_master_clock(VideoState self) nogil
    cdef void check_external_clock_speed(VideoState self) nogil
    cdef void stream_seek(VideoState self, int64_t pos, int64_t rel, int seek_by_bytes) nogil
    cdef void stream_toggle_pause(VideoState self) nogil
    cdef void toggle_pause(VideoState self) nogil
    cdef void step_to_next_frame(VideoState self) nogil
    cdef double compute_target_delay(VideoState self, double delay) nogil
    cdef void pictq_next_picture(VideoState self) nogil
    cdef int pictq_prev_picture(VideoState self) nogil
    cdef void update_video_pts(VideoState self, double pts, int64_t pos, int serial) nogil
    cdef void video_refresh(VideoState self, double *remaining_time) nogil
    cdef void alloc_picture(VideoState self) nogil
    cdef int queue_picture(VideoState self, AVFrame *src_frame, double pts,
                           int64_t pos, int serial) nogil
    cdef int get_video_frame(VideoState self, AVFrame *frame, AVPacket *pkt, int *serial) nogil
    IF CONFIG_AVFILTER:
        cdef int configure_filtergraph(VideoState self, AVFilterGraph *graph, const char *filtergraph,
                                       AVFilterContext *source_ctx, AVFilterContext *sink_ctx) nogil
        cdef int configure_video_filters(VideoState self, AVFilterGraph *graph,
                                         const char *vfilters, AVFrame *frame) nogil
        cdef int configure_audio_filters(VideoState self, const char *afilters,
                                         int force_output_format) nogil
    cdef int video_thread(VideoState self) nogil
    cdef int subtitle_thread(VideoState self) nogil
    cdef void update_sample_display(VideoState self, int16_t *samples, int samples_size) nogil
    cdef int synchronize_audio(VideoState self, int nb_samples) nogil
    cdef int audio_decode_frame(VideoState self) nogil
    cdef void sdl_audio_callback(VideoState self, uint8_t *stream, int len) nogil
    cdef int audio_open(VideoState self, int64_t wanted_channel_layout, int wanted_nb_channels,
                        int wanted_sample_rate, AudioParams *audio_hw_params) nogil
    cdef int stream_component_open(VideoState self, int stream_index) nogil
    cdef void stream_component_close(VideoState self, int stream_index) nogil
    cdef int read_thread(VideoState self) nogil
    cdef inline int failed(VideoState self, int ret) nogil
    cdef void stream_cycle_channel(VideoState self, int codec_type) nogil
    cdef void toggle_full_screen(VideoState self) nogil
    cdef void toggle_audio_display(VideoState self) nogil
    cdef void refresh_loop_wait_event(VideoState self, SDL_Event *event) nogil
