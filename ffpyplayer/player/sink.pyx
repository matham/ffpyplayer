#cython: cdivision=True

include "../includes/ff_consts.pxi"
include "../includes/inline_funcs.pxi"

from cpython.ref cimport PyObject

cdef extern from "Python.h":
    PyObject* PyString_FromString(const char *)
    void Py_DECREF(PyObject *)

from ffpyplayer.threading cimport MTMutex

cdef bytes sub_ass = b'ass', sub_text = b'text', sub_fmt


cdef class VideoSink(object):

    def __cinit__(self, **kwargs):
        self.pix_fmt = AV_PIX_FMT_NONE

    cdef AVPixelFormat _get_out_pix_fmt(VideoSink self) nogil:
        return self.pix_fmt

    cdef object get_out_pix_fmt(VideoSink self):
        return av_get_pix_fmt_name(self.pix_fmt)

    cdef void set_out_pix_fmt(VideoSink self, AVPixelFormat out_fmt):
        '''
        Users set the pixel fmt here. If avfilter is enabled, the filter is
        changed when this is changed. If disabled, this method may only
        be called before other methods below, and can not be called once things
        are running.

        After the user changes the pix_fmt, it might take a few frames until they
        receive the new fmt in case pics were already queued.
        '''
        self.pix_fmt = out_fmt

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
