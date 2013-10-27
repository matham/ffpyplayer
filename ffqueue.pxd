
include 'ff_defs.pxi'

cimport ffthreading
from ffthreading cimport MTGenerator, MTCond

cdef AVPacket * get_flush_packet() nogil


cdef class FFPacketQueue(object):
    cdef:
        MTGenerator mt_gen
        MyAVPacketList *first_pkt, *last_pkt
        int nb_packets
        int size
        int abort_request
        int serial
        MTCond cond
    
    cdef int packet_queue_put_private(FFPacketQueue self, AVPacket *pkt) nogil
    
    cdef int packet_queue_put(FFPacketQueue self, AVPacket *pkt) nogil
    
    cdef void packet_queue_flush(FFPacketQueue self) nogil
    
    cdef void packet_queue_abort(FFPacketQueue self) nogil
    
    cdef void packet_queue_start(FFPacketQueue self) nogil
    # return < 0 if aborted, 0 if no packet and > 0 if packet.
    cdef int packet_queue_get(FFPacketQueue self, AVPacket *pkt, int block, int *serial) nogil