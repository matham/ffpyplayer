
include 'ff_defs.pxi'




cdef class MediaWriter(object):
    cdef AVFormatContext *fmt_ctx
    cdef MediaStream *streams
    cdef int n_streams
    cdef list config

    cdef void clean_up(MediaWriter self)


cdef struct MediaStream:
    # pointer to the stream to which we're adding frames.
    AVStream *av_stream
    int index
    AVCodec *codec
    AVCodecContext *codec_ctx
    # codec used to encode video
    AVCodecID codec_id
    # the size of the frame passed in
    int width_in
    int width_out
    # the size of the frame actually written to disk
    int height_in
    int height_out
    # The denominator of the frame rate of the stream
    int den
    # The numerator of the frame rate of the stream
    int num
    # the pixel format of the frame passed in
    AVPixelFormat pix_fmt_in
    # the pixel format of the frame actually written to disk
    # if it's -1 (AV_PIX_FMT_NONE) then input will be used. '''
    AVPixelFormat pix_fmt_out

    # The frame in which the final image to be written to disk is held.
    AVFrame *av_frame
    # If the format passed in is different than the format that
    # is written to disk, this frame holds the image passed in
    AVFrame *av_frame_src
    SwsContext *sws_ctx
    # buffer size of the frame passed in
    int buff_len
    int count
    int64_t pts
    int sync_fmt
