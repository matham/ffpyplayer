#cython: cdivision=True

include "ff_defs_comp.pxi"
include "inline_funcs.pxi"

from cpython.ref cimport PyObject

cdef extern from "Python.h":
    PyObject* PyByteArray_FromStringAndSize(const char *string, Py_ssize_t len)
    PyObject* PyString_FromStringAndSize(const char *v, Py_ssize_t len)
    void Py_DECREF(PyObject *)

cdef extern from "limits.h" nogil:
    int INT_MIN

cdef extern from "math.h" nogil:
    float rint(float)
    double sqrt(double)
    
cdef extern from "string.h" nogil:
    void * memset(void *, int, size_t)


cimport ffcore
from ffcore cimport VideoState
cimport ffthreading
from ffthreading cimport MTMutex

cdef AVPixelFormat *pix_fmts_py = [AV_PIX_FMT_RGB24, AV_PIX_FMT_NONE]
pydummy_videodriver = 'SDL_VIDEODRIVER=dummy' # does SDL_putenv copy the string?
cdef char *dummy_videodriver = pydummy_videodriver

cdef class VideoSink(object):

    def __cinit__(VideoSink self, Video_lib lib, MTMutex settings_mutex, MTMutex mutex=None,
                  object callback=None, **kwargs):
        self.lib = lib
        self.alloc_mutex = mutex
        self.settings_mutex = settings_mutex
        self.callback = callback
        self.requested_alloc = 0

    cdef AVPixelFormat * get_out_pix_fmts(VideoSink self) nogil:
        if self.lib == Py_Video:
            return pix_fmts_py

    cdef void request_thread(VideoSink self, void *data, uint8_t request) nogil:
        if self.lib == Py_Video:
            if request == FF_ALLOC_EVENT:
                self.alloc_mutex.lock()
                self.requested_alloc = 1
                self.alloc_mutex.unlock()
                with gil:
                    self.callback('refresh', 0.0)
            elif request == FF_QUIT_EVENT:
                with gil:
                    self.callback('quit', None)
            elif request == FF_EOF_EVENT:
                with gil:
                    self.callback('eof', None)

    cdef int peep_alloc(VideoSink self) nogil:
        if self.lib == Py_Video:
            self.alloc_mutex.lock()
            self.requested_alloc = 0
            self.alloc_mutex.unlock()
            return 0

    cdef int video_open(VideoSink self, int force_set_video_mode, VideoPicture *vp,
                        VideoSettings *player, int *width, int *height) nogil:
        cdef int w,h
        cdef Rect rect
    
        if vp != NULL and vp.width:
            calculate_display_rect(&rect, 0, 0, INT_MAX, vp.height, vp);
            player.default_width  = rect.w
            player.default_height = rect.h
    
        if player.is_full_screen and player.fs_screen_width:
            w = player.fs_screen_width
            h = player.fs_screen_height
        elif (not player.is_full_screen) and player.screen_width:
            w = player.screen_width
            h = player.screen_height
        else:
            w = player.default_width
            h = player.default_height
        w = FFMIN(16383, w)
        if self.lib == Py_Video:
            width[0] = w
            height[0] = h
    
        return 0

    cdef void alloc_picture(VideoSink self, VideoPicture *vp,
                            VideoSettings *player, int *width, int *height) nogil:
        self.video_open(0, vp, player, width, height)
        if self.lib == Py_Video:
            vp.bmp = NULL
            if vp.pict != NULL:
                self.free_alloc(vp)
            vp.pict = av_frame_alloc()
            if vp.pict == NULL:
                av_log(NULL, AV_LOG_FATAL, "Could not allocate avframe.\n")
                with gil:
                    raise Exception('Could not allocate avframe.')
            if (av_image_alloc(vp.pict.data, vp.pict.linesize, vp.width,
                               vp.height, pix_fmts_py[0], 1) < 0):
                av_log(NULL, AV_LOG_FATAL, "Could not allocate avframe buffer.\n")
                with gil:
                    raise Exception('Could not allocate avframe buffer of size %dx%d.' %(vp.width, vp.height))

    cdef void free_alloc(VideoSink self, VideoPicture *vp) nogil:
        if vp.pict != NULL:
            av_frame_unref(vp.pict)
            av_freep(&vp.pict.data[0])
            av_frame_free(&vp.pict)
        
    cdef void copy_picture(VideoSink self, VideoPicture *vp, AVFrame *src_frame,
                           VideoSettings *player) nogil:
        cdef AVPicture *pictp
        cdef AVPixelFormat out_fmt
        if self.lib == Py_Video:
            pictp = <AVPicture *>vp.pict
            out_fmt = pix_fmts_py[0]

        IF CONFIG_AVFILTER:
            # FIXME use direct rendering
            av_picture_copy(pictp, <AVPicture *>src_frame,
                            <AVPixelFormat>src_frame.format, vp.width, vp.height)
        ELSE:
            av_opt_get_int(player.sws_opts, 'sws_flags', 0, &player.sws_flags)
            player.img_convert_ctx = sws_getCachedContext(player.img_convert_ctx,\
            vp.width, vp.height, <AVPixelFormat>src_frame.format, vp.width, vp.height,\
            out_fmt, player.sws_flags, NULL, NULL, NULL)
            if player.img_convert_ctx == NULL:
                av_log(NULL, AV_LOG_FATAL, "Cannot initialize the conversion context\n")
                with gil:
                    raise Exception('Cannot initialize the conversion context.')
            sws_scale(player.img_convert_ctx, src_frame.data, src_frame.linesize,
                      0, vp.height, pict.data, pict.linesize)

    cdef void video_image_display(VideoSink self, SDL_Surface *screen, VideoState ist) nogil:
        cdef VideoPicture *vp
        cdef SubPicture *sp
        cdef AVPicture pict
        cdef SDL_Rect rect
        cdef int i, bgcolor
        cdef PyObject *buff
    
        vp = &(ist.pictq[ist.pictq_rindex])
        if vp.pict != NULL:
            with gil:
                buff = PyString_FromStringAndSize(<const char *>\
                vp.pict.data[0], 3 *vp.width * vp.height)
                self.callback('display', (<object>buff, (vp.width, vp.height), vp.pts))
                # XXX doesn't python automatically free?
                Py_DECREF(buff)
