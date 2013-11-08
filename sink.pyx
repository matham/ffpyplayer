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

cdef AVPixelFormat *pix_fmts_sdl = [AV_PIX_FMT_YUV420P, AV_PIX_FMT_NONE]
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
        if self.lib == SDL_Video:
            return pix_fmts_sdl
        elif self.lib == Py_Video:
            return pix_fmts_py

    cdef void request_thread(VideoSink self, void *data, uint8_t request) nogil:
        cdef SDL_Event event
        if self.lib == SDL_Video:
            event.type = request
            event.user.data1 = data
            SDL_PushEvent(&event)
        elif self.lib == Py_Video:
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
        cdef SDL_Event event
        if self.lib == SDL_Video:
            return SDL_PeepEvents(&event, 1, SDL_GETEVENT, EVENTMASK(FF_ALLOC_EVENT)) != 1
        elif self.lib == Py_Video:
            self.alloc_mutex.lock()
            self.requested_alloc = 0
            self.alloc_mutex.unlock()
            return 0

    cdef int video_open(VideoSink self, int force_set_video_mode, VideoPicture *vp,
                        VideoSettings *player, int *width, int *height) nogil:
        cdef uint32_t flags
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
        if self.lib == SDL_Video:
            if player.screen != NULL and width[0] == player.screen.w and player.screen.w == w\
            and height[0] == player.screen.h and player.screen.h == h and not force_set_video_mode:
                return 0
            flags = SDL_HWSURFACE | SDL_ASYNCBLIT | SDL_HWACCEL
            if player.is_full_screen:
                flags |= SDL_FULLSCREEN
            else:
                flags |= SDL_RESIZABLE
            player.screen = SDL_SetVideoMode(w, h, 0, flags)
            if player.screen == NULL:
                av_log(NULL, AV_LOG_FATAL, "SDL: could not set video mode - exiting\n")
                with gil:
                    raise Exception('SDL: could not set video mode - exiting')
            if player.window_title == NULL:
                player.window_title = player.input_filename
            SDL_WM_SetCaption(player.window_title, player.window_title)
            width[0] = player.screen.w
            height[0] = player.screen.h
        elif self.lib == Py_Video:
            width[0] = w
            height[0] = h
    
        return 0

    cdef void alloc_picture(VideoSink self, VideoPicture *vp,
                            VideoSettings *player, int *width, int *height) nogil:
        cdef int64_t bufferdiff = 0
        self.video_open(0, vp, player, width, height)
        if self.lib == SDL_Video:
            vp.pict = NULL
            if vp.bmp != NULL:
                SDL_FreeYUVOverlay(vp.bmp)
            vp.bmp = SDL_CreateYUVOverlay(vp.width, vp.height, SDL_YV12_OVERLAY,
                                          player.screen)
            if vp.bmp != NULL:
                bufferdiff = FFMAXptr(vp.bmp.pixels[0], vp.bmp.pixels[1]) -\
                FFMINptr(vp.bmp.pixels[0], vp.bmp.pixels[1])
            if (vp.bmp == NULL or vp.bmp.pitches[0] < vp.width or
                bufferdiff < <int64_t>vp.height * vp.bmp.pitches[0]):
                ''' SDL allocates a buffer smaller than requested if the video
                overlay hardware is unable to support the requested size. '''
                #msg = 
                av_log(NULL, AV_LOG_FATAL,
                       "Error: the video system does not support an image\n\
                       size of %dx%d pixels. Try using -lowres or -vf \"scale=w:h\"\n\
                       to reduce the image size.\n", vp.width, vp.height)
                with gil:
                    raise Exception('The video system does not support an image of size\
                 %dx%d pixels' % (vp.width, vp.height))
        elif self.lib == Py_Video:
            vp.bmp = NULL
            vp.pict = av_frame_alloc()
            if vp.pict == NULL:
                av_log(NULL, AV_LOG_FATAL, "Could not allocate avframe.\n")
                with gil:
                    raise Exception('Could not allocate avframe.')
            if (av_image_alloc(vp.pict.data, vp.pict.linesize, vp.width,
                               vp.height, pix_fmts_py[0], 1) < 0):
                av_log(NULL, AV_LOG_FATAL, "Could not allocate avframe buffer.\n")
                with gil:
                    raise Exception('Could not allocate avframe buffer.')

    cdef void free_alloc(VideoSink self, VideoPicture *vp) nogil:
        if vp.bmp != NULL:
            SDL_FreeYUVOverlay(vp.bmp)
            vp.bmp = NULL
        if vp.pict != NULL:
            av_frame_unref(vp.pict)
            av_freep(&vp.pict.data[0])
            av_frame_free(&vp.pict)
        
    cdef void copy_picture(VideoSink self, VideoPicture *vp, AVFrame *src_frame,
                           VideoSettings *player) nogil:
        cdef AVPicture pict
        cdef AVPicture *pictp
        cdef AVPixelFormat out_fmt
        if self.lib == SDL_Video:
            memset(&pict, 0, sizeof(AVPicture))
            # get a pointer on the bitmap
            SDL_LockYUVOverlay(vp.bmp)
    
            pict.data[0] = vp.bmp.pixels[0]
            pict.data[1] = vp.bmp.pixels[2]
            pict.data[2] = vp.bmp.pixels[1]
    
            pict.linesize[0] = vp.bmp.pitches[0]
            pict.linesize[1] = vp.bmp.pitches[2]
            pict.linesize[2] = vp.bmp.pitches[1]
            
            pictp = &pict
            out_fmt = pix_fmts_sdl[0]
        elif self.lib == Py_Video:
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
        if self.lib == SDL_Video:
            # workaround SDL PITCH_WORKAROUND 
            duplicate_right_border_pixels(vp.bmp)
            # update the bitmap content
            SDL_UnlockYUVOverlay(vp.bmp)

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
                self.callback('display', (<object>buff, (vp.width, vp.height)))
                # XXX doesn't python automatically free?
                Py_DECREF(buff)
        elif vp.bmp != NULL:
            if ist.subtitle_st:
                if ist.subpq_size > 0:
                    sp = &ist.subpq[ist.subpq_rindex]
    
                    if vp.pts >= sp.pts + (<float> sp.sub.start_display_time / 1000.):
                        SDL_LockYUVOverlay(vp.bmp)
    
                        pict.data[0] = vp.bmp.pixels[0]
                        pict.data[1] = vp.bmp.pixels[2]
                        pict.data[2] = vp.bmp.pixels[1]
    
                        pict.linesize[0] = vp.bmp.pitches[0]
                        pict.linesize[1] = vp.bmp.pitches[2]
                        pict.linesize[2] = vp.bmp.pitches[1]
    
                        for i from 0 <= i < sp.sub.num_rects:
                            blend_subrect(&pict, sp.sub.rects[i], vp.bmp.w, vp.bmp.h)
    
                        SDL_UnlockYUVOverlay(vp.bmp)
    
            calculate_display_rect(&rect, ist.xleft, ist.ytop, ist.width, ist.height, vp)
    
            SDL_DisplayYUVOverlay(vp.bmp, &rect)
    
            if (rect.x != ist.last_display_rect.x or rect.y != ist.last_display_rect.y or
                rect.w != ist.last_display_rect.w or rect.h != ist.last_display_rect.h or
                ist.force_refresh):
                bgcolor = SDL_MapRGB(screen.format, 0x00, 0x00, 0x00)
                fill_border(screen, ist.xleft, ist.ytop, ist.width, ist.height, rect.x,
                            rect.y, rect.w, rect.h, bgcolor, 1)
                ist.last_display_rect = rect

    cdef void SDL_Initialize(VideoSink self, VideoState vs) nogil:
        cdef unsigned flags
        cdef const SDL_VideoInfo *vi
        flags = SDL_INIT_VIDEO | SDL_INIT_AUDIO | SDL_INIT_TIMER
        if vs.player.audio_disable:# or audio_sink != 'SDL':
            flags &= ~SDL_INIT_AUDIO
        if vs.player.display_disable or self.lib != SDL_Video:
            SDL_putenv(dummy_videodriver) # For the event queue, we always need a video driver.
        if NOT_WIN_MAC:
            flags |= SDL_INIT_EVENTTHREAD # Not supported on Windows or Mac OS X
        with gil:
            if SDL_Init(flags):
                raise ValueError('Could not initialize SDL - %s\nDid you set the DISPLAY variable?' % SDL_GetError())
        if (not vs.player.display_disable) and self.lib == SDL_Video:
            vi = SDL_GetVideoInfo()
            vs.player.fs_screen_width = vi.current_w
            vs.player.fs_screen_height = vi.current_h
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

        while 1:
            remaining_time = 0.0
            SDL_PumpEvents()
            while not SDL_PeepEvents(&event, 1, SDL_GETEVENT, SDL_ALLEVENTS):
                self.settings_mutex.lock()
                if (not vs.player.cursor_hidden) and av_gettime() -\
                vs.player.cursor_last_shown > CURSOR_HIDE_DELAY:
                    SDL_ShowCursor(0)
                    vs.player.cursor_hidden = 1
                self.settings_mutex.unlock()
                if remaining_time > 0.0:
                    av_usleep(<int64_t>(remaining_time * 1000000.0))
                remaining_time = REFRESH_RATE
                self.settings_mutex.lock()
                if <ShowMode>vs.show_mode != SHOW_MODE_NONE and ((not vs.paused) or vs.force_refresh):
                    vs.video_refresh(&remaining_time)
                self.settings_mutex.unlock()
                SDL_PumpEvents()
            if event.type == SDL_VIDEOEXPOSE:
                self.settings_mutex.lock()
                vs.force_refresh = 1
                self.settings_mutex.unlock()
            elif event.type == SDL_VIDEORESIZE:
                self.settings_mutex.lock()
                vs.player.screen = SDL_SetVideoMode(FFMIN(16383, event.resize.w), event.resize.h, 0,
                                                        SDL_HWSURFACE|SDL_RESIZABLE|SDL_ASYNCBLIT|SDL_HWACCEL)
                if vs.player.screen == NULL:
                    av_log(NULL, AV_LOG_FATAL, "Failed to set video mode\n")
                    self.settings_mutex.unlock()
                    break
                vs.player.screen_width  = vs.width  = vs.player.screen.w
                vs.player.screen_height = vs.height = vs.player.screen.h
                vs.force_refresh = 1
                self.settings_mutex.unlock()
            elif event.type == SDL_QUIT or event.type == FF_QUIT_EVENT:
                break
            elif event.type == FF_ALLOC_EVENT:
                vs.alloc_picture()

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
 
