# https://github.com/tito/ffmpeg-android/blob/master/python/ffmpeg/_ffmpeg.pyx

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
from sink cimport VideoSettings, VideoSink, SDL_Video, Py_Video
from libc.stdio cimport printf
from cpython.ref cimport PyObject


cdef int event_loop(void *obj) with gil:
    cdef FFPyPlayer fp = <object>obj
    with nogil:
        fp.vid_sink.SDL_Initialize(fp.ivs)
        fp.vid_sink.event_loop(fp.ivs)
    return 0

cdef class FFPyPlayer(object):

    def __cinit__(self, filename, loglevel, ff_opts, thread_lib='python', vid_sink='SDL', audio_sink='SDL', **kargs):
        cdef unsigned flags
        cdef VideoSettings *settings = &self.settings
        PyEval_InitThreads()
        settings.format_opts = settings.codec_opts = settings.resample_opts = settings.swr_opts = NULL
        settings.sws_flags = SWS_BICUBIC
        settings.default_width  = 640
        settings.default_height = 480
        # set x, or y to -1 to preserve pixel ratio
        settings.screen_width  = ff_opts['x'] if 'x' in ff_opts else 0
        settings.screen_height = ff_opts['y'] if 'y' in ff_opts else 0
        if not CONFIG_AVFILTER and (settings.screen_width or settings.screen_height):
            raise Exception('You can only set the screen size when avfilter is enabled.')
        settings.is_full_screen = bool(ff_opts['fs']) if 'fs' in ff_opts else 0
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
        settings.display_disable = bool(ff_opts['nodisp']) if 'nodisp' in ff_opts else 0
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
        settings.exit_on_keydown = 0
        settings.exit_on_mousedown = 0
        settings.loop = ff_opts['loop'] if 'loop' in ff_opts else 1
        settings.framedrop = bool(ff_opts['framedrop']) if 'framedrop' in ff_opts else -1
        settings.infinite_buffer = bool(ff_opts['infbuf']) if 'infbuf' in ff_opts else -1
        settings.window_title = NULL
        if 'window_title' in ff_opts:
            self.py_window_title = ff_opts['window_title']
            settings.window_title = self.py_window_title
        settings.show_mode = SHOW_MODE_NONE
        if 'showmode' in ff_opts:
            val = ff_opts['showmode']
            if val != 0 and val != 1 and val != 2 and val != -1:
                raise ValueError('Invalid showmode option value.')
            settings.show_mode = val # xxx might need to cast to ShowMode?
        settings.rdftspeed = float(ff_opts['rdftspeed']) if 'rdftspeed' in ff_opts else 0.02
        settings.cursor_hidden = 0
        IF CONFIG_AVFILTER:
            settings.vfilters = NULL
            if 'vf' in ff_opts:
                self.py_vfilters = ff_opts['vf']
                settings.vfilters = self.py_vfilters
            settings.afilters = NULL
            if 'af' in ff_opts:
                self.py_afilters = ff_opts['af']
                settings.afilters = self.py_afilters
        settings.dummy = bool(ff_opts['i']) if 'i' in ff_opts else 0
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
        if settings.display_disable:
            settings.video_disable = 1

        'see http://ffmpeg.org/ffmpeg.html for log levels'
        loglevels = {"quiet":AV_LOG_QUIET, "panic":AV_LOG_PANIC, "fatal":AV_LOG_FATAL,
                     "error":AV_LOG_ERROR, "warning":AV_LOG_WARNING, "info":AV_LOG_INFO,
                     "verbose":AV_LOG_VERBOSE, "debug":AV_LOG_DEBUG}
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
        self.py_filename = filename # keep filename in memory until closing
        settings.input_filename = self.py_filename
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
        if vid_sink == 'SDL':
            if not CONFIG_SDL:
                raise Exception('FFPyPlayer extension not compiled with SDL support.')
            self.vid_sink = VideoSink(SDL_Video, self.settings_mutex)
        elif callable(vid_sink):
            self.vid_sink = VideoSink(Py_Video, self.settings_mutex, 
                                      MTMutex(self.mt_gen.mt_src), vid_sink)
        else:
            raise Exception('Video sink parameter not recognized.')
        if av_lockmgr_register(self.mt_gen.get_lockmgr()):
            raise ValueError('Could not initialize lock manager.')
        self.ivs = VideoState()
        self.ivs.cInit(self.mt_gen, self.vid_sink, settings.input_filename, settings.file_iformat,
                              settings.av_sync_type, settings)
        self.update_thread = None
        if vid_sink == 'SDL':
            self.update_thread = MTThread(self.mt_gen.mt_src)
            self.update_thread.create_thread(event_loop, <PyObject*>self)
        else:
            self.vid_sink.SDL_Initialize(self.ivs)
        #if callable(vid_sink):
        #    vid_sink('refresh', 0.0)

    def __dealloc__(self):
        cdef const char *empty = ''
        #XXX: cquit has to be called, otherwise the read_thread never exists.
        # probably some circular referencing somewhere (in event_loop)
        self.ivs.cquit()
        av_lockmgr_register(NULL)
        IF CONFIG_SWSCALE:
            sws_freeContext(self.settings.sws_opts)
            self.settings.sws_opts = NULL

        av_dict_free(&self.settings.swr_opts)
        av_dict_free(&self.settings.format_opts)
        av_dict_free(&self.settings.codec_opts)
        av_dict_free(&self.settings.resample_opts)
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
            
    def get_duration(self):
        if self.ivs.ic.duration < 0:
            return 0.0
        else:
            return self.ivs.ic.duration / <double>AV_TIME_BASE
    
    def get_size(self):
        return (self.ivs.width, self.ivs.height)
    
    'Can only be called from the main thread (GUI thread in kivy, eventloop in SDL)'
    def toggle_full_screen(self):
        self.ivs.toggle_full_screen()
        self.ivs.force_refresh = 1
        
    def toggle_pause(self):
        self.settings_mutex.lock()
        self.ivs.toggle_pause()
        self.settings_mutex.unlock()
    
    def step_frame(self):
        self.settings_mutex.lock()
        self.ivs.step_to_next_frame()
        self.settings_mutex.unlock()
    
    def force_refresh(self):
        self.settings_mutex.lock()
        self.ivs.force_refresh = 1
        self.settings_mutex.unlock()
    
    "Can only be called from the main thread (GUI thread in kivy) Doesn't work with SDL"
    def set_size(self, int width, int height):
        self.settings_mutex.lock()
        self.settings.screen_width = self.ivs.width = width
        self.settings.screen_height = self.ivs.height = height
        self.ivs.stream_component_close(self.ivs.video_stream)
        self.ivs.stream_component_open(self.ivs.video_stream)
        self.settings_mutex.unlock()
    
    'Can only be called from the main thread (GUI thread in kivy, eventloop in SDL)'
    def cycle_channel(self, stream_type):
        cdef int stream
        if stream_type == 'audio':
            stream = AVMEDIA_TYPE_AUDIO
        elif stream_type == 'video':
            stream = AVMEDIA_TYPE_VIDEO
        elif stream_type == 'subtitle':
            stream = AVMEDIA_TYPE_SUBTITLE
        else:
            raise Exception('Invalid stream type')
        self.ivs.stream_cycle_channel(stream)
    
    'Can only be called from the main thread (GUI thread in kivy, eventloop in SDL)\
    Only works for SDL currently.'
    def toggle_audio_display(self):
        self.ivs.toggle_audio_display()

    def seek(self, val, relative=True, seek_by_bytes=False):
        cdef double incr, pos
        cdef int64_t t
        self.settings_mutex.lock()
        if relative:
            incr = val
            if seek_by_bytes:
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
                if self.ivs.ic.bit_rate:
                    pos *= self.ivs.ic.bit_rate / 8.0
                else:
                    pos *= 180000.0;
                self.ivs.stream_seek(<int64_t>pos, 0, 1)
            else:
                t = <int64_t>(pos * AV_TIME_BASE)
                if self.ivs.ic.start_time != AV_NOPTS_VALUE and t < self.ivs.ic.start_time:
                    t = self.ivs.ic.start_time
                self.ivs.stream_seek(t, 0, 0)
        self.settings_mutex.unlock()
