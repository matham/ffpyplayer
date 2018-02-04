include 'includes/ffmpeg.pxi'


cdef class SWScale(object):
    cdef SwsContext *sws_ctx
    cdef bytes dst_pix_fmt
    cdef str dst_pix_fmt_s
    cdef int dst_h
    cdef int dst_w
    cdef AVPixelFormat src_pix_fmt
    cdef int src_h
    cdef int src_w


cdef class Image(object):

    cdef AVFrame *frame
    cdef list byte_planes
    cdef AVPixelFormat pix_fmt

    cdef int cython_init(self, AVFrame *frame) nogil except 1
    cpdef is_ref(Image self)
    cpdef is_key_frame(Image self)
    cpdef get_linesizes(Image self, keep_align=*)
    cpdef get_size(Image self)
    cpdef get_pixel_format(Image self)
    cpdef get_buffer_size(Image self, keep_align=*)
    cpdef get_required_buffers(Image self)
    cpdef to_bytearray(Image self, keep_align=*)
    cpdef to_memoryview(Image self, keep_align=*)


cdef class ImageLoader(object):
    cdef AVFormatContext *format_ctx
    cdef AVCodec *codec
    cdef AVCodecContext *codec_ctx
    cdef AVPacket pkt
    cdef AVFrame *frame
    cdef bytes filename
    cdef char msg[256]
    cdef int eof

    cpdef next_frame(self)
    cdef inline object eof_frame(self)
