
__all__ = ('FFPacketQueue', )

include 'ff_defs_comp.pxi'
include "inline_funcs.pxi"

cdef extern from "string.h" nogil:
    void * memset(void *, int, size_t)

cdef void raise_py_exception(bytes msg) nogil except *:
    with gil:
        raise Exception(msg)


cdef class FrameQueue(object):

    def __cinit__(FrameQueue self, MTGenerator mt_gen, FFPacketQueue pktq, int max_size, int keep_last):
        self.cond = MTCond.__new__(MTCond, mt_gen.mt_src)
        self.alloc_mutex = MTMutex.__new__(MTMutex, mt_gen.mt_src)
        self.max_size = FFMIN(max_size, FRAME_QUEUE_SIZE)
        cdef int i

        with nogil:
            self.requested_alloc = 0
            memset(self.queue, 0, sizeof(self.queue))
            self.pktq = pktq
            self.keep_last = not not keep_last

            for i in range(self.max_size):
                self.queue[i].pix_fmt = <AVPixelFormat>-1
                self.queue[i].frame = av_frame_alloc()
                self.queue[i].frame_ref = av_frame_alloc()
                if self.queue[i].frame == NULL or self.queue[i].frame_ref == NULL:
                    with gil:
                        raise_py_exception(b'Could not allocate avframe buffer')

    def __dealloc__(self):
        cdef int i
        cdef Frame *vp

        with nogil:
            for i in range(self.max_size):
                vp = &self.queue[i]
                self.frame_queue_unref_item(vp)

    cdef void frame_queue_unref_item(self, Frame *vp) nogil:
        if vp.frame != NULL:
            av_freep(&vp.frame.data[0])
            av_frame_free(&vp.frame)
            vp.frame = NULL
        if vp.frame_ref != NULL:
            av_frame_free(&vp.frame_ref)
            vp.frame_ref = NULL
        avsubtitle_free(&vp.sub)

    cdef int frame_queue_signal(self) nogil except 1:
        self.cond.lock()
        self.cond.cond_signal()
        self.cond.unlock()
        return 0

    cdef Frame *frame_queue_peek(self) nogil:
        return &self.queue[(self.rindex + self.rindex_shown) % self.max_size]

    cdef Frame *frame_queue_peek_next(self) nogil:
        return &self.queue[(self.rindex + self.rindex_shown + 1) % self.max_size]

    cdef Frame *frame_queue_peek_last(self) nogil:
        return &self.queue[self.rindex]

    cdef Frame *frame_queue_peek_writable(self) nogil:
        # wait until we have space to put a new frame
        self.cond.lock()
        while self.size >= self.max_size and not self.pktq.abort_request:
            self.cond.cond_wait()
        self.cond.unlock()

        if self.pktq.abort_request:
            return NULL

        return &self.queue[self.windex]

    cdef int frame_queue_push(self) nogil except 1:
        self.windex += 1
        if self.windex == self.max_size:
            self.windex = 0

        self.cond.lock()
        self.size += 1
        self.cond.unlock()
        return 0

    cdef int frame_queue_next(self) nogil except 1:
        if self.keep_last and not self.rindex_shown:
            self.rindex_shown = 1
            return 0

        self.frame_queue_unref_item(&self.queue[self.rindex])
        self.rindex += 1
        if self.rindex == self.max_size:
            self.rindex = 0

        self.cond.lock()
        self.size -= 1
        self.cond.cond_signal()
        self.cond.unlock()
        return 0

    cdef int frame_queue_prev(self) nogil:
        # jump back to the previous frame if available by resetting rindex_shown
        cdef int ret = self.rindex_shown
        self.rindex_shown = 0
        return ret

    cdef int frame_queue_nb_remaining(self) nogil:
        # return the number of undisplayed frames in the queue
        return self.size - self.rindex_shown

    cdef int64_t frame_queue_last_pos(self) nogil:
        cdef Frame *fp = &self.queue[self.rindex]
        if self.rindex_shown and fp.serial == self.pktq.serial):
            return fp.pos
        else:
            return -1

    cdef int copy_picture(self, Frame *vp, AVFrame *src_frame,
                           VideoSettings *player) nogil except 1:

        IF CONFIG_AVFILTER:
            av_frame_unref(vp.frame_ref)
            av_frame_move_ref(vp.frame_ref, src_frame)
        ELSE:
            if vp.pix_fmt == <AVPixelFormat>src_frame.format:
                av_frame_unref(vp.frame_ref)
                av_frame_move_ref(vp.frame_ref, src_frame)
                return 0
            av_opt_get_int(player.sws_opts, 'sws_flags', 0, &player.sws_flags)
            player.img_convert_ctx = sws_getCachedContext(player.img_convert_ctx,\
            vp.width, vp.height, <AVPixelFormat>src_frame.format, vp.width, vp.height,\
            vp.pix_fmt, player.sws_flags, NULL, NULL, NULL)
            if player.img_convert_ctx == NULL:
                av_log(NULL, AV_LOG_FATAL, "Cannot initialize the conversion context\n")
                raise_py_exception(b'Cannot initialize the conversion context.')
            sws_scale(player.img_convert_ctx, src_frame.data, src_frame.linesize,
                      0, vp.height, vp.frame.data, vp.frame.linesize)
            av_frame_unref(src_frame)
        return 0

    cdef int alloc_picture(self) nogil except 1:
        ''' allocate a picture (needs to do that in main thread to avoid
        potential locking problems '''
        cdef Frame *vp
        self.alloc_mutex.lock()
        if self.requested_alloc:
            vp = &self.queue[self.windex]
            self.frame_queue_unref_item(vp)

            vp.frame = av_frame_alloc()
            vp.frame_ref = av_frame_alloc()
            if vp.frame == NULL or vp.frame_ref == NULL:
                av_log(NULL, AV_LOG_FATAL, "Could not allocate avframe of size %dx%d.\n", vp.width, vp.height)
                raise_py_exception(b'Could not allocate avframe.')
            if (av_image_alloc(vp.frame.data, vp.frame.linesize, vp.width,
                               vp.height, vp.pix_fmt, 1) < 0):
                av_log(NULL, AV_LOG_FATAL, "Could not allocate avframe buffer.\n")
                raise_py_exception(b'Could not allocate avframe buffer')

            vp.frame.width = vp.width
            vp.frame.height = vp.height
            vp.frame.format = <int>vp.pix_fmt

            self.cond.lock()
            vp.allocated = 1
            self.cond.cond_signal()
            self.cond.unlock()
            self.requested_alloc = 0
        self.alloc_mutex.unlock()
        return 0

    cdef int peep_alloc(self) nogil:
        cdef int requested_alloc = 0
        self.alloc_mutex.lock()
        requested_alloc = self.requested_alloc
        self.alloc_mutex.unlock()
        return requested_alloc

    cdef int queue_picture(
            self, AVFrame *src_frame, double pts, double duration, int64_t pos,
            int serial, AVPixelFormat out_fmt, int *abort_request,
            VideoSettings *player) nogil except 1:
        cdef Frame *vp

        IF 0:# and defined(DEBUG_SYNC):
            av_log(NULL, AV_LOG_DEBUG, "frame_type=%c pts=%0.3f\n",
                   av_get_picture_type_char(src_frame.pict_type), pts)

        vp = self.frame_queue_peek_writable()
        if vp == NULL:
            return -1

        vp.sar = src_frame.sample_aspect_ratio

        # alloc or resize hardware picture buffer
        if (vp.frame == NULL or vp.reallocate or (not vp.allocated) or
            vp.width != src_frame.width or vp.height != src_frame.height
            or <int>vp.pix_fmt != <int>out_fmt):
            vp.allocated = 0
            vp.reallocate = 0
            vp.width = src_frame.width
            vp.height = src_frame.height
            vp.pix_fmt = out_fmt

            # the allocation must be done in the main thread to avoid locking problems.
            self.alloc_mutex.lock()
            self.requested_alloc = 1
            self.alloc_mutex.unlock()

            # wait until the picture is allocated
            self.cond.lock()
            while (not vp.allocated) and not self.pktq.abort_request:
                self.cond.cond_wait()
            ''' if the queue is aborted, we have to pop the pending ALLOC event
            or wait for the allocation to complete '''
            if self.pktq.abort_request and self.peep_alloc():
                while not vp.allocated and not abort_request[0]:
                    self.cond.cond_wait()
            self.cond.unlock()

            if self.pktq.abort_request:
                return -1

        # if the frame is not skipped, then display it
        if vp.frame != NULL:
            self.copy_picture(vp, src_frame, player)

            vp.pts = pts
            vp.duration = duration
            vp.pos = pos
            vp.serial = serial
            self.frame_queue_push()
        return 0
