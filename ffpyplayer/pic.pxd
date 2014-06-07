include 'ff_defs.pxi'



cdef class SWScale(object):
    cdef SwsContext *sws_ctx
    cdef bytes dst_pix_fmt
    cdef int dst_h
    cdef int dst_w
    cdef AVPixelFormat src_pix_fmt
    cdef int src_h
    cdef int src_w


cdef class Image(object):

    cdef AVFrame *frame
    cdef list byte_planes
    cdef AVPixelFormat pix_fmt

    cdef int cython_init(self, AVFrame *frame) nogil
    cpdef is_ref(Image self)
    cpdef get_linesizes(Image self, keep_align=*)
    cpdef get_size(Image self)
    cpdef get_pixel_format(Image self)
    cpdef get_buffer_size(Image self, keep_align=*)
    cpdef to_bytearray(Image self, keep_align=*)
    cpdef to_memoryview(Image self, keep_align=*)