#             if ist.subtitle_st:
#                 if ist.subpq_size > 0:
#                     sp = &ist.subpq[ist.subpq_rindex]
#     
#                     if vp.pts >= sp.pts + (<float> sp.sub.start_display_time / 1000.):

    cdef void SDL_Initialize(VideoSink self, VideoState vs) nogil:
        cdef unsigned flags
        cdef const SDL_VideoInfo *vi
        flags = SDL_INIT_VIDEO | SDL_INIT_AUDIO | SDL_INIT_TIMER
        if vs.player.audio_disable:# or audio_sink != 'SDL':
            flags &= ~SDL_INIT_AUDIO
        SDL_putenv(dummy_videodriver) # For the event queue, we always need a video driver.
        if NOT_WIN_MAC:
            flags |= SDL_INIT_EVENTTHREAD # Not supported on Windows or Mac OS X
        with gil:
            if SDL_Init(flags):
                raise ValueError('Could not initialize SDL - %s\nDid you set the DISPLAY variable?' % SDL_GetError())
        SDL_EventState(SDL_ACTIVEEVENT, SDL_IGNORE)
        SDL_EventState(SDL_SYSWMEVENT, SDL_IGNORE)
        SDL_EventState(SDL_USEREVENT, SDL_IGNORE)
        self.remaining_time = 0.0

    cdef void event_loop(VideoSink self, VideoState vs) nogil:
        cdef SDL_Event event
        cdef double incr, pos, frac
        cdef double x
        cdef double remaining_time

        if self.lib == Py_Video:
            while 1:
                if self.remaining_time > 0.0:
                    remaining_time = self.remaining_time
                    self.remaining_time = 0.
                    with gil:
                        self.callback('refresh', remaining_time)
                    break
                self.remaining_time = REFRESH_RATE
                self.settings_mutex.lock()
                if <ShowMode>vs.show_mode != SHOW_MODE_NONE and ((not vs.paused) or vs.force_refresh):
                    vs.video_refresh(&self.remaining_time)
                self.settings_mutex.unlock()
            self.alloc_mutex.lock()
            if self.requested_alloc:
                #self.settings_mutex.lock()
                vs.alloc_picture()
                #self.settings_mutex.unlock()
                self.requested_alloc = 0
            self.alloc_mutex.unlock()
            return 

