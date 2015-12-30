
include '../includes/ffmpeg.pxi'

from ffpyplayer.threading cimport MTGenerator, MTCond

cdef AVPacket * get_flush_packet() nogil

cdef struct MyAVPacketList:
    AVPacket pkt
    MyAVPacketList *next
    int serial


cdef class FFPacketQueue(object):
    cdef:
        MTGenerator mt_gen
        MyAVPacketList *first_pkt
        MyAVPacketList *last_pkt
        int nb_packets
        int size
        int abort_request
        int serial
        MTCond cond

    cdef int packet_queue_put_private(FFPacketQueue self, AVPacket *pkt) nogil except 1
    cdef int packet_queue_put_nullpacket(FFPacketQueue self, int stream_index) nogil except 1
    cdef int packet_queue_put(FFPacketQueue self, AVPacket *pkt) nogil except 1
    cdef int packet_queue_flush(FFPacketQueue self) nogil except 1
    cdef int packet_queue_abort(FFPacketQueue self) nogil except 1
    cdef int packet_queue_start(FFPacketQueue self) nogil except 1
    # return < 0 if aborted, 0 if no packet and > 0 if packet.
    cdef int packet_queue_get(FFPacketQueue self, AVPacket *pkt, int block, int *serial) nogil except 0
