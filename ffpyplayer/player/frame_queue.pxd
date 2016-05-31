
include '../includes/ffmpeg.pxi'

from ffpyplayer.threading cimport MTGenerator, MTCond, MTMutex
from ffpyplayer.player.queue cimport FFPacketQueue
from ffpyplayer.player.core cimport VideoSettings

cdef struct Frame:
    AVFrame *frame
    int need_conversion
    AVSubtitle sub
    int serial
    double pts  # presentation timestamp for the frame
    double duration  # estimated duration of the frame
    int64_t pos  # byte position of the frame in the input file
    SDL_Overlay *bmp
    int allocated
    int reallocate
    int width
    int height
    AVRational sar
    AVPixelFormat pix_fmt


cdef class FrameQueue(object):
    cdef:
        MTCond cond
        FFPacketQueue pktq
        Frame queue[FRAME_QUEUE_SIZE]
        int rindex
        int windex
        int size
        int max_size
        int keep_last
        int rindex_shown

        MTMutex alloc_mutex
        int requested_alloc

    cdef void frame_queue_unref_item(self, Frame *vp) nogil
    cdef int frame_queue_signal(self) nogil except 1
    cdef int is_empty(self) nogil
    cdef Frame *frame_queue_peek(self) nogil
    cdef Frame *frame_queue_peek_next(self) nogil
    cdef Frame *frame_queue_peek_last(self) nogil
    cdef Frame *frame_queue_peek_writable(self) nogil
    cdef Frame *frame_queue_peek_readable(self) nogil
    cdef int frame_queue_push(self) nogil except 1
    cdef int frame_queue_next(self) nogil except 1
    cdef int frame_queue_prev(self) nogil
    cdef int frame_queue_nb_remaining(self) nogil
    cdef int64_t frame_queue_last_pos(self) nogil
    cdef int copy_picture(self, Frame *vp, AVFrame *src_frame,
                          VideoSettings *player) nogil except 1
    cdef int peep_alloc(self) nogil
    cdef int queue_picture(
        self, AVFrame *src_frame, double pts, double duration, int64_t pos,
        int serial, AVPixelFormat out_fmt, int *abort_request,
        VideoSettings *player) nogil except 1
    cdef int alloc_picture(self) nogil except 1
    cdef int copy_picture(self, Frame *vp, AVFrame *src_frame,
                           VideoSettings *player) nogil except 1