cdef inline void fill_rectangle(SDL_Surface *screen, int x, int y, int w,
                                int h, int color, int update) nogil:
    cdef SDL_Rect rect
    rect.x = x
    rect.y = y
    rect.w = w
    rect.h = h
    SDL_FillRect(screen, &rect, color)
    if update and (w > 0) and (h > 0):
        SDL_UpdateRect(screen, x, y, w, h)
  
cdef void calculate_display_rect(SDL_Rect *rect, int scr_xleft, int scr_ytop,
                                 int scr_width, int scr_height, VideoPicture *vp) nogil:
    cdef float aspect_ratio
    cdef int width, height, x, y
 
    if vp.sar.num == 0:
        aspect_ratio = 0
    else:
        aspect_ratio = av_q2d(vp.sar)

    if aspect_ratio <= 0.0:
        aspect_ratio = 1.0
    aspect_ratio *= (<float>vp.width) / <float>vp.height
 
    # XXX: we suppose the screen has a 1.0 pixel ratio
    height = scr_height
    width = (<int>rint(height * aspect_ratio)) & ~1
    if width > scr_width:
        width = scr_width
        height = (<int>rint(width / aspect_ratio)) & ~1
    x = (scr_width - width) / 2
    y = (scr_height - height) / 2
    rect.x = scr_xleft + x
    rect.y = scr_ytop  + y
    rect.w = FFMAX(width,  1)
    rect.h = FFMAX(height, 1)


