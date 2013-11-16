
__all__ = ('FFPyPlayer', )

include 'ff_defs_comp.pxi'
include "inline_funcs.pxi"

cdef extern from "Python.h":
    void PyEval_InitThreads()

cdef extern from "math.h" nogil:
    double NAN
    int isnan(double x)



cimport ffthreading
from ffthreading cimport MTGenerator, SDL_MT, Py_MT, MTThread, MTMutex
cimport ffqueue
from ffqueue cimport FFPacketQueue
cimport ffcore
from ffcore cimport VideoState
cimport sink
from sink cimport VideoSettings, VideoSink
from libc.stdio cimport printf
from cpython.ref cimport PyObject


'see http://ffmpeg.org/ffmpeg.html for log levels'
loglevels = {"quiet":AV_LOG_QUIET, "panic":AV_LOG_PANIC, "fatal":AV_LOG_FATAL,
             "error":AV_LOG_ERROR, "warning":AV_LOG_WARNING, "info":AV_LOG_INFO,
             "verbose":AV_LOG_VERBOSE, "debug":AV_LOG_DEBUG}
loglevel_inverse = {v:k for k, v in loglevels.iteritems()}

cdef object _log_callback = None
cdef int _print_prefix
cdef MTMutex _log_mutex= MTMutex(Py_MT)

cdef void _log_callback_func(void* ptr, int level, const char* fmt, va_list vl) nogil:
    cdef char line[2048]
    global _print_prefix
    _log_mutex.lock()
    _print_prefix = 1
    av_log_format_line(ptr, level, fmt, vl, line, sizeof(line), &_print_prefix)
    if _log_callback is not None:
        with gil:
            _log_callback(str(line), loglevel_inverse[level])
    _log_mutex.unlock()

def set_log_callback(object callback):
    global _log_callback
    if callback is not None and not callable(callback):
         raise Exception('Log callback needs to be callable.')
    _log_mutex.lock()
    if callback is None:
        av_log_set_callback(&av_log_default_callback)
    else:
        av_log_set_callback(&_log_callback_func)
    _log_callback = callback
    _log_mutex.unlock()


