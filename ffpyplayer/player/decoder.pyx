
__all__ = ('Decoder', )

include '../includes/ff_consts.pxi'

cdef extern from "string.h" nogil:
    void * memset(void *, int, size_t)


cdef class Decoder(object):

    cdef void decoder_init(
            self, MTGenerator mt_gen, AVCodecContext *avctx, FFPacketQueue queue,
            MTCond empty_queue_cond) nogil:
        with gil:
            self.queue = queue
            self.empty_queue_cond = empty_queue_cond
            self.mt_gen = mt_gen
        self.avctx = avctx
        self.packet_pending = self.finished = self.pkt_serial = 0
        self.seeking = self.start_pts = self.next_pts = 0
        self.seek_req_pos = -1
        self.start_pts = AV_NOPTS_VALUE
        memset(&self.pkt, 0, sizeof(self.pkt))
        memset(&self.pkt_temp, 0, sizeof(self.pkt_temp))
        memset(&self.start_pts_tb, 0, sizeof(self.start_pts_tb))
        memset(&self.next_pts_tb, 0, sizeof(self.next_pts_tb))

    cdef void decoder_destroy(self) nogil:
        av_packet_unref(&self.pkt)
        avcodec_free_context(&self.avctx)

    cdef void set_seek_pos(self, double seek_req_pos) nogil:
        self.seek_req_pos = seek_req_pos
        if seek_req_pos == -1:
            self.seeking = 0

    cdef int is_seeking(self) nogil:
        return self.seeking and self.seek_req_pos != -1

    cdef int decoder_abort(self, FrameQueue fq) nogil except 1:
        self.queue.packet_queue_abort()
        fq.frame_queue_signal()
        self.decoder_tid.wait_thread(NULL)
        with gil:
            self.decoder_tid = None
        self.queue.packet_queue_flush()
        return 0

    cdef int decoder_start(self, int_void_func func, void *arg) nogil except 1:
        self.queue.packet_queue_start()
        with gil:
            self.decoder_tid = MTThread(self.mt_gen.mt_src)
            self.decoder_tid.create_thread(func, arg)
        return 0

    cdef int decoder_decode_frame(self, AVFrame *frame, AVSubtitle *sub, int decoder_reorder_pts) nogil except? 2:
        cdef int ret, got_frame = 0
        cdef AVPacket pkt
        cdef AVRational tb

        while True:
            ret = -1
            if self.queue.abort_request:
                return -1

            if not self.packet_pending or self.queue.serial != self.pkt_serial:
                while True:
                    if not self.queue.nb_packets:
                        self.empty_queue_cond.lock()
                        self.empty_queue_cond.cond_signal()
                        self.empty_queue_cond.unlock()
                    if self.queue.packet_queue_get(&pkt, 1, &self.pkt_serial) < 0:
                        return -1

                    if pkt.data == get_flush_packet().data:
                        avcodec_flush_buffers(self.avctx)
                        self.finished = 0
                        self.seeking = self.seek_req_pos != -1
                        self.next_pts = self.start_pts
                        self.next_pts_tb = self.start_pts_tb

                    if pkt.data != get_flush_packet().data and self.queue.serial == self.pkt_serial:
                        break
                av_packet_unref(&self.pkt)
                self.pkt_temp = self.pkt = pkt
                self.packet_pending = 1

                if self.avctx.codec_type == AVMEDIA_TYPE_VIDEO:
                    ret = avcodec_decode_video2(self.avctx, frame, &got_frame, &self.pkt_temp)
                    if got_frame:
                        if decoder_reorder_pts == -1:
                            frame.pts = av_frame_get_best_effort_timestamp(frame)
                        elif not decoder_reorder_pts:
                            frame.pts = frame.pkt_dts

                elif self.avctx.codec_type == AVMEDIA_TYPE_AUDIO:
                    ret = avcodec_decode_audio4(self.avctx, frame, &got_frame, &self.pkt_temp)
                    if got_frame:
                        tb.num = 1
                        tb.den = frame.sample_rate
                        if frame.pts != AV_NOPTS_VALUE:
                            frame.pts = av_rescale_q(frame.pts, av_codec_get_pkt_timebase(self.avctx), tb)
                        elif self.next_pts != AV_NOPTS_VALUE:
                            frame.pts = av_rescale_q(self.next_pts, self.next_pts_tb, tb)
                        if frame.pts != AV_NOPTS_VALUE:
                            self.next_pts = frame.pts + frame.nb_samples
                            self.next_pts_tb = tb
                elif self.avctx.codec_type == AVMEDIA_TYPE_SUBTITLE:
                    ret = avcodec_decode_subtitle2(self.avctx, sub, &got_frame, &self.pkt_temp)

            if ret < 0:
                self.packet_pending = 0
            else:
                self.pkt_temp.dts =\
                self.pkt_temp.pts = AV_NOPTS_VALUE
                if self.pkt_temp.data != NULL:
                    if self.avctx.codec_type != AVMEDIA_TYPE_AUDIO:
                        ret = self.pkt_temp.size
                    self.pkt_temp.data += ret
                    self.pkt_temp.size -= ret
                    if self.pkt_temp.size <= 0:
                        self.packet_pending = 0
                else:
                    if not got_frame:
                        self.packet_pending = 0
                        self.finished = self.pkt_serial

            if got_frame or self.finished:
                break

        return got_frame
