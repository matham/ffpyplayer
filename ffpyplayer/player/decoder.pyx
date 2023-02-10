
__all__ = ('Decoder', )

include '../includes/ff_consts.pxi'

cdef extern from "string.h" nogil:
    void * memset(void *, int, size_t)

cdef extern from "errno.h" nogil:
    int ENOSYS
    int ENOMEM
    int EAGAIN


cdef class Decoder(object):

    def __cinit__(Decoder self):
        self.avctx = NULL
        self.pkt = NULL

    cdef int decoder_init(
            self, MTGenerator mt_gen, AVCodecContext *avctx, FFPacketQueue queue,
            MTCond empty_queue_cond) nogil except 1:
        self.pkt = av_packet_alloc()

        with gil:
            self.queue = queue
            self.empty_queue_cond = empty_queue_cond
            self.mt_gen = mt_gen
            if self.pkt == NULL:
                raise MemoryError

        self.avctx = avctx
        self.packet_pending = self.finished = 0
        self.seeking = self.start_pts = self.next_pts = 0
        self.seek_req_pos = -1
        self.start_pts = AV_NOPTS_VALUE
        self.pkt_serial = -1
        memset(&self.start_pts_tb, 0, sizeof(self.start_pts_tb))
        memset(&self.next_pts_tb, 0, sizeof(self.next_pts_tb))
        return 0

    cdef void decoder_destroy(self) nogil:
        av_packet_free(&self.pkt)
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

    cdef int decoder_start(self, int_void_func func, const char *thread_name, void *arg) nogil except 1:
        self.queue.packet_queue_start()
        with gil:
            self.decoder_tid = MTThread(self.mt_gen.mt_src)
            self.decoder_tid.create_thread(func, thread_name, arg)
        return 0

    cdef int decoder_decode_frame(self, AVFrame *frame, AVSubtitle *sub, int decoder_reorder_pts) nogil except? 2:
        cdef int ret = AVERROR(EAGAIN)
        cdef int got_frame
        cdef AVRational tb
        cdef int old_serial

        while True:
            if self.queue.serial == self.pkt_serial:
                while True:
                    if self.queue.abort_request:
                        return -1

                    if self.avctx.codec_type == AVMEDIA_TYPE_VIDEO:
                        ret = avcodec_receive_frame(self.avctx, frame)
                        if ret >= 0:
                            if decoder_reorder_pts == -1:
                                frame.pts = frame.best_effort_timestamp
                            elif not decoder_reorder_pts:
                                frame.pts = frame.pkt_dts

                    elif self.avctx.codec_type == AVMEDIA_TYPE_AUDIO:
                        ret = avcodec_receive_frame(self.avctx, frame)
                        if ret >= 0:
                            tb.num = 1
                            tb.den = frame.sample_rate
                            if frame.pts != AV_NOPTS_VALUE:
                                frame.pts = av_rescale_q(frame.pts, self.avctx.pkt_timebase, tb)
                            elif self.next_pts != AV_NOPTS_VALUE:
                                frame.pts = av_rescale_q(self.next_pts, self.next_pts_tb, tb)
                            if frame.pts != AV_NOPTS_VALUE:
                                self.next_pts = frame.pts + frame.nb_samples
                                self.next_pts_tb = tb

                    if ret == AVERROR_EOF:
                        self.finished = self.pkt_serial
                        avcodec_flush_buffers(self.avctx)
                        return 0
                    if ret >= 0:
                        return 1
                    if ret == AVERROR(EAGAIN):
                        break

            while True:
                if not self.queue.nb_packets:
                    self.empty_queue_cond.lock()
                    self.empty_queue_cond.cond_signal()
                    self.empty_queue_cond.unlock()

                if self.packet_pending:
                    self.packet_pending = 0
                else:
                    old_serial = self.pkt_serial
                    if self.queue.packet_queue_get(self.pkt, 1, &self.pkt_serial) < 0:
                        return -1

                    if old_serial != self.pkt_serial:
                        avcodec_flush_buffers(self.avctx)
                        self.finished = 0
                        self.seeking = self.seek_req_pos != -1
                        self.next_pts = self.start_pts
                        self.next_pts_tb = self.start_pts_tb

                if self.queue.serial == self.pkt_serial:
                    break
                av_packet_unref(self.pkt)

            if self.avctx.codec_type == AVMEDIA_TYPE_SUBTITLE:
                got_frame = 0
                ret = avcodec_decode_subtitle2(self.avctx, sub, &got_frame, self.pkt)
                if ret < 0:
                    ret = AVERROR(EAGAIN)
                else:
                    if got_frame and self.pkt.data == NULL:
                       self.packet_pending = 1
                    if got_frame:
                        ret = 0
                    else:
                        ret = AVERROR(EAGAIN) if self.pkt.data != NULL else AVERROR_EOF
                av_packet_unref(self.pkt)
            else:
                if avcodec_send_packet(self.avctx, self.pkt) == AVERROR(EAGAIN):
                    av_log(self.avctx, AV_LOG_ERROR, "Receive_frame and send_packet both returned EAGAIN, which is an API violation.\n")
                    self.packet_pending = 1
                else:
                    av_packet_unref(self.pkt)
