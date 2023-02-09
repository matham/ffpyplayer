
include '../includes/ffmpeg.pxi'

from ffpyplayer.threading cimport MTGenerator, MTCond

cdef struct MyAVPacketList:
    AVPacket *pkt
    int serial


cdef class FFPacketQueue(object):
    cdef:
        MTGenerator mt_gen
        AVFifoBuffer *pkt_list
        int nb_packets
        int size
        int64_t duration
        int abort_request
        int serial
        MTCond cond

    cdef int packet_queue_put_private(FFPacketQueue self, AVPacket *pkt) nogil except 1
    cdef int packet_queue_put_nullpacket(FFPacketQueue self, AVPacket *pkt, int stream_index) nogil except 1
    cdef int packet_queue_put(FFPacketQueue self, AVPacket *pkt) nogil except 1
    cdef int packet_queue_flush(FFPacketQueue self) nogil except 1
    cdef int packet_queue_abort(FFPacketQueue self) nogil except 1
    cdef int packet_queue_start(FFPacketQueue self) nogil except 1
    # return < 0 if aborted, 0 if no packet and > 0 if packet.
    cdef int packet_queue_get(FFPacketQueue self, AVPacket *pkt, int block, int *serial) nogil except 0
