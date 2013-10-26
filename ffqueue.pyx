
__all__ = ('FFPacketQueue', )

include 'ff_defs_comp.pxi'

cimport ffthreading
from ffthreading cimport MTGenerator, MTMutex, MTCond


cdef AVPacket flush_pkt
av_init_packet(&flush_pkt)
flush_pkt.data = <uint8_t *>&flush_pkt
cdef AVPacket * get_flush_packet() nogil:
    return &flush_pkt


cdef class FFPacketQueue(object):

    def __cinit__(FFPacketQueue self, MTGenerator mt_gen):
        self.mt_gen = mt_gen
        self.first_pkt = self.last_pkt = NULL
        self.nb_packets = self.size = self.serial = 0
        self.mutex = mt_gen.create_mutex()
        self.cond = mt_gen.create_cond()
        self.abort_request = 1
    
    def __dealloc__(self):
        if self.mutex == NULL or self.cond == NULL:
            return
        self.packet_queue_flush()
        self.mt_gen.destroy_mutex(self.mutex)
        self.mt_gen.destroy_cond(self.cond)

    cdef int packet_queue_put_private(FFPacketQueue self, AVPacket *pkt) nogil:
        cdef MyAVPacketList *pkt1
    
        if self.abort_request:
           return -1
    
        pkt1 = <MyAVPacketList*>av_malloc(sizeof(MyAVPacketList))
        if pkt1 == NULL:
            return -1
        pkt1.pkt = pkt[0]
        pkt1.next = NULL
        if pkt == &flush_pkt:
            self.serial += 1
        pkt1.serial = self.serial
    
        if self.last_pkt == NULL:
            self.first_pkt = pkt1
        else:
            self.last_pkt.next = pkt1
        self.last_pkt = pkt1
        self.nb_packets += 1
        self.size += pkt1.pkt.size + sizeof(pkt1[0])
        #/* XXX: should duplicate packet data in DV case */
        self.cond.cond_signal(self.cond.cond)
        return 0

    cdef int packet_queue_put(FFPacketQueue self, AVPacket *pkt) nogil:
        cdef int ret

        #/* duplicate the packet */
        if pkt != &flush_pkt and av_dup_packet(pkt) < 0:
            return -1
     
        self.mutex.lock_mutex(self.mutex.mutex)
        ret = self.packet_queue_put_private(pkt)
        self.mutex.unlock_mutex(self.mutex.mutex)
     
        if pkt != &flush_pkt and ret < 0:
            av_free_packet(pkt)
     
        return ret
 
    cdef void packet_queue_flush(FFPacketQueue self) nogil:
        cdef MyAVPacketList *pkt, *pkt1

        self.mutex.lock_mutex(self.mutex.mutex)
        pkt = self.first_pkt
        while pkt != NULL:
            pkt1 = pkt.next
            av_free_packet(&pkt.pkt)
            av_freep(&pkt)
            pkt = pkt1
        self.last_pkt = NULL
        self.first_pkt = NULL
        self.nb_packets = 0
        self.size = 0
        self.mutex.unlock_mutex(self.mutex.mutex)
     
    cdef void packet_queue_abort(FFPacketQueue self) nogil:
        self.mutex.lock_mutex(self.mutex.mutex)
        self.abort_request = 1
        self.cond.cond_signal(self.cond)
        self.mutex.unlock_mutex(self.mutex.mutex)
     
    cdef void packet_queue_start(FFPacketQueue self) nogil:
        self.mutex.lock_mutex(self.mutex.mutex)
        self.abort_request = 0
        self.packet_queue_put_private(&flush_pkt)
        self.mutex.unlock_mutex(self.mutex.mutex)
 
    # return < 0 if aborted, 0 if no packet and > 0 if packet.
    cdef int packet_queue_get(FFPacketQueue self, AVPacket *pkt, int block, int *serial) nogil:
        cdef MyAVPacketList *pkt1
        cdef int ret
        
        self.mutex.lock_mutex(self.mutex.mutex)
        
        while True:
            if self.abort_request:
                ret = -1
                break
     
            pkt1 = self.first_pkt
            if pkt1 != NULL:
                self.first_pkt = pkt1.next
                if self.first_pkt == NULL:
                    self.last_pkt = NULL
                self.nb_packets -= 1
                self.size -= pkt1.pkt.size + sizeof(pkt1[0])
                pkt[0] = pkt1.pkt
                if serial != NULL:
                    serial[0] = pkt1.serial
                av_free(pkt1)
                ret = 1
                break
            elif not block:
                ret = 0
                break
            else:
                self.cond.cond_wait(self.cond.cond, self.mutex.mutex)
        self.mutex.unlock_mutex(self.mutex.mutex)
        return ret
