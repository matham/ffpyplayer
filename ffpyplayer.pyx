# https://github.com/tito/ffmpeg-android/blob/master/python/ffmpeg/_ffmpeg.pyx

__all__ = ('FFPyPlayer', )

include 'ff_defs_comp.pxi'
include "inline_funcs.pxi"

cdef extern from "Python.h":
    void PyEval_InitThreads()
    
cimport ffthreading
from ffthreading cimport MTGenerator, SDL_MT, Py_MT, MTThread
cimport ffqueue
from ffqueue cimport FFPacketQueue
cimport ffcore
from ffcore cimport VideoState, VideoSettings
cimport sink
from sink cimport SDL_initialize
from libc.stdio cimport printf
from cpython.ref cimport PyObject


cdef int event_loop(void *obj) with gil:
    cdef FFPyPlayer vs = <object>obj
    with nogil:
        vs.event_loop()
    return 0


cdef class FFPyPlayer(object):
    
    def __cinit__(self, filename, loglevel, ff_opts, sink, thread_lib, **kargs):
        cdef unsigned flags
        cdef VideoSettings *settings = &self.settings
        PyEval_InitThreads()
        settings.format_opts = settings.codec_opts = settings.resample_opts = settings.swr_opts = NULL
        settings.sws_flags = SWS_BICUBIC
        settings.default_width  = 640
        settings.default_height = 480
        settings.screen_width  = ff_opts['x'] if 'x' in ff_opts else 0
        settings.screen_height = ff_opts['y'] if 'y' in ff_opts else 0
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
        settings.autoexit = 0
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
            if val != 0 and val != 1 and val != 2:
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
        if sink != 'SDL':
            if not CONFIG_SDL:
                raise Exception('FFPyPlayer extension not compiled with SDL support.')
            raise Exception('Currently, only SDL is supported as a sink.')
        if thread_lib == 'SDL':
            if not CONFIG_SDL:
                raise Exception('FFPyPlayer extension not compiled with SDL support.')
            self.mt_gen = MTGenerator(SDL_MT)
        elif thread_lib == 'python':
            self.mt_gen = MTGenerator(Py_MT)
        if av_lockmgr_register(self.mt_gen.get_lockmgr()):
            raise ValueError('Could not initialize lock manager.')
        self.ivs = VideoState()
        self.ivs.cInit(self.mt_gen, settings.input_filename, settings.file_iformat,
                              settings.av_sync_type, settings)
        self.update_thread = None
        if sink == 'SDL':
            self.update_thread = MTThread(self.mt_gen.mt_src)
            self.update_thread.create_thread(event_loop, <PyObject*>self)
    
    def __dealloc__(self):
        cdef const char *empty = ''
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
        SDL_Quit()
        av_log(NULL, AV_LOG_QUIET, "%s", empty)

    cdef void event_loop(FFPyPlayer self) nogil:
        cdef SDL_Event event
        cdef double incr, pos, frac
        cdef double x
        SDL_initialize(self.settings.display_disable, self.settings.audio_disable,
                       &self.settings.fs_screen_width, &self.settings.fs_screen_height)
        
        while 1:
            self.ivs.refresh_loop_wait_event(&event)
            if event.type == SDL_VIDEOEXPOSE:
                self.ivs.force_refresh = 1
            elif event.type == SDL_VIDEORESIZE:
                self.settings.screen = SDL_SetVideoMode(FFMIN(16383, event.resize.w), event.resize.h, 0,
                                                        SDL_HWSURFACE|SDL_RESIZABLE|SDL_ASYNCBLIT|SDL_HWACCEL)
                if self.settings.screen == NULL:
                    av_log(NULL, AV_LOG_FATAL, "Failed to set video mode\n")
                    break
                self.settings.screen_width  = self.ivs.width  = self.settings.screen.w
                self.settings.screen_height = self.ivs.height = self.settings.screen.h
                self.ivs.force_refresh = 1
            elif event.type == SDL_QUIT or event.type == FF_QUIT_EVENT:
                break
            elif event.type == FF_ALLOC_EVENT:
                self.ivs.alloc_picture()
