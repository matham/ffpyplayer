#cython: cdivision=True

include "ff_defs_comp.pxi"
include "inline_funcs.pxi"

cdef extern from "limits.h" nogil:
    int INT_MIN

cdef extern from "math.h" nogil:
    float rint(float)
    double sqrt(double)


cimport ffcore
from ffcore cimport VideoState


pydummy_videodriver = 'SDL_VIDEODRIVER=dummy' # does SDL_putenv copy the string?
cdef char *dummy_videodriver = pydummy_videodriver
cdef void SDL_initialize(int display_disable, int audio_disable, int *fs_screen_width,
                         int *fs_screen_height) nogil:
    cdef const SDL_VideoInfo *vi
    cdef unsigned flags
    flags = SDL_INIT_VIDEO | SDL_INIT_AUDIO | SDL_INIT_TIMER
    if audio_disable:
        flags &= ~SDL_INIT_AUDIO
    if display_disable:
        SDL_putenv(dummy_videodriver) # For the event queue, we always need a video driver.
    if NOT_WIN_MAC:
        flags |= SDL_INIT_EVENTTHREAD # Not supported on Windows or Mac OS X
    with gil:
        if SDL_Init(flags):
            raise ValueError('Could not initialize SDL - %s\nDid you set the DISPLAY variable?' % SDL_GetError())
    if not display_disable:
        vi = SDL_GetVideoInfo()
        fs_screen_width[0] = vi.current_w
        fs_screen_height[0] = vi.current_h
    SDL_EventState(SDL_ACTIVEEVENT, SDL_IGNORE)
    SDL_EventState(SDL_SYSWMEVENT, SDL_IGNORE)
    SDL_EventState(SDL_USEREVENT, SDL_IGNORE)

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


cdef void video_image_display(SDL_Surface *screen, VideoState ist) nogil:
    cdef VideoPicture *vp
    cdef SubPicture *sp
    cdef AVPicture pict
    cdef SDL_Rect rect
    cdef int i, bgcolor

    vp = &(ist.pictq[ist.pictq_rindex])
    if vp.bmp:
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
