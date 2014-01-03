include 'ff_defs.pxi'



cdef class SWScale(object):
    cdef SwsContext *sws_ctx
    cdef bytes dst_pix_fmt
    cdef int dst_h
    cdef int dst_w

cdef class Image(object):

    cdef AVFrame *frame
    cdef list byte_planes
    cdef AVPixelFormat pix_fmt

    cdef int free_pict