cdef class FFPyPlayer(object):

    def __cinit__(self, filename, vid_sink, loglevel='error', ff_opts={},
                  thread_lib='python', audio_sink='SDL', **kargs):
        cdef unsigned flags
        cdef VideoSettings *settings = &self.settings
        PyEval_InitThreads()
        print_all_libs_info(INDENT|SHOW_CONFIG,  AV_LOG_INFO)
        print_all_libs_info(INDENT|SHOW_VERSION, AV_LOG_INFO)
        settings.format_opts = settings.codec_opts = NULL
        settings.sws_flags = SWS_BICUBIC
        # set x, or y to -1 to preserve pixel ratio
        settings.screen_width  = ff_opts['x'] if 'x' in ff_opts else 0
        settings.screen_height = ff_opts['y'] if 'y' in ff_opts else 0
        if not CONFIG_AVFILTER and (settings.screen_width or settings.screen_height):
            raise Exception('You can only set the screen size when avfilter is enabled.')
        settings.audio_disable = bool(ff_opts['an']) if 'an' in ff_opts else 0
        settings.video_disable = bool(ff_opts['vn']) if 'vn' in ff_opts else 0
        settings.subtitle_disable = bool(ff_opts['sn']) if 'sn' in ff_opts else 0
        settings.wanted_stream[<int>AVMEDIA_TYPE_AUDIO] = ff_opts['ast'] if 'ast' in ff_opts else -1
        settings.wanted_stream[<int>AVMEDIA_TYPE_VIDEO] = ff_opts['vst'] if 'vst' in ff_opts else -1
        settings.wanted_stream[<int>AVMEDIA_TYPE_SUBTITLE] = ff_opts['sst'] if 'sst' in ff_opts else -1
        settings.start_time = ff_opts['ss'] * 1000000 if 'ss' in ff_opts else AV_NOPTS_VALUE
        settings.duration = ff_opts['t'] * 1000000 if 't' in ff_opts else AV_NOPTS_VALUE
        settings.seek_by_bytes = -1
        if 'bytes' in ff_opts:
            val = ff_opts['bytes']
            if val != 1 and val != 0 and val != -1:
                raise ValueError('Invalid bytes option value.')
            settings.seek_by_bytes = val
        settings.file_iformat = NULL
        if 'f' in ff_opts:
            settings.file_iformat = av_find_input_format(ff_opts['f'])
            if settings.file_iformat == NULL:
                raise ValueError('Unknown input format: %s.' % ff_opts['f'])
        if 'pixel_format' in ff_opts:
            av_dict_set(<AVDictionary **>&settings.format_opts, "pixel_format", ff_opts['pixel_format'], 0)
        settings.show_status = bool(ff_opts['stats']) if 'stats' in ff_opts else 0
        settings.workaround_bugs = bool(ff_opts['bug']) if 'bug' in ff_opts else 1
        settings.fast = bool(ff_opts['fast']) if 'fast' in ff_opts else 0
        settings.genpts = bool(ff_opts['genpts']) if 'genpts' in ff_opts else 0
        settings.decoder_reorder_pts = -1
        if 'drp' in ff_opts:
            val = ff_opts['drp']
            if val != 1 and val != 0 and val != -1:
                raise ValueError('Invalid drp option value.')
            settings.decoder_reorder_pts = val
        settings.lowres = ff_opts['lowres'] if 'lowres' in ff_opts else 0
        settings.error_concealment = ff_opts['ec'] if 'ec' in ff_opts else 3
        settings.av_sync_type = AV_SYNC_AUDIO_MASTER
        settings.volume = SDL_MIX_MAXVOLUME
        if 'sync' in ff_opts:
            val = ff_opts['sync']
            if val == 'audio':
                settings.av_sync_type = AV_SYNC_AUDIO_MASTER
            elif val == 'video':
                settings.av_sync_type = AV_SYNC_VIDEO_MASTER
            elif val == 'ext':
                settings.av_sync_type = AV_SYNC_EXTERNAL_CLOCK
            else:
                raise ValueError('Invalid sync option value.')
        settings.autoexit = ff_opts['autoexit'] if 'autoexit' in ff_opts else 0
        settings.loop = ff_opts['loop'] if 'loop' in ff_opts else 1
        settings.framedrop = bool(ff_opts['framedrop']) if 'framedrop' in ff_opts else -1
        # -1 means not infinite, not respected if real time.
        settings.infinite_buffer = bool(ff_opts['infbuf']) if 'infbuf' in ff_opts else -1
        IF CONFIG_AVFILTER:
            settings.vfilters = NULL
            if 'vf' in ff_opts:
                self.py_vfilters = ff_opts['vf']
                settings.vfilters = self.py_vfilters
            settings.afilters = NULL
            if 'af' in ff_opts:
                self.py_afilters = ff_opts['af']
                settings.afilters = self.py_afilters
            settings.avfilters = NULL
            if 'avf' in ff_opts:
                self.py_avfilters = ff_opts['avf']
                settings.avfilters = self.py_avfilters
        settings.audio_codec_name = NULL
        if 'acodec' in ff_opts:
            self.py_audio_codec_name = ff_opts['acodec']
            settings.audio_codec_name = self.py_audio_codec_name
        settings.video_codec_name = NULL
        if 'vcodec' in ff_opts:
            self.py_video_codec_name = ff_opts['vcodec']
            settings.video_codec_name = self.py_video_codec_name
        settings.subtitle_codec_name = NULL
        if 'scodec' in ff_opts:
            self.py_subtitle_codec_name = ff_opts['scodec']
            settings.subtitle_codec_name = self.py_subtitle_codec_name
        if 'max_alloc' in ff_opts:
            av_max_alloc(ff_opts['max_alloc'])
        if 'cpuflags' in ff_opts:
            flags = av_get_cpu_flags()
            if av_parse_cpu_caps(&flags, ff_opts['cpuflags']) < 0:
                raise ValueError('Invalid cpuflags option value.')
            av_force_cpu_flags(flags)

        if loglevel not in loglevels:
            raise ValueError('Invalid log level option.')

        av_log_set_flags(AV_LOG_SKIP_REPEATED)
        av_log_set_level(loglevels[loglevel])
        avcodec_register_all() # register all codecs, demux and protocols
        IF CONFIG_AVDEVICE:
            avdevice_register_all()
        IF CONFIG_AVFILTER:
            avfilter_register_all()
        av_register_all()
        avformat_network_init()
        if CONFIG_SWSCALE:
            sws_opts = sws_getContext(16, 16, <AVPixelFormat>0, 16, 16,
                                      <AVPixelFormat>0, SWS_BICUBIC,
                                      NULL, NULL, NULL)


        'filename can start with pipe:'
        av_strlcpy(settings.input_filename, <char *>filename, sizeof(settings.input_filename))
        if thread_lib == 'SDL':
            if not CONFIG_SDL:
                raise Exception('FFPyPlayer extension not compiled with SDL support.')
            self.mt_gen = MTGenerator(SDL_MT)
        elif thread_lib == 'python':
            self.mt_gen = MTGenerator(Py_MT)
        else:
            raise Exception('Thread library parameter not recognized.')
        if audio_sink != 'SDL':
            raise Exception('Currently, only SDL is supported as a audio sink.')
        self.settings_mutex = MTMutex(self.mt_gen.mt_src)
        if callable(vid_sink):
            self.vid_sink = VideoSink(self.settings_mutex, MTMutex(self.mt_gen.mt_src), vid_sink)
            self.vid_sink.set_out_pix_fmt(AV_PIX_FMT_RGB24)
        else:
            raise Exception('Video sink parameter not recognized.')
        if av_lockmgr_register(self.mt_gen.get_lockmgr()):
            raise ValueError('Could not initialize lock manager.')
        self.ivs = VideoState()
        self.ivs.cInit(self.mt_gen, self.vid_sink, settings)
        self.vid_sink.SDL_Initialize(self.ivs)

    def __dealloc__(self):
        cdef const char *empty = ''
        #XXX: cquit has to be called, otherwise the read_thread never exists.
        # probably some circular referencing somewhere (in event_loop)
        self.ivs.cquit()
        av_lockmgr_register(NULL)
        IF CONFIG_SWSCALE:
            sws_freeContext(self.settings.sws_opts)
            self.settings.sws_opts = NULL

        av_dict_free(&self.settings.format_opts)
        av_dict_free(&self.settings.codec_opts)
        IF CONFIG_AVFILTER:
            av_freep(&self.settings.vfilters)
        avformat_network_deinit()
        if self.settings.show_status:
            printf("\n")
        #SDL_Quit()
        av_log(NULL, AV_LOG_QUIET, "%s", empty)

    def refresh(self, *args):
        with nogil:
            self.vid_sink.event_loop(self.ivs)

    def get_metadata(self):
        return self.ivs.metadata

    def set_volume(self, volume):
        self.settings.volume = min(max(volume, 0.), 1.) * SDL_MIX_MAXVOLUME

    def toggle_pause(self):
        self.settings_mutex.lock()
        with nogil:
            self.ivs.toggle_pause()
        self.settings_mutex.unlock()

    def step_frame(self):
        self.settings_mutex.lock()
        with nogil:
            self.ivs.step_to_next_frame()
        self.settings_mutex.unlock()

    def force_refresh(self):
        self.settings_mutex.lock()
        self.ivs.force_refresh = 1
        self.ivs.callback()('refresh', 0.0)
        self.settings_mutex.unlock()

    "Can only be called from the main thread."
    def set_size(self, int width, int height):
        if not CONFIG_AVFILTER and (width or height):
            raise Exception('You can only set the screen size when avfilter is enabled.')
        self.settings_mutex.lock()
        self.settings.screen_width = width
        self.settings.screen_height = height
        self.settings_mutex.unlock()

    'Can only be called from the main thread.'
    # Currently, if a stream is re-opened when the stream was not open before
    # it'l cause some seeking. We can probably remove it by setting a seek flag
    # only for this stream and not for all, provided is not the master clock stream.
    def request_channel(self, stream_type, action='cycle', int requested_stream=-1):
        cdef int stream, old_index
        if stream_type == 'audio':
            stream = AVMEDIA_TYPE_AUDIO
            old_index = self.ivs.audio_stream
        elif stream_type == 'video':
            stream = AVMEDIA_TYPE_VIDEO
            old_index = self.ivs.video_stream
        elif stream_type == 'subtitle':
            stream = AVMEDIA_TYPE_SUBTITLE
            old_index = self.ivs.subtitle_stream
        else:
            raise Exception('Invalid stream type')
        if action == 'open' or action == 'cycle':
            with nogil:
                self.ivs.stream_cycle_channel(stream, requested_stream)
        elif action == 'close':
            self.ivs.stream_component_close(old_index)

    def seek(self, val, relative=True, seek_by_bytes=False):
        cdef double incr, pos
        cdef int64_t t
        self.settings_mutex.lock()
        if relative:
            incr = val
            if seek_by_bytes:
                with nogil:
                    if self.ivs.video_stream >= 0 and self.ivs.video_current_pos >= 0:
                        pos = self.ivs.video_current_pos
                    elif self.ivs.audio_stream >= 0 and self.ivs.audio_pkt.pos >= 0:
                        pos = self.ivs.audio_pkt.pos
                    else:
                        pos = avio_tell(self.ivs.ic.pb)
                    if self.ivs.ic.bit_rate:
                        incr *= self.ivs.ic.bit_rate / 8.0
                    else:
                        incr *= 180000.0;
                    pos += incr
                    self.ivs.stream_seek(<int64_t>pos, <int64_t>incr, 1)
            else:
                with nogil:
                    pos = self.ivs.get_master_clock()
                    if isnan(pos):
                        # seek_pos might never have been set
                        pos = <double>self.ivs.seek_pos / <double>AV_TIME_BASE
                    pos += incr
                    if self.ivs.ic.start_time != AV_NOPTS_VALUE and pos < self.ivs.ic.start_time / <double>AV_TIME_BASE:
                        pos = self.ivs.ic.start_time / <double>AV_TIME_BASE
                    self.ivs.stream_seek(<int64_t>(pos * AV_TIME_BASE), <int64_t>(incr * AV_TIME_BASE), 0)
        else:
            pos = val
            if seek_by_bytes:
                with nogil:
                    if self.ivs.ic.bit_rate:
                        pos *= self.ivs.ic.bit_rate / 8.0
                    else:
                        pos *= 180000.0;
                    self.ivs.stream_seek(<int64_t>pos, 0, 1)
            else:
                with nogil:
                    t = <int64_t>(pos * AV_TIME_BASE)
                    if self.ivs.ic.start_time != AV_NOPTS_VALUE and t < self.ivs.ic.start_time:
                        t = self.ivs.ic.start_time
                    self.ivs.stream_seek(t, 0, 0)
        self.settings_mutex.unlock()
