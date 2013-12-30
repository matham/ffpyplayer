'''
FFmpeg based media player
=========================

A FFmpeg based python media player. See :class:`MediaPlayer` for details.
'''


__all__ = ('MediaPlayer', )

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
from tools import loglevels, _initialize_ffmpeg
from libc.stdio cimport printf
from cpython.ref cimport PyObject


cdef class MediaPlayer(object):
    '''
    An FFmpeg based media player.

    Was originally ported from FFplay. Most options offered in FFplay is
    also available here.

    The class provides a player interface to a media file. Video components
    of the file are returned with :meth:`get_frame`. Audio is played directly
    using SDL. And subtitles are acquired either through the callback function
    (text subtitles only), or are overlaid directly using the subtitle filter.

    **Args**:
        *filename* (str): The filename or url of the media object. This can be
        physical files, remote files or even webcam name's e.g. for direct show
        or Video4Linux webcams. The *f* specifier in *ff_opts* can be used to
        indicate the format needed to open the file (e.g. dshow).

        *vid_sink* (ref to function): A weak ref to a function that will be called
        when quitting or when text subtitles are available. The function takes
        two parameters, *selector*, and *value*. When the player is closing internally
        due to some error the *selector* will be 'quit'.
        When a new subtitle string is available, *selector* will be 'display_sub'
        and *value* will be a 5-tuple of the form *(text, fmt, pts, start, end)*.
        Where *text* is the text, *fmt* is the subtitle format e.g. 'ass', *pts*
        is the timestamp of the text, *start*, and *end* respectively are the times
        in video time when to start and finish displaying the text.

        *loglevel* (str): The level of logs to emit. It value is one of the keywords
        defined in :attr:`ffpyplayer.tools.loglevels`. Note this only affects
        the default FFmpeg logger, which prints to stderr. You can manipulate the
        log stream directly using :attr:`ffpyplayer.tools.set_log_callback`.

        *thread_lib* (str): The threading library to use internally. Can be one of
        'SDL' or 'python'.

        .. warning::

            If the python threading library is used, care must be taken to delete
            the player before exiting python, otherwise it may hang. The reason is
            that the internal threads are created as non-daemon, consequently, when the
            python main thread exits, the internal threads will keep python alive.
            By deleting the player directly, the internal threads will be shut down
            before python exits.

        *audio_sink* (str): Currently it must be 'SDL'.

        *lib_opts* (dict): A dictionary of options that will be passed to the
        ffmpeg libraries, codecs, sws, swr, and formats when opening them. This accepts
        most of the options that can be passed to FFplay. Examples are
        "threads":"auto", "lowres":"1" etc. Both the keywords and values must be
        strings.

        *ff_opts* (dict): A dictionary with options for the player. Following are
        the available options. Note, many options have identical names and meaning
        as in the FFplay options: www.ffmpeg.org/ffplay.html

            | *cpuflags* (str): similar to ffplay
            | *max_alloc* (int): similar to ffplay
            | *infbuf* (bool): similar to ffplay
            | *framedrop* (bool): similar to ffplay
            | *loop* (int): similar to ffplay
            | *autoexit* (int): If non-zero, the player closes on eof.
            | *ec* (int): similar to ffplay
            | *lowres* (int): similar to ffplay
            | *drp* (int): similar to ffplay
            | *genpts* (bool): similar to ffplay
            | *fast* (bool): similar to ffplay
            | *bug* (bool): similar to ffplay
            | *stats* (bool): similar to ffplay
            | *pixel_format* (str): similar to ffplay
            | *bytes* (int): similar to ffplay, not used
            | *t* (float): similar to ffplay
            | *ss* (float): similar to ffplay
            | *sync* (str): similar to ffplay, can be one of 'audio', 'video', 'ext'
            | *acodec, vcodec, scodec* (str): similar to ffplay
            | *ast, vst, sst* (int): similar to ffplay
            | *an, sn, vn* (bool): similar to ffplay
            | *f* (str): similar to ffplay. The format to open the file with. E.g. dshow for webcams.
            | *af, vf* (str) similar to ffplay. These are filters applied to the audio/video.
              Examples are 'crop=100:100' to crop, 'vflip' to flip horizontally, 'subtitles=filename'
              to overlay subtitles from another media or text file etc. CONFIG_AVFILTER must be True
              (the default) when compiling in order to use this.
            | *x, y* (int): The width and height of the output frames. Similar to
              :meth:`set_size`. CONFIG_AVFILTER must be True (the default) when
              compiling in order to use this.

    ::

        from ffpyplayer.player import MediaPlayer
        import time, weakref
        def callback(selector, value):
            if selector == 'quit':
                print 'quitting'
        player = MediaPlayer(filename, vid_sink=weakref.ref(callback))
        while 1:
            frame, val = player.get_frame()
            if val == 'eof':
                break
            elif frame is None:
                time.sleep(0.01)
            else:
                print val, len(frame[0]), frame[1:]
                time.sleep(val)

    TODO: offer audio buffers, similar to video frames (if wanted?).
    '''

    def __cinit__(self, filename, vid_sink, loglevel='error', ff_opts={},
                  thread_lib='python', audio_sink='SDL', lib_opts={}, **kargs):
        cdef unsigned flags
        cdef VideoSettings *settings = &self.settings
        PyEval_InitThreads()
        if loglevel not in loglevels:
            raise ValueError('Invalid log level option.')
        av_log_set_flags(AV_LOG_SKIP_REPEATED)
        av_log_set_level(loglevels[loglevel])
        _initialize_ffmpeg()
        settings.format_opts = settings.codec_opts = settings.swr_opts = NULL
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

        if CONFIG_SWSCALE:
            settings.sws_opts = sws_getContext(16, 16, <AVPixelFormat>0, 16, 16,
                                               <AVPixelFormat>0, SWS_BICUBIC,
                                               NULL, NULL, NULL)
        for k, v in lib_opts.iteritems():
            if opt_default(k, v, settings.sws_opts, &settings.swr_opts,
                           &settings.format_opts, &self.settings.codec_opts) < 0:
                raise Exception('library option %s: $s not found' % (k, v))

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
            self.vid_sink = VideoSink(MTMutex(self.mt_gen.mt_src), vid_sink)
            self.vid_sink.set_out_pix_fmt(AV_PIX_FMT_RGB24)
        else:
            raise Exception('Video sink parameter not recognized.')
        if av_lockmgr_register(self.mt_gen.get_lockmgr()):
            raise ValueError('Could not initialize lock manager.')
        self.ivs = VideoState()
        self.ivs.cInit(self.mt_gen, self.vid_sink, settings)
        flags = SDL_INIT_AUDIO | SDL_INIT_TIMER
        if settings.audio_disable:# or audio_sink != 'SDL':
            flags &= ~SDL_INIT_AUDIO
        IF not HAS_SDL2:
            if NOT_WIN_MAC:
                flags |= SDL_INIT_EVENTTHREAD # Not supported on Windows or Mac OS X
        if SDL_Init(flags):
            raise ValueError('Could not initialize SDL - %s\nDid you set the DISPLAY variable?' % SDL_GetError())

    def __init__(self, filename, vid_sink, loglevel='error', ff_opts={},
                 thread_lib='python', audio_sink='SDL', lib_opts={}, **kargs):
        pass

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
        av_dict_free(&self.settings.swr_opts)
        IF CONFIG_AVFILTER:
            av_freep(&self.settings.vfilters)
        avformat_network_deinit()
        if self.settings.show_status:
            printf("\n")
        #SDL_Quit()
        av_log(NULL, AV_LOG_QUIET, "%s", empty)

    def get_frame(self, force_refresh=False, *args):
        '''
        Retrieves the next available frame if ready.

        **Args**:
            *force_refresh* (bool): If True, the last frame will be returned again.
            Defaults to False.

        **Returns**:
            *(frame, val)*.
            *frame* is None or a 4-tuple.
            *val* is either 'paused', 'eof', or a float.

            If *val* is either 'paused' or 'eof', *frame* is None. Otherwise, if
            *frame* is not None, *val* is the realtime time one should wait before
            displaying this frame to the user to achieve a play rate of 1.0.

            If *frame* is not None it's a 4-tuple - *(buffer, size, linesize, pts)*.
            *buffer* is a bytes buffer containing the frmae in RGBRGB... format.
            *size* is a 2-tuple of (width, height) of the frame. Because the video
            can be dynamically resized these values can change between frames.
            *linesize* is the width of a line in the frame. Currently it should be
            the same as width. In the future it might be larger if the lines are padded.
            *pts* is the presentation timestamp of this frame. This is the time
            when the frame should be displayed to the user in video time (i.e.
            not realtime).

        .. note::

            The audio plays at a normal play rate, independent of when and if
            this function is called. Therefore, 'eof' will only be received when
            the audio is complete, even if all the frames have been read (unless
            audio is disabled). I.e. a None frame will be sent after all the frames
            have been read until eof.

        For example, playing as soon as frames are read::

            >>> while 1:
            ...     frame, val = player.get_frame()
            ...     if val == 'eof':
            ...         break
            ...     elif frame is None:
            ...         time.sleep(0.01)
            ...         print 'not ready'
            ...     else:
            ...         print val, len(frame[0]), frame[1:]
            not ready
            0.0 1013760 ((704, 480), 2112, 0.0)
            0.0 1013760 ((704, 480), 2112, 0.033)
            ...
            24.731872797 1013760 ((704, 480), 2112, 13.881)
            not ready
            24.7868728638 1013760 ((704, 480), 2112, 13.914)

        vs displaying frames at their proper times::

            >>> while 1:
            ...     frame, val = player.get_frame()
            ...     if val == 'eof':
            ...         break
            ...     elif frame is None:
            ...         time.sleep(0.01)
            ...         print 'not ready'
            ...     else:
            ...         print val, len(frame[0]), frame[1:]
            ...         time.sleep(val)
            not ready
            0.0 1013760 ((704, 480), 2112, 0.0)
            0.0 1013760 ((704, 480), 2112, 0.033)
            ...
            0.031772851944 1013760 ((704, 480), 2112, 20.954)
            0.030770778656 1013760 ((704, 480), 2112, 20.988)
            0.0307686328888 1013760 ((704, 480), 2112, 21.021)
        '''
        self.settings_mutex.lock()
        res = self.ivs.video_refresh(force_refresh)
        self.settings_mutex.unlock()
        return res

    def get_metadata(self):
        '''
        Returns metadata of the file being played.

        **Returns**:
            (dict): The player metadata

        ::

            >>> print player.get_metadata()
            {'duration': 71.972, 'sink_vid_size': (0, 0), 'src_vid_size':
             (704, 480), 'title': 'The Melancholy of Haruhi Suzumiya: Special Ending'}

        .. warning::

            The dictionary returned will have default values until the file is
            open and read. Because a second thread is created and used to read
            the file, when the constructor returns the dict might still have
            the default values. After the first frame is read, the dictionary
            entries are correct with respect to the file metadata.

        .. note::

            Some paramteres can change as the streams are manipulated (e.g. the
            frame size parameters).
        '''
        return self.ivs.metadata

    def set_volume(self, volume):
        '''
        Sets the volume of the audio.

        **Args**:
            *volume* (float): A value between 0.0 - 1.0.
        '''
        self.settings.volume = min(max(volume, 0.), 1.) * SDL_MIX_MAXVOLUME

    def get_volume(self):
        '''
        Returns the volume of the audio.

        **Returns**:
            (float): A value between 0.0 - 1.0.
        '''
        return self.settings.volume / <double>SDL_MIX_MAXVOLUME

    def toggle_pause(self):
        '''
        Pauses or unpauses the player.
        '''
        self.settings_mutex.lock()
        with nogil:
            self.ivs.toggle_pause()
        self.settings_mutex.unlock()

    def get_pts(VideoState self):
        '''
        Returns the elapsed play time.

        **Returns**:
            (float): The amount of the time that the video has been playing.
            The time is from the clock used for the player (default is audio,
            see sync option). If the clock is based on video, it should correspond
            with the pts from get_frame.
        '''
        cdef double pos
        cdef int sync_type = self.ivs.get_master_sync_type()
        if (sync_type == AV_SYNC_VIDEO_MASTER and
            self.ivs.video_stream != -1):
            pos = self.ivs.vidclk.get_clock()
        elif (sync_type == AV_SYNC_AUDIO_MASTER and
            self.ivs.audio_stream != -1):
            pos = self.ivs.audclk.get_clock()
        else:
            pos = self.ivs.extclk.get_clock()
        if isnan(pos):
            pos = <double>self.ivs.seek_pos / <double>AV_TIME_BASE
        if (self.ivs.ic.start_time != AV_NOPTS_VALUE and
            pos < self.ivs.ic.start_time / <double>AV_TIME_BASE):
            pos = self.ivs.ic.start_time / <double>AV_TIME_BASE
        return pos

    def set_size(self, int width=-1, int height=-1):
        '''
        Dynamically sets the size of the frames returned by get_frame.

        **Args**:
            *width*, *height* (int): The width and height of the output frames.
            A value of 0 will set that parameter to the source height/width.
            A value of -1 for one of the parameters, will result in a value of that
            parameter that maintains the original aspect ratio.

        ::

            >>> print player.get_frame()[0][1:]
            ((704, 480), 2112, 0.067)

            >>> player.set_size(200, 200)
            >>> print player.get_frame()[0][1:]
            ((704, 480), 2112, 0.1)
            >>> print player.get_frame()[0][1:]
            ((704, 480), 2112, 0.133)
            >>> print player.get_frame()[0][1:]
            ((704, 480), 2112, 0.167)
            >>> print player.get_frame()[0][1:]
            ((200, 200), 600, 0.2)

            >>> player.set_size(200, 0)
            >>> print player.get_frame()[0][1:]
            ((200, 200), 600, 0.234)
            >>> print player.get_frame()[0][1:]
            ((200, 200), 600, 0.267)
            >>> print player.get_frame()[0][1:]
            ((200, 480), 600, 0.3)

            >>> player.set_size(200, -1)
            >>> print player.get_frame()[0][1:]
            ((200, 480), 600, 0.334)
            >>> print player.get_frame()[0][1:]
            ((200, 480), 600, 0.367)
            >>> print player.get_frame()[0][1:]
            ((200, 136), 600, 0.4)

        Note that it takes a few calls to flush the old frames.

        .. note::

            This should only be called from the main thread (the thread that calls
            get_frame).

        .. note::

            if CONFIG_AVFILTER was False when compiling, this function will raise
            an error.
        '''
        if not CONFIG_AVFILTER and (width or height):
            raise Exception('You can only set the screen size when avfilter is enabled.')
        self.settings_mutex.lock()
        self.settings.screen_width = width
        self.settings.screen_height = height
        self.settings_mutex.unlock()

    # Currently, if a stream is re-opened when the stream was not open before
    # it'l cause some seeking. We can probably remove it by setting a seek flag
    # only for this stream and not for all, provided is not the master clock stream.
    def request_channel(self, stream_type, action='cycle', int requested_stream=-1):
        '''
        Opens or closes a stream dynamically.

        This function may result in seeking when opening a new stream.

        **Args**:
            *stream_type* (str): The stream group on which to operate. Can be one of
            'audio', 'video', or 'subtitle'.

            *action* (str): The action to preform. Can be one of 'open', 'close',
            or 'cycle'. A value of 'cycle' will close the current stream and
            open the next stream in this group.

            *requested_stream* (int): The stream to open next when *action* is
            'cycle' or 'open'. If -1, the next stream will be opened. Otherwise,
            this stream will be attempted to be opened.

        .. note::

            This should only be called from the main thread (the thread that calls
            get_frame).

        '''
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

    def seek(self, pts, relative=True, seek_by_bytes=False):
        '''
        Seeks in the current streams.

        Seeks to the desired timepoint as close as possible while not exceeding
        that time.

        **Args**:
            *pts* (float): The timestamp to seek to (in seconds).

            *relative* (bool): Whether the pts parameter is interpreted as the
            time offset from the current stream position.

            *seek_by_bytes* (bool): Whether we seek based on the position in bytes
            or in time. In some instances seeking by bytes may be more accurate
            (don't ask me which).

        ::

            >>> print player.get_frame()[0][1:]
            ((1280, 688), 3840, 1016.392)

            >>> player.seek(200.)
            >>> player.get_frame()
            >>> print player.get_frame()[0][1:]
            ((1280, 688), 3840, 1249.876)

            >>> player.seek(200, relative=False)
            >>> player.get_frame()
            >>> print player.get_frame()[0][1:]
            ((1280, 688), 3840, 198.49)

        Note that it may take a few calls to get new frames after seeking.
        '''
        cdef double incr, pos
        cdef int64_t t
        self.settings_mutex.lock()
        if relative:
            incr = pts
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
                    self.ivs.stream_seek(<int64_t>pos, <int64_t>incr, 1, 1)
            else:
                with nogil:
                    pos = self.ivs.get_master_clock()
                    if isnan(pos):
                        # seek_pos might never have been set
                        pos = <double>self.ivs.seek_pos / <double>AV_TIME_BASE
                    pos += incr
                    if self.ivs.ic.start_time != AV_NOPTS_VALUE and pos < self.ivs.ic.start_time / <double>AV_TIME_BASE:
                        pos = self.ivs.ic.start_time / <double>AV_TIME_BASE
                    self.ivs.stream_seek(<int64_t>(pos * AV_TIME_BASE), <int64_t>(incr * AV_TIME_BASE), 0, 1)
        else:
            pos = pts
            if seek_by_bytes:
                with nogil:
                    if self.ivs.ic.bit_rate:
                        pos *= self.ivs.ic.bit_rate / 8.0
                    else:
                        pos *= 180000.0;
                    self.ivs.stream_seek(<int64_t>pos, 0, 1, 1)
            else:
                with nogil:
                    t = <int64_t>(pos * AV_TIME_BASE)
                    if self.ivs.ic.start_time != AV_NOPTS_VALUE and t < self.ivs.ic.start_time:
                        t = self.ivs.ic.start_time
                    self.ivs.stream_seek(t, 0, 0, 1)
        self.settings_mutex.unlock()