cdef void video_audio_display(SDL_Surface *screen, VideoState s, int64_t *audio_callback_time) nogil:
    cdef int i, i_start, x, y1, y, ys, delay, n, nb_display_channels
    cdef int ch, channels, h, h2, bgcolor, fgcolor
    cdef int64_t time_diff
    cdef int rdft_bits, nb_freq
    cdef int data_used
    cdef int idx, a, b, c, d, score
    cdef FFTSample *data[2]
    cdef double w
    
    rdft_bits = 1
    while (1 << rdft_bits) < 2 * s.height:
        rdft_bits += 1
    nb_freq = 1 << (rdft_bits - 1)
 
    # compute display index : center on currently output samples
    channels = s.audio_tgt.channels
    nb_display_channels = channels
    if not s.paused:
        data_used = s.width if <int>s.show_mode == <int>SHOW_MODE_WAVES else 2 * nb_freq
        n = 2 * channels
        delay = s.audio_write_buf_size
        delay /= n
 
        ''' to be more precise, we take into account the time spent since
           the last buffer computation'''
        if audio_callback_time[0]:
            time_diff = av_gettime() - audio_callback_time[0]
            delay -= (time_diff * s.audio_tgt.freq) / 1000000
 
        delay += 2 * data_used
        if delay < data_used:
            delay = data_used
 
        i_start = x = compute_mod(s.sample_array_index - delay * channels, SAMPLE_ARRAY_SIZE)
        if s.show_mode == <int>SHOW_MODE_WAVES:
            h = INT_MIN
            for i from 0 <= i < 1000 by channels:
                idx = (SAMPLE_ARRAY_SIZE + x - i) % SAMPLE_ARRAY_SIZE
                a = s.sample_array[idx]
                b = s.sample_array[(idx + 4 * channels) % SAMPLE_ARRAY_SIZE]
                c = s.sample_array[(idx + 5 * channels) % SAMPLE_ARRAY_SIZE]
                d = s.sample_array[(idx + 9 * channels) % SAMPLE_ARRAY_SIZE]
                score = a - d
                if h < score and (b ^ c) < 0:
                    h = score
                    i_start = idx
 
        s.last_i_start = i_start
    else:
        i_start = s.last_i_start
 
    bgcolor = SDL_MapRGB(screen.format, 0x00, 0x00, 0x00)
    if s.show_mode == <int>SHOW_MODE_WAVES:
        fill_rectangle(screen, s.xleft, s.ytop, s.width, s.height, bgcolor, 0);
 
        fgcolor = SDL_MapRGB(screen.format, 0xff, 0xff, 0xff)
 
        # total height for one channel
        h = s.height / nb_display_channels
        # graph height / 2 
        h2 = (h * 9) / 20
        for ch from 0 <= ch < nb_display_channels:
            i = i_start + ch
            y1 = s.ytop + ch * h + (h / 2)   # position of center line
            for x from 0 <= x < s.width:
                y = (s.sample_array[i] * h2) >> 15
                if y < 0:
                    y = -y
                    ys = y1 - y
                else:
                    ys = y1
                fill_rectangle(screen, s.xleft + x, ys, 1, y, fgcolor, 0)
                i += channels
                if i >= SAMPLE_ARRAY_SIZE:
                    i -= SAMPLE_ARRAY_SIZE
 
        fgcolor = SDL_MapRGB(screen.format, 0x00, 0x00, 0xff)
 
        for ch from 1 <= ch < nb_display_channels:
            y = s.ytop + ch * h
            fill_rectangle(screen, s.xleft, y, s.width, 1, fgcolor, 0)
        SDL_UpdateRect(screen, s.xleft, s.ytop, s.width, s.height)
    else:
        nb_display_channels = FFMIN(nb_display_channels, 2)
        if rdft_bits != s.rdft_bits:
            av_rdft_end(s.rdft)
            av_free(s.rdft_data)
            s.rdft = av_rdft_init(rdft_bits, DFT_R2C)
            s.rdft_bits = rdft_bits
            s.rdft_data = <FFTSample *>av_malloc(4 * nb_freq * sizeof(s.rdft_data[0]))
        #{ hmm why were these in thei own context?
            for ch from 0 <= ch < nb_display_channels:
                data[ch] = s.rdft_data + 2 * nb_freq * ch
                i = i_start + ch
                for x from 0 <= x < 2 * nb_freq:
                    w = (x - nb_freq) / <double>nb_freq
                    data[ch][x] = s.sample_array[i] * (1.0 - w * w)
                    i += channels
                    if i >= SAMPLE_ARRAY_SIZE:
                        i -= SAMPLE_ARRAY_SIZE
                av_rdft_calc(s.rdft, data[ch])
            ''' Least efficient way to do this, we should of course
            directly access it but it is more than fast enough. '''
            for y from 0 <= y < s.height:
                w = 1 / sqrt(nb_freq)
                a = <int>sqrt(w * sqrt(data[0][2 * y + 0] * data[0][2 * y + 0] + data[0][2 * y + 1] * data[0][2 * y + 1]))
                if nb_display_channels == 2:
                    b = <int>sqrt(w * sqrt(data[1][2 * y + 0] * data[1][2 * y + 0] + data[1][2 * y + 1] * data[1][2 * y + 1]))
                else:
                    b = a
                a = FFMIN(a, 255)
                b = FFMIN(b, 255)
                fgcolor = SDL_MapRGB(screen.format, a, b, (a + b) / 2)
 
                fill_rectangle(screen, s.xpos, s.height - y, 1, 1, fgcolor, 0)
        #}
        SDL_UpdateRect(screen, s.xpos, s.ytop, 1, s.height)
        if not s.paused:
            s.xpos += 1
        if s.xpos >= s.width:
            s.xpos = s.xleft
