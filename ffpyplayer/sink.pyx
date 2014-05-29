#cython: cdivision=True

include "ff_defs_comp.pxi"
include "inline_funcs.pxi"

from cpython.ref cimport PyObject

cdef extern from "Python.h":
    PyObject* PyString_FromStringAndSize(const char *, Py_ssize_t)
    PyObject* PyString_FromString(const char *)
    void Py_DECREF(PyObject *)

from ffpyplayer.ffthreading cimport MTMutex
from ffpyplayer.pic cimport Image


cdef AVPixelFormat *pix_fmts = [AV_PIX_FMT_RGB24, AV_PIX_FMT_NONE]
cdef bytes sub_ass = str('ass'), sub_text = str('text'), sub_fmt, pix_fmt = str('rgb24')

cdef class VideoSink(object):

    def __cinit__(VideoSink self, MTMutex mutex=None, object callback=None, **kwargs):
        self.alloc_mutex = mutex
        self.callback = callback
        self.requested_alloc = 0

    cdef AVPixelFormat * get_out_pix_fmts(VideoSink self) nogil:
        return pix_fmts

    cdef void set_out_pix_fmt(VideoSink self, AVPixelFormat out_fmt) nogil:
        pix_fmts[0] = out_fmt
        pix_fmt = av_get_pix_fmt_name(out_fmt)

    cdef int request_thread(VideoSink self, uint8_t request) nogil except 1:
        if request == FF_ALLOC_EVENT:
            self.alloc_mutex.lock()
            self.requested_alloc = 1
            self.alloc_mutex.unlock()
        elif request == FF_QUIT_EVENT:
            with gil:
                self.callback()('quit', '')
        elif request == FF_EOF_EVENT:
            with gil:
                self.callback()('eof', '')
        return 0

    cdef int peep_alloc(VideoSink self) nogil except 1:
        self.alloc_mutex.lock()
        self.requested_alloc = 0
        self.alloc_mutex.unlock()
        return 0

    cdef int alloc_picture(VideoSink self, VideoPicture *vp) nogil except 1:
        if vp.pict != NULL:
            self.free_alloc(vp)
        vp.pict = av_frame_alloc()
        vp.pict_ref = av_frame_alloc()
        if vp.pict == NULL or vp.pict_ref == NULL:
            av_log(NULL, AV_LOG_FATAL, "Could not allocate avframe.\n")
            with gil:
                raise Exception('Could not allocate avframe.')
        if (av_image_alloc(vp.pict.data, vp.pict.linesize, vp.width,
                           vp.height, pix_fmts[0], 1) < 0):
            av_log(NULL, AV_LOG_FATAL, "Could not allocate avframe buffer.\n")
            with gil:
                raise Exception('Could not allocate avframe buffer of size %dx%d.' %(vp.width, vp.height))
        vp.pict.width = vp.width
        vp.pict.height = vp.height
        vp.pict.format = <int>pix_fmts[0]
        return 0

    cdef void free_alloc(VideoSink self, VideoPicture *vp) nogil:
        if vp.pict != NULL:
            av_freep(&vp.pict.data[0])
            av_frame_free(&vp.pict)
            vp.pict = NULL
        if vp.pict_ref != NULL:
            av_frame_free(&vp.pict_ref)
            vp.pict_ref = NULL

    cdef int copy_picture(VideoSink self, VideoPicture *vp, AVFrame *src_frame,
                           VideoSettings *player) nogil except 1:

        IF CONFIG_AVFILTER:
            av_frame_unref(vp.pict_ref)
            av_frame_move_ref(vp.pict_ref, src_frame)
        ELSE:
            if pix_fmts[0] == <AVPixelFormat>src_frame.format:
                av_frame_unref(vp.pict_ref)
                av_frame_move_ref(vp.pict_ref, src_frame)
                return 0
            av_opt_get_int(player.sws_opts, 'sws_flags', 0, &player.sws_flags)
            player.img_convert_ctx = sws_getCachedContext(player.img_convert_ctx,\
            vp.width, vp.height, <AVPixelFormat>src_frame.format, vp.width, vp.height,\
            pix_fmts[0], player.sws_flags, NULL, NULL, NULL)
            if player.img_convert_ctx == NULL:
                av_log(NULL, AV_LOG_FATAL, "Cannot initialize the conversion context\n")
                with gil:
                    raise Exception('Cannot initialize the conversion context.')
            sws_scale(player.img_convert_ctx, src_frame.data, src_frame.linesize,
                      0, vp.height, vp.pict.data, vp.pict.linesize)
            av_frame_unref(src_frame)
        return 0

    cdef object video_image_display(VideoSink self, VideoPicture *vp) with gil:
        cdef Image img
        cdef int *ls
        cdef AVFrame *frame
        if vp.pict == NULL:
            return None

        if CONFIG_AVFILTER or pix_fmts[0] == <AVPixelFormat>vp.pict_ref.format:
            frame = vp.pict_ref
        else:
            frame = vp.pict
        ls = frame.linesize
        img = Image(frame=<size_t>frame,
                    pix_fmt=av_get_pix_fmt_name(<AVPixelFormat>frame.format),
                    size=(frame.width, frame.height),
                    linesize=[ls[0], ls[1], ls[2], ls[3]])
        return (img, vp.pts)

    cdef int subtitle_display(VideoSink self, AVSubtitle *sub) nogil except 1:
        cdef PyObject *buff
        cdef int i
        cdef double pts
        with gil:
            for i in range(sub.num_rects):
                if sub.rects[i].type == SUBTITLE_ASS:
                    buff = PyString_FromString(sub.rects[i].ass)
                    sub_fmt = sub_ass
                elif sub.rects[i].type == SUBTITLE_TEXT:
                    buff = PyString_FromString(sub.rects[i].text)
                    sub_fmt = sub_text
                else:
                    buff = NULL
                    continue
                if sub.pts != AV_NOPTS_VALUE:
                    pts = sub.pts / <double>AV_TIME_BASE
                else:
                    pts = 0.0
                self.callback()('display_sub', (<object>buff, sub_fmt, pts,
                                                sub.start_display_time / 1000.,
                                                sub.end_display_time / 1000.))
                if buff != NULL:
                    Py_DECREF(buff)
        return 0
