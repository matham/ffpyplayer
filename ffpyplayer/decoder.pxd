
include 'ff_defs.pxi'

from ffpyplayer.ffthreading cimport MTGenerator, MTCond, MTMutex
from ffpyplayer.ffqueue cimport FFPacketQueue, get_flush_packet


cdef class Decoder(object):
    cdef:
        AVPacket pkt
        AVPacket pkt_temp
        FFPacketQueue queue
        AVCodecContext *avctx
        int pkt_serial
        int finished
        int flushed
        int packet_pending
        MTCond empty_queue_cond
        int64_t start_pts
        AVRational start_pts_tb
        int64_t next_pts
        AVRational next_pts_tb

    cdef void decoder_init(self, AVCodecContext *avctx, FFPacketQueue queue,
                           MTCond empty_queue_cond) nogil
    cdef void decoder_destroy(self) nogil
    cdef int decoder_decode_frame(self, AVFrame *frame, AVSubtitle *sub, int decoder_reorder_pts) nogil except? 2
