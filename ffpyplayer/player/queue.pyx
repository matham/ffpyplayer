
__all__ = ('FFPacketQueue', )

include '../includes/ff_consts.pxi'

from ffpyplayer.threading cimport MTGenerator, MTMutex, MTCond

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
        self.cond = MTCond.__new__(MTCond, mt_gen.mt_src)
        self.abort_request = 1

    def __dealloc__(self):
        if self.cond is None:
            return
        with nogil:
            self.packet_queue_flush()

    cdef int packet_queue_put_private(FFPacketQueue self, AVPacket *pkt) nogil except 1:
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
        self.cond.cond_signal()
        return 0

    cdef int packet_queue_put(FFPacketQueue self, AVPacket *pkt) nogil except 1:
        cdef int ret

        self.cond.lock()
        ret = self.packet_queue_put_private(pkt)
        self.cond.unlock()

        if pkt != &flush_pkt and ret < 0:
            av_packet_unref(pkt)

        return ret

    cdef int packet_queue_put_nullpacket(FFPacketQueue self, int stream_index) nogil except 1:
        cdef AVPacket pkt1
        cdef AVPacket *pkt = &pkt1
        av_init_packet(pkt)
        pkt.data = NULL
        pkt.size = 0
        pkt.stream_index = stream_index
        return self.packet_queue_put(pkt)

    cdef int packet_queue_flush(FFPacketQueue self) nogil except 1:
        cdef MyAVPacketList *pkt
        cdef MyAVPacketList *pkt1

        self.cond.lock()
        pkt = self.first_pkt
        while pkt != NULL:
            pkt1 = pkt.next
            av_packet_unref(&pkt.pkt)
            av_freep(&pkt)
            pkt = pkt1
        self.last_pkt = NULL
        self.first_pkt = NULL
        self.nb_packets = 0
        self.size = 0
        self.cond.unlock()
        return 0

    cdef int packet_queue_abort(FFPacketQueue self) nogil except 1:
        self.cond.lock()
        self.abort_request = 1
        self.cond.cond_signal()
        self.cond.unlock()
        return 0

    cdef int packet_queue_start(FFPacketQueue self) nogil except 1:
        self.cond.lock()
        self.abort_request = 0
        self.packet_queue_put_private(&flush_pkt)
        self.cond.unlock()
        return 0

    # return < 0 if aborted, 0 if no packet and > 0 if packet.
    cdef int packet_queue_get(FFPacketQueue self, AVPacket *pkt, int block, int *serial) nogil except 0:
        cdef MyAVPacketList *pkt1
        cdef int ret

        self.cond.lock()

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
                ret = -1
                break
            else:
                self.cond.cond_wait()
        self.cond.unlock()
        return ret
