#cython: cdivision=True

include "ff_defs_comp.pxi"
include "inline_funcs.pxi"

from cpython.ref cimport PyObject

cdef extern from "Python.h":
    PyObject* PyString_FromStringAndSize(const char *, Py_ssize_t)
    PyObject* PyString_FromString(const char *)
    void Py_DECREF(PyObject *)

cimport ffthreading
from ffthreading cimport MTMutex


cdef AVPixelFormat *pix_fmts = [AV_PIX_FMT_RGB24, AV_PIX_FMT_NONE]
cdef bytes sub_ass = str('ass'), sub_text = str('text'), sub_fmt

cdef class VideoSink(object):

    def __cinit__(VideoSink self, MTMutex mutex=None, object callback=None, **kwargs):
        self.alloc_mutex = mutex
        self.callback = callback
        self.requested_alloc = 0

    cdef AVPixelFormat * get_out_pix_fmts(VideoSink self) nogil:
        return pix_fmts

    cdef void set_out_pix_fmt(VideoSink self, AVPixelFormat out_fmt) nogil:
        pix_fmts[0] = out_fmt

    cdef int request_thread(VideoSink self, uint8_t request) nogil except 1:
        if request == FF_ALLOC_EVENT:
            self.alloc_mutex.lock()
            self.requested_alloc = 1
            self.alloc_mutex.unlock()
        elif request == FF_QUIT_EVENT:
            with gil:
                self.callback()('quit')
        return 0

    cdef int peep_alloc(VideoSink self) nogil except 1:
        self.alloc_mutex.lock()
        self.requested_alloc = 0
        self.alloc_mutex.unlock()
        return 0

    cdef int alloc_picture(VideoSink self, VideoPicture *vp) nogil except 1:
        if vp.pict != NULL:
            #av_frame_unref(vp.pict)
            self.free_alloc(vp)
#         else:
        vp.pict = av_frame_alloc()
        if vp.pict == NULL:
            av_log(NULL, AV_LOG_FATAL, "Could not allocate avframe.\n")
            with gil:
                raise Exception('Could not allocate avframe.')
#         IF CONFIG_AVFILTER and 0:
#             return 0
        if (av_image_alloc(vp.pict.data, vp.pict.linesize, vp.width,
                           vp.height, pix_fmts[0], 1) < 0):
            av_log(NULL, AV_LOG_FATAL, "Could not allocate avframe buffer.\n")
            with gil:
                raise Exception('Could not allocate avframe buffer of size %dx%d.' %(vp.width, vp.height))
        return 0

    cdef void free_alloc(VideoSink self, VideoPicture *vp) nogil:
        if vp.pict != NULL:
            av_frame_unref(vp.pict)
            #av_freep(vp.pict.data)
            av_frame_free(&vp.pict)
            vp.pict = NULL

    cdef int copy_picture(VideoSink self, VideoPicture *vp, AVFrame *src_frame,
                           VideoSettings *player) nogil except 1:

        IF CONFIG_AVFILTER:
            #av_frame_move_ref(vp.pict, src_frame)
            av_picture_copy(<AVPicture *>vp.pict, <AVPicture *>src_frame,
                            <AVPixelFormat>src_frame.format, vp.width, vp.height)
            av_frame_unref(src_frame)
        ELSE:
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
        return 0

    cdef object video_image_display(VideoSink self, VideoPicture *vp) with gil:
        cdef SubPicture *sp
        cdef object buff
        cdef object res
        if vp.pict == NULL:
            return None

        if pix_fmts[0] != AV_PIX_FMT_RGB24:
            raise Exception('Invalid output pixel format.')
        buff = <object>PyString_FromStringAndSize(<const char *>vp.pict.data[0], 3 *vp.width * vp.height)
        res = (buff, (vp.width, vp.height), vp.pict.linesize[0], vp.pts)
        # XXX doesn't python automatically free?
        Py_DECREF(<PyObject *>buff)
        #av_frame_unref(vp.pict)
        return res

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
