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

    def __cinit__(VideoSink self, MTMutex mutex=None, object callback=None,
                  int use_ref=0, **kwargs):
        self.alloc_mutex = mutex
        self.callback = callback
        self.requested_alloc = 0
        self.use_ref = use_ref

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

        vp.use_ref = 0
        IF CONFIG_AVFILTER:
            if self.use_ref:
                av_frame_unref(vp.pict_ref)
                av_frame_move_ref(vp.pict_ref, src_frame)
                vp.use_ref = 1
            else:
                av_picture_copy(<AVPicture *>vp.pict, <AVPicture *>src_frame,
                                <AVPixelFormat>src_frame.format, vp.width, vp.height)
                av_frame_unref(src_frame)
        ELSE:
            if self.use_ref and pix_fmts[0] == <AVPixelFormat>src_frame.format:
                av_frame_unref(vp.pict_ref)
                av_frame_move_ref(vp.pict_ref, src_frame)
                vp.use_ref = 1
                return 0
            if self.use_ref:
                with gil:
                    raise Exception('use_ref was used when CONFIG_AVFILTER is False,\
                    and the input/output pixel formats are different.')
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
        cdef SubPicture *sp
        cdef object buff
        cdef object res
        cdef int *ls
        cdef AVFrame *frame
        if vp.pict == NULL:
            return None

        ls = vp.pict.linesize
        if vp.use_ref:
            frame = av_frame_clone(vp.pict_ref)
            if frame == NULL:
                raise MemoryError()
            buff = (<size_t>frame, [<size_t>frame.data[0], <size_t>frame.data[1],
                                    <size_t>frame.data[2], <size_t>frame.data[3]],
                    av_get_pix_fmt_name(<AVPixelFormat>frame.format))
        else:
            if pix_fmts[0] != AV_PIX_FMT_RGB24:
                raise Exception('Output pixel format is not rgb24.')
            buff = <object>PyString_FromStringAndSize(<const char *>vp.pict.data[0], 3 *vp.width * vp.height)
        res = (buff, (vp.width, vp.height), [ls[0], ls[1], ls[2], ls[3]], vp.pts)
        # XXX doesn't python automatically free?
        if not vp.use_ref:
            Py_DECREF(<PyObject *>buff)
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
