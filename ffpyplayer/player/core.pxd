
include '../includes/ffmpeg.pxi'

from ffpyplayer.player.queue cimport FFPacketQueue
from ffpyplayer.player.frame_queue cimport FrameQueue, Frame
from ffpyplayer.player.decoder cimport Decoder
from ffpyplayer.threading cimport MTGenerator, MTThread, MTMutex, MTCond
from ffpyplayer.player.clock cimport Clock
from ffpyplayer.pic cimport Image
from cpython.ref cimport PyObject


cdef struct AudioParams:
    int freq
    int channels
    int64_t channel_layout
    AVSampleFormat fmt
    int frame_size
    int bytes_per_sec


cdef class VideoState(object):
    cdef:
        MTThread read_tid
        const AVInputFormat *iformat
        int abort_request
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
        int reached_eof
        int eof
        int audio_dev

        Clock audclk
        Clock vidclk
        Clock extclk

        FrameQueue pictq
        FrameQueue subpq
        FrameQueue sampq

        Decoder auddec
        Decoder viddec
        Decoder subdec

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

        IF USE_SDL2_MIXER:
            uint8_t chunk_buf[AUDIO_MIN_BUFFER_SIZE]
            Mix_Chunk *chunk
            int audio_count

        uint8_t *audio_buf
        uint8_t *audio_buf1
        unsigned int audio_buf_size # in bytes
        unsigned int audio_buf1_size
        int audio_buf_index # in bytes
        int audio_write_buf_size
        AudioParams audio_src
        IF CONFIG_AVFILTER:
            AudioParams audio_filter_src
        AudioParams audio_tgt
        SwrContext *swr_ctx
        int frame_drops_early
        int frame_drops_late

        int16_t sample_array[SAMPLE_ARRAY_SIZE]
        int sample_array_index

        int subtitle_stream
        AVStream *subtitle_st
        FFPacketQueue subtitleq

        double frame_timer
        double frame_last_returned_time
        double frame_last_filter_delay
        int video_stream
        AVStream *video_st
        FFPacketQueue videoq
        double max_frame_duration      # maximum duration of a frame - above this, we consider the jump a timestamp discontinuity

        IF CONFIG_AVFILTER:
            int vfilter_idx
            AVFilterContext *in_video_filter   # the first filter in the video chain
            AVFilterContext *out_video_filter  # the last filter in the video chain
            AVFilterContext *in_audio_filter   # the first filter in the audio chain
            AVFilterContext *out_audio_filter  # the last filter in the audio chain
            AVFilterContext *split_audio_filter  # the last filter in the audio chain
            AVFilterGraph *agraph              # audio filter graph

        int last_video_stream, last_audio_stream, last_subtitle_stream

        MTCond continue_read_thread
        MTGenerator mt_gen
        VideoSettings *player
        int64_t last_time

        MTCond pause_cond
        double last_clock
        PyObject *self_id

        dict metadata

        object callback
        int is_ref
        AVPixelFormat pix_fmt


    cdef int cInit(self, MTGenerator mt_gen, VideoSettings *player, int paused,
                   AVPixelFormat out_fmt) nogil except 1
    cdef int cquit(VideoState self) nogil except 1
    cdef int request_thread_s(self, char *name, char *msg) nogil except 1
    cdef int request_thread(self, char *name, object msg) nogil except 1
    cdef int request_thread_py(self, object name, object msg) except 1
    cdef object get_out_pix_fmt(self)
    cdef void set_out_pix_fmt(self, AVPixelFormat out_fmt)
    cdef int get_master_sync_type(VideoState self) nogil
    cdef double get_master_clock(VideoState self) nogil except? 0.0
    cdef int check_external_clock_speed(VideoState self) nogil except 1
    cdef int stream_seek(VideoState self, int64_t pos, int64_t rel, int seek_by_bytes, int flush) nogil except 1
    cdef int seek_chapter(VideoState self, int incr, int flush) nogil except 1
    cdef int toggle_pause(VideoState self) nogil except 1
    cdef double compute_target_delay(VideoState self, double delay) nogil except? 0.0
    cdef double vp_duration(VideoState self, Frame *vp, Frame *nextvp) nogil except? 0.0
    cdef void update_video_pts(VideoState self, double pts, int64_t pos, int serial) nogil
    cdef int video_refresh(VideoState self, Image next_image, double *pts, double *remaining_time,
                           int force_refresh) nogil except -1
    cdef int get_video_frame(VideoState self, AVFrame *frame) nogil except 2
    IF CONFIG_AVFILTER:
        cdef int configure_filtergraph(VideoState self, AVFilterGraph *graph, const char *filtergraph,
                                       AVFilterContext *source_ctx, AVFilterContext *sink_ctx) nogil except? 1
        cdef int configure_video_filters(VideoState self, AVFilterGraph *graph,
                                         const char *vfilters, AVFrame *frame,
                                         AVPixelFormat pix_fmt) nogil except? 1
        cdef int configure_audio_filters(VideoState self, const char *afilters,
                                         int force_output_format) nogil except? 1
    cdef int audio_thread(self) nogil except? 1
    cdef int video_thread(VideoState self) nogil except? 1
    cdef int subtitle_thread(VideoState self) nogil except 1
    cdef int subtitle_display(self, AVSubtitle *sub) nogil except 1
    cdef int update_sample_display(VideoState self, int16_t *samples, int samples_size) nogil except 1
    cdef int synchronize_audio(VideoState self, int nb_samples) nogil except -1
    cdef int audio_decode_frame(VideoState self) nogil except? 1
    cdef int sdl_audio_callback(VideoState self, uint8_t *stream, int len) nogil except 1
    cdef inline int open_audio_device(VideoState self, SDL_AudioSpec *wanted_spec, SDL_AudioSpec *spec) nogil except 1
    cdef int audio_open(VideoState self, int64_t wanted_channel_layout, int wanted_nb_channels,
                        int wanted_sample_rate, AudioParams *audio_hw_params) nogil except? 1
    cdef int stream_component_open(VideoState self, int stream_index) nogil except 1
    cdef int stream_component_close(VideoState self, int stream_index) nogil except 1
    cdef int read_thread(VideoState self) nogil except 1
    cdef int stream_has_enough_packets(self, AVStream *st, int stream_id, FFPacketQueue queue) nogil
    cdef inline int failed(VideoState self, int ret, AVFormatContext *ic, AVPacket **pkt) nogil except 1
    cdef int stream_select_program(VideoState self, int requested_program) nogil except 1
    cdef int stream_select_channel(VideoState self, int codec_type, unsigned int requested_stream) nogil except 1
    cdef int stream_cycle_channel(VideoState self, int codec_type) nogil except 1
    cdef int decode_interrupt_cb(VideoState self) nogil


cdef struct VideoSettings:
    unsigned sws_flags
    int loglevel

    const AVInputFormat *file_iformat
    char *input_filename
    int screen_width
    int screen_height
    uint8_t audio_volume
    int muted
    int audio_sdl
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
    int find_stream_info
    int filter_threads

    #/* current context */
    int64_t audio_callback_time

    SwsContext *img_convert_ctx
    AVDictionary *format_opts
    AVDictionary *codec_opts
    AVDictionary *resample_opts
    AVDictionary *sws_dict
    AVDictionary *swr_opts
