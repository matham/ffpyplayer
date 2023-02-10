
__all__ = ('FFPacketQueue', )

include '../includes/ff_consts.pxi'

from ffpyplayer.threading cimport MTGenerator, MTMutex, MTCond


cdef class FFPacketQueue(object):

    def __cinit__(FFPacketQueue self, MTGenerator mt_gen):
        self.mt_gen = mt_gen
        self.pkt_list = NULL
        self.nb_packets = self.size = self.serial = 0
        self.duration = 0

        self.pkt_list = av_fifo_alloc(sizeof(MyAVPacketList))
        if self.pkt_list == NULL:
            raise MemoryError

        self.cond = MTCond.__new__(MTCond, mt_gen.mt_src)
        self.abort_request = 1

    def __dealloc__(self):
        if self.cond is None:
            return
        with nogil:
            self.packet_queue_flush()
            av_fifo_freep(&self.pkt_list)

    cdef int packet_queue_put_private(FFPacketQueue self, AVPacket *pkt) nogil except 1:
        cdef MyAVPacketList pkt1
        cdef int ret

        if self.abort_request:
            return -1

        if av_fifo_space(self.pkt_list) < sizeof(pkt1):
            ret = av_fifo_grow(self.pkt_list, sizeof(pkt1))
            if ret < 0:
                return ret

        pkt1.pkt = pkt
        pkt1.serial = self.serial

        ret = av_fifo_generic_write(self.pkt_list, &pkt1, sizeof(pkt1), NULL)
        if ret < 0:
            return ret
        self.nb_packets += 1
        self.size += pkt1.pkt.size + sizeof(pkt1)
        self.duration += pkt1.pkt.duration
        #/* XXX: should duplicate packet data in DV case */
        self.cond.cond_signal()
        return 0

    cdef int packet_queue_put(FFPacketQueue self, AVPacket *pkt) nogil except 1:
        cdef AVPacket *pkt1 = av_packet_alloc()
        cdef int ret = -1

        if pkt1 == NULL:
            av_packet_unref(pkt)
            return -1
        av_packet_move_ref(pkt1, pkt)

        self.cond.lock()
        ret = self.packet_queue_put_private(pkt1)
        self.cond.unlock()

        if ret < 0:
            av_packet_free(&pkt1)

        return ret

    cdef int packet_queue_put_nullpacket(FFPacketQueue self, AVPacket *pkt, int stream_index) nogil except 1:
        pkt.stream_index = stream_index
        return self.packet_queue_put(pkt)

    cdef int packet_queue_flush(FFPacketQueue self) nogil except 1:
        cdef MyAVPacketList pkt1
        cdef int ret = 0

        self.cond.lock()
        while av_fifo_size(self.pkt_list) >= sizeof(pkt1):
            ret = av_fifo_generic_read(self.pkt_list, &pkt1, sizeof(pkt1), NULL)
            if ret < 0:
                break
            av_packet_free(&pkt1.pkt)

        self.nb_packets = 0
        self.size = 0
        self.duration = 0
        self.serial += 1
        self.cond.unlock()
        return ret

    cdef int packet_queue_abort(FFPacketQueue self) nogil except 1:
        self.cond.lock()
        self.abort_request = 1
        self.cond.cond_signal()
        self.cond.unlock()
        return 0

    cdef int packet_queue_start(FFPacketQueue self) nogil except 1:
        self.cond.lock()
        self.abort_request = 0
        self.serial += 1
        self.cond.unlock()
        return 0

    # return < 0 if aborted, 0 if no packet and > 0 if packet.
    cdef int packet_queue_get(FFPacketQueue self, AVPacket *pkt, int block, int *serial) nogil except 0:
        cdef MyAVPacketList pkt1
        cdef int ret = 0

        self.cond.lock()

        while True:
            if self.abort_request:
                ret = -1
                break

            if av_fifo_size(self.pkt_list) >= sizeof(pkt1):
                ret = av_fifo_generic_read(self.pkt_list, &pkt1, sizeof(pkt1), NULL)
                if ret < 0:
                    break
                self.nb_packets -= 1
                self.size -= pkt1.pkt.size + sizeof(pkt1)
                self.duration -= pkt1.pkt.duration

                av_packet_move_ref(pkt, pkt1.pkt)
                if serial != NULL:
                    serial[0] = pkt1.serial
                av_packet_free(&pkt1.pkt)
                ret = 1
                break
            elif not block:
                ret = -1
                break
            else:
                self.cond.cond_wait()
        self.cond.unlock()
        return ret
