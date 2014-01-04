

__all__ = ('Image', )


include "inline_funcs.pxi"

from cpython.ref cimport PyObject

cdef extern from "string.h" nogil:
    void *memset(void *, int, size_t)

cdef extern from "Python.h":
    PyObject* PyString_FromStringAndSize(const char *, Py_ssize_t)
    void Py_DECREF(PyObject *)

cdef class SWScale(object):
    '''
    '''

    def __cinit__(self, int src_w, int src_h, src_fmt, int dst_w=-1,
                  int dst_h=-1, dst_fmt='', **kargs):
        cdef AVPixelFormat src_pix_fmt, dst_pix_fmt

        self.sws_ctx = NULL
        src_pix_fmt = av_get_pix_fmt(src_fmt)
        if src_pix_fmt == AV_PIX_FMT_NONE:
            raise Exception('Pixel format %s not found.' % src_fmt)
        dst_pix_fmt = src_pix_fmt
        self.dst_pix_fmt = src_fmt
        if dst_fmt:
            self.dst_pix_fmt = dst_fmt
            dst_pix_fmt = av_get_pix_fmt(dst_fmt)
            if dst_pix_fmt == AV_PIX_FMT_NONE:
                raise Exception('Pixel format %s not found.' % dst_fmt)
        if dst_w == -1 and dst_h == -1:
            dst_w = dst_h = 0
        if not dst_h:
            dst_h = src_h
        if not dst_w:
            dst_w = src_w
        if dst_w == -1:
            dst_w = <int>(dst_h / <double>src_h * src_w)
        if dst_h == -1:
            dst_h = <int>(dst_w / <double>src_w * src_h)
        self.dst_w = dst_w
        self.dst_h = dst_h

        self.sws_ctx = sws_getCachedContext(NULL, src_w, src_h, src_pix_fmt, dst_w, dst_h,
                                            dst_pix_fmt, SWS_BICUBIC, NULL, NULL, NULL)
        if self.sws_ctx == NULL:
            raise Exception('Cannot initialize the conversion context.')

    def __init__(self, int src_w, int src_h, src_fmt, int dst_w=-1,
                  int dst_h=-1, dst_fmt='', **kargs):
        pass

    def __dealloc__(self):
        if self.sws_ctx != NULL:
            sws_freeContext(self.sws_ctx)

    def scale(self, Image src, Image dst=None):
        if not dst:
            dst = Image(pix_fmt=self.dst_pix_fmt, size=(self.dst_w, self.dst_h))
        sws_scale(self.sws_ctx, <const uint8_t *const *>src.frame.data, src.frame.linesize,
                      0, src.frame.height, dst.frame.data, dst.frame.linesize)
        return dst


cdef class Image(object):
    '''
    Stores an image buffer.


    '''

    def __cinit__(self, plane_buffers=[], plane_ptrs=[], Image image=None,
                  frame=0, pix_fmt='', size=(), linesize=[], **kargs):
        cdef int i, w, h, res
        cdef bytes plane = None
        cdef char msg[256]

        self.frame = NULL
        self.byte_planes = None
        self.free_pict = 0
        memset(msg, 0, sizeof(msg))

        if frame:
            self.frame = av_frame_clone(<AVFrame *><size_t>frame)
            if self.frame == NULL:
                raise MemoryError()
            return

        if image:
            self.frame = av_frame_clone(image.frame)
            if self.frame == NULL:
                raise MemoryError()
            return

        self.pix_fmt = av_get_pix_fmt(pix_fmt)
        if self.pix_fmt == AV_PIX_FMT_NONE:
            raise Exception('Pixel format %s not found.' % pix_fmt)
        w, h = size
        self.frame = av_frame_alloc()
        if self.frame == NULL:
            raise MemoryError()

        self.frame.format = self.pix_fmt
        self.frame.width = w
        self.frame.height = h
        if linesize:
            for i in range(len(linesize)):
                self.frame.linesize[i] = linesize[i]
        else:
            res = av_image_fill_linesizes(self.frame.linesize, self.pix_fmt, w)
            if res < 0:
                raise Exception('Failed to initialize linesizes: ' + emsg(res, msg, sizeof(msg)))

        if plane_buffers:
            self.byte_planes = []
            for i in range(len(plane_buffers)):
                plane = plane_buffers[i]
                self.byte_planes.append(plane)
                self.frame.data[i] = plane
        elif plane_ptrs:
            for i in range(len(plane_ptrs)):
                self.frame.data[i] = <uint8_t *><size_t>plane_ptrs[i]
        else:
            self.free_pict = 1
            res = av_image_alloc(self.frame.data, self.frame.linesize, w, h, self.pix_fmt, 1)
            if res < 0:
                raise Exception('Could not allocate avframe buffer of size %dx%d: %s'\
                                % (w, h, emsg(res, msg, sizeof(msg))))

    def __init__(self, plane_buffers=[], plane_ptrs=[], Image image=None,
                  frame=0, pix_fmt='', size=(), linesize=[], **kargs):
        pass

    def __dealloc__(self):
        if self.free_pict:
            av_freep(&self.frame.data[0])
        av_frame_free(&self.frame)

    def get_linesizes(Image self):
        cdef int *ls = self.frame.linesize
        return (ls[0], ls[1], ls[2], ls[3])

    def get_size(Image self):
        return (self.frame.width, self.frame.height)

    def get_pixel_format(Image self):
        return av_get_pix_fmt_name(self.pix_fmt)

    def to_bytes(Image self):
        cdef list planes = [None, None, None, None]
        cdef int i
        for i in range(4):
            if self.frame.linesize[i] and self.frame.data[i] != NULL:
                planes[i] = <object>PyString_FromStringAndSize(<const char *>\
                self.frame.data[i], self.frame.linesize[i] * self.frame.height)
                Py_DECREF(<PyObject *>planes[i])
        return planes
