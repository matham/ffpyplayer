
include '../includes/ffmpeg.pxi'

from ffpyplayer.threading cimport MTGenerator, MTCond, MTMutex, MTThread
from ffpyplayer.player.queue cimport FFPacketQueue
from ffpyplayer.player.frame_queue cimport FrameQueue


cdef class Decoder(object):
    cdef:
        AVPacket *pkt
        FFPacketQueue queue
        AVCodecContext *avctx
        int pkt_serial
        int finished
        int packet_pending
        MTCond empty_queue_cond
        int64_t start_pts
        AVRational start_pts_tb
        int64_t next_pts
        AVRational next_pts_tb
        MTThread decoder_tid

        double seek_req_pos
        int seeking
        MTGenerator mt_gen

    cdef int decoder_init(self, MTGenerator mt_gen, AVCodecContext *avctx, FFPacketQueue queue,
                           MTCond empty_queue_cond) nogil except 1
    cdef void decoder_destroy(self) nogil
    cdef void set_seek_pos(self, double seek_req_pos) nogil
    cdef int is_seeking(self) nogil
    cdef int decoder_abort(self, FrameQueue fq) nogil except 1
    cdef int decoder_start(self, int_void_func func, const char *thread_name, void *arg) nogil except 1
    cdef int decoder_decode_frame(self, AVFrame *frame, AVSubtitle *sub, int decoder_reorder_pts) nogil except? 2