# /* draw only the border of a rectangle */
cdef void fill_border(SDL_Surface *screen, int xleft, int ytop, int width,
                      int height, int x, int y, int w, int h, int color, int update) nogil:
    cdef int w1, w2, h1, h2
 
    # /* fill the background */
    w1 = x
    if w1 < 0:
        w1 = 0
    w2 = width - (x + w)
    if w2 < 0:
        w2 = 0
    h1 = y
    if h1 < 0:
        h1 = 0
    h2 = height - (y + h)
    if h2 < 0:
        h2 = 0
    fill_rectangle(screen,
                   xleft, ytop,
                   w1, height,
                   color, update)
    fill_rectangle(screen,
                   xleft + width - w2, ytop,
                   w2, height,
                   color, update)
    fill_rectangle(screen,
                   xleft + w1, ytop,
                   width - w1 - w2, h1,
                   color, update)
    fill_rectangle(screen,
                   xleft + w1, ytop + height - h2,
                   width - w1 - w2, h2,
                   color, update)


DEF BPP = 1

cdef void blend_subrect(AVPicture *dst, const AVSubtitleRect *rect, int imgw, int imgh) nogil:
    cdef int wrap, wrap3, width2, skip2
    cdef int y, u, v, a, u1, v1, a1, w, h
    cdef uint8_t *lum, *cb, *cr
    cdef const uint8_t *p
    cdef const uint32_t *pal
    cdef int dstx, dsty, dstw, dsth
 
    dstw = av_clip(rect.w, 0, imgw)
    dsth = av_clip(rect.h, 0, imgh)
    dstx = av_clip(rect.x, 0, imgw - dstw)
    dsty = av_clip(rect.y, 0, imgh - dsth)
    lum = dst.data[0] + dsty * dst.linesize[0]
    cb  = dst.data[1] + (dsty >> 1) * dst.linesize[1]
    cr  = dst.data[2] + (dsty >> 1) * dst.linesize[2]
 
    width2 = ((dstw + 1) >> 1) + (dstx & ~(dstw & 1))
    skip2 = dstx >> 1
    wrap = dst.linesize[0]
    wrap3 = rect.pict.linesize[0]
    p = rect.pict.data[0]
    pal = <const uint32_t *>rect.pict.data[1]  # Now in YCrCb!
 
    if dsty & 1:
        lum += dstx
        cb += skip2
        cr += skip2
 
        if dstx & 1:
            YUVA_IN(&y, &u, &v, &a, p, pal)
            lum[0] = ALPHA_BLEND(a, lum[0], y, 0)
            cb[0] = ALPHA_BLEND(a >> 2, cb[0], u, 0)
            cr[0] = ALPHA_BLEND(a >> 2, cr[0], v, 0)
            cb += 1
            cr += 1
            lum += 1
            p += BPP
        w = dstw - (dstx & 1)
        while w >= 2:
            YUVA_IN(&y, &u, &v, &a, p, pal)
            u1 = u
            v1 = v
            a1 = a
            lum[0] = ALPHA_BLEND(a, lum[0], y, 0)
 
            YUVA_IN(&y, &u, &v, &a, p + BPP, pal)
            u1 += u
            v1 += v
            a1 += a
            lum[1] = ALPHA_BLEND(a, lum[1], y, 0)
            cb[0] = ALPHA_BLEND(a1 >> 2, cb[0], u1, 1)
            cr[0] = ALPHA_BLEND(a1 >> 2, cr[0], v1, 1)
            cb += 1
            cr += 1
            p += 2 * BPP
            lum += 2
            w -= 2
        if w:
            YUVA_IN(&y, &u, &v, &a, p, pal)
            lum[0] = ALPHA_BLEND(a, lum[0], y, 0)
            cb[0] = ALPHA_BLEND(a >> 2, cb[0], u, 0)
            cr[0] = ALPHA_BLEND(a >> 2, cr[0], v, 0)
            p += 1
            lum += 1
        p += wrap3 - dstw * BPP
        lum += wrap - dstw - dstx
        cb += dst.linesize[1] - width2 - skip2
        cr += dst.linesize[2] - width2 - skip2
    h = dsth - (dsty & 1)
    while h >= 2:
        lum += dstx
        cb += skip2
        cr += skip2
 
        if dstx & 1:
            YUVA_IN(&y, &u, &v, &a, p, pal)
            u1 = u
            v1 = v
            a1 = a
            lum[0] = ALPHA_BLEND(a, lum[0], y, 0)
            p += wrap3
            lum += wrap
            YUVA_IN(&y, &u, &v, &a, p, pal)
            u1 += u
            v1 += v
            a1 += a
            lum[0] = ALPHA_BLEND(a, lum[0], y, 0)
            cb[0] = ALPHA_BLEND(a1 >> 2, cb[0], u1, 1)
            cr[0] = ALPHA_BLEND(a1 >> 2, cr[0], v1, 1)
            cb += 1
            cr += 1
            p += -wrap3 + BPP
            lum += -wrap + 1
        w = dstw - (dstx & 1)
        while w >= 2:
            YUVA_IN(&y, &u, &v, &a, p, pal)
            u1 = u
            v1 = v
            a1 = a
            lum[0] = ALPHA_BLEND(a, lum[0], y, 0)
 
            YUVA_IN(&y, &u, &v, &a, p + BPP, pal)
            u1 += u
            v1 += v
            a1 += a
            lum[1] = ALPHA_BLEND(a, lum[1], y, 0)
            p += wrap3
            lum += wrap
 
            YUVA_IN(&y, &u, &v, &a, p, pal)
            u1 += u
            v1 += v
            a1 += a
            lum[0] = ALPHA_BLEND(a, lum[0], y, 0)
 
            YUVA_IN(&y, &u, &v, &a, p + BPP, pal)
            u1 += u
            v1 += v
            a1 += a
            lum[1] = ALPHA_BLEND(a, lum[1], y, 0)
 
            cb[0] = ALPHA_BLEND(a1 >> 2, cb[0], u1, 2)
            cr[0] = ALPHA_BLEND(a1 >> 2, cr[0], v1, 2)
 
            cb += 1
            cr += 1
            p += -wrap3 + 2 * BPP
            lum += -wrap + 2
            w -= 2
        if w:
            YUVA_IN(&y, &u, &v, &a, p, pal)
            u1 = u
            v1 = v
            a1 = a
            lum[0] = ALPHA_BLEND(a, lum[0], y, 0)
            p += wrap3
            lum += wrap
            YUVA_IN(&y, &u, &v, &a, p, pal)
            u1 += u
            v1 += v
            a1 += a
            lum[0] = ALPHA_BLEND(a, lum[0], y, 0)
            cb[0] = ALPHA_BLEND(a1 >> 2, cb[0], u1, 1)
            cr[0] = ALPHA_BLEND(a1 >> 2, cr[0], v1, 1)
            cb += 1
            cr += 1
            p += -wrap3 + BPP
            lum += -wrap + 1
        p += wrap3 + (wrap3 - dstw * BPP)
        lum += wrap + (wrap - dstw - dstx)
        cb += dst.linesize[1] - width2 - skip2
        cr += dst.linesize[2] - width2 - skip2
        h -= 2
    # handle odd height
    if h:
        lum += dstx
        cb += skip2
        cr += skip2
 
        if dstx & 1:
            YUVA_IN(&y, &u, &v, &a, p, pal)
            lum[0] = ALPHA_BLEND(a, lum[0], y, 0)
            cb[0] = ALPHA_BLEND(a >> 2, cb[0], u, 0)
            cr[0] = ALPHA_BLEND(a >> 2, cr[0], v, 0)
            cb += 1
            cr += 1
            lum += 1
            p += BPP
        w = dstw - (dstx & 1)
        while w >= 2:
            YUVA_IN(&y, &u, &v, &a, p, pal)
            u1 = u
            v1 = v
            a1 = a
            lum[0] = ALPHA_BLEND(a, lum[0], y, 0)
 
            YUVA_IN(&y, &u, &v, &a, p + BPP, pal)
            u1 += u
            v1 += v
            a1 += a
            lum[1] = ALPHA_BLEND(a, lum[1], y, 0)
            cb[0] = ALPHA_BLEND(a1 >> 2, cb[0], u, 1)
            cr[0] = ALPHA_BLEND(a1 >> 2, cr[0], v, 1)
            cb += 1
            cr += 1
            p += 2 * BPP
            lum += 2
            w -= 2
        if w:
            YUVA_IN(&y, &u, &v, &a, p, pal)
            lum[0] = ALPHA_BLEND(a, lum[0], y, 0)
            cb[0] = ALPHA_BLEND(a >> 2, cb[0], u, 0)
            cr[0] = ALPHA_BLEND(a >> 2, cr[0], v, 0)
 
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

cdef void duplicate_right_border_pixels(SDL_Overlay *bmp) nogil:
    cdef int i, width, height
    cdef uint8_t *p, *maxp
    for i from 0 <= i < 3:
        width  = bmp.w
        height = bmp.h
        if i > 0:
            width  >>= 1
            height >>= 1
        if bmp.pitches[i] > width:
            maxp = bmp.pixels[i] + bmp.pitches[i] * height - 1
            p = bmp.pixels[i] + width - 1
            while p < maxp:
                p[1] = p[0]
                p += bmp.pitches[i]
