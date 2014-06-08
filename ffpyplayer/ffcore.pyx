#cython: cdivision=True

__all__ = ('VideoState', )

include 'ff_defs_comp.pxi'
include "inline_funcs.pxi"

from ffpyplayer.ffqueue cimport FFPacketQueue, get_flush_packet
from ffpyplayer.ffthreading cimport MTGenerator, MTThread, MTMutex, MTCond, Py_MT
from ffpyplayer.ffclock cimport Clock
from ffpyplayer.sink cimport VideoSink, VideoPicture, SubPicture
from ffpyplayer.pic cimport Image
from cpython.ref cimport PyObject
import traceback


cdef extern from "limits.h" nogil:
    int INT_MAX
    int64_t INT64_MAX
    int64_t INT64_MIN

cdef extern from "math.h" nogil:
    double NAN
    int isnan(double x)
    double fabs(double x)
    double exp(double x)
    double log(double x)

cdef extern from "errno.h" nogil:
    int ENOSYS
    int ENOMEM
    int EAGAIN

cdef extern from "stdio.h" nogil:
    int snprintf(char *, size_t, const char *, ... )

cdef extern from "stdlib.h" nogil:
    int atoi(const char *)

cdef extern from "inttypes.h" nogil:
    const char *PRId64
    const char *PRIx64

cdef extern from "string.h" nogil:
    void * memset(void *, int, size_t)
    void * memcpy(void *, const void *, size_t)
    char * strchr (char *, int)
    int strcmp(const char *, const char *)
    int strncmp(const char *, const char *, size_t)
    char * strerror(int)
    size_t strlen(const char *)
    char * strcat(char *, const char *)
    char * strcpy(char *, const char *)

ctypedef enum LoopState:
    retry,
    display

# XXX: const
cdef AVSampleFormat *sample_fmts = [AV_SAMPLE_FMT_S16, AV_SAMPLE_FMT_NONE]
cdef int *next_nb_channels = [0, 0, 1, 6, 2, 6, 4, 6]

cdef int read_thread_enter(void *obj_id) except? 1 with gil:
    cdef VideoState vs = <VideoState>obj_id
    cdef bytes msg
    try:
        with nogil:
            return vs.read_thread()
    except:
        msg = traceback.format_exc()
        av_log(NULL, AV_LOG_FATAL, msg)
        vs.vid_sink.request_thread(FF_QUIT_EVENT)
        if vs.mt_gen.mt_src == Py_MT:
            raise
        else:
            return 1
cdef int video_thread_enter(void *obj_id) except? 1 with gil:
    cdef VideoState vs = <VideoState>obj_id
    cdef bytes msg
    try:
        with nogil:
            return vs.video_thread()
    except:
        msg = traceback.format_exc()
        av_log(NULL, AV_LOG_FATAL, msg)
        vs.vid_sink.request_thread(FF_QUIT_EVENT)
        if vs.mt_gen.mt_src == Py_MT:
            raise
        else:
            return 1

cdef int subtitle_thread_enter(void *obj_id) except? 1 with gil:
    cdef VideoState vs = <VideoState>obj_id
    cdef bytes msg
    try:
        with nogil:
            return vs.subtitle_thread()
    except:
        msg = traceback.format_exc()
        av_log(NULL, AV_LOG_FATAL, msg)
        vs.vid_sink.request_thread(FF_QUIT_EVENT)
        if vs.mt_gen.mt_src == Py_MT:
            raise
        else:
            return 1

cdef int check_stream_specifier(AVFormatContext *s, AVStream *st, const char *spec) nogil:
    cdef int ret = avformat_match_stream_specifier(s, st, spec)
    if ret < 0:
        av_log(s, AV_LOG_ERROR, "Invalid stream specifier: %s.\n", spec)
    return ret

cdef AVDictionary *filter_codec_opts(AVDictionary *opts, AVCodecID codec_id,
                                     AVFormatContext *s, AVStream *st, AVCodec *codec) nogil:
    cdef AVDictionary *ret = NULL
    cdef AVDictionaryEntry *t = NULL
    cdef int flags
    cdef char prefix = 0
    cdef char *p
    cdef const AVClass *cc = avcodec_get_class()
    cdef int res
    if s.oformat != NULL:
        flags = AV_OPT_FLAG_ENCODING_PARAM
    else:
        flags = AV_OPT_FLAG_DECODING_PARAM
    if codec == NULL:
        if s.oformat != NULL:
            codec = avcodec_find_encoder(codec_id)
        else:
            codec = avcodec_find_decoder(codec_id)

    if st.codec.codec_type == AVMEDIA_TYPE_VIDEO:
        prefix  = 'v'
        flags  |= AV_OPT_FLAG_VIDEO_PARAM
    elif st.codec.codec_type ==  AVMEDIA_TYPE_AUDIO:
        prefix  = 'a'
        flags  |= AV_OPT_FLAG_AUDIO_PARAM
    elif st.codec.codec_type ==  AVMEDIA_TYPE_SUBTITLE:
        prefix  = 's'
        flags  |= AV_OPT_FLAG_SUBTITLE_PARAM

    while 1:
        t = av_dict_get(opts, "", t, AV_DICT_IGNORE_SUFFIX)
        if t == NULL:
            break
        p = strchr(t.key, ':')

        # check stream specification in opt name
        if p != NULL:
            res = check_stream_specifier(s, st, p + 1)
            if res == 1:
                p[0] = 0
            elif res == 0:
                continue
            else:
                return NULL

        if (av_opt_find(&cc, t.key, NULL, flags, AV_OPT_SEARCH_FAKE_OBJ) != NULL or
            (codec != NULL and codec.priv_class != NULL and
             av_opt_find(&codec.priv_class, t.key, NULL, flags, AV_OPT_SEARCH_FAKE_OBJ) != NULL)):
            av_dict_set(&ret, t.key, t.value, 0)
        elif (t.key[0] == prefix and av_opt_find(&cc, t.key + 1, NULL, flags,
                                                 AV_OPT_SEARCH_FAKE_OBJ) != NULL):
            av_dict_set(&ret, t.key + 1, t.value, 0)

        if p != NULL:
            p[0] = ':'
    return ret

cdef int is_realtime(AVFormatContext *s) nogil:
    if((not strcmp(s.iformat.name, "rtp")) or
       (not strcmp(s.iformat.name, "rtsp")) or
       not strcmp(s.iformat.name, "sdp")):
        return 1
    if s.pb and ((not strncmp(s.filename, "rtp:", 4)) or
                 not strncmp(s.filename, "udp:", 4)):
        return 1
    return 0

cdef AVDictionary **setup_find_stream_info_opts(AVFormatContext *s, AVDictionary *codec_opts) nogil:
    cdef int i
    cdef AVDictionary **opts

    if not s.nb_streams:
        return NULL
    opts = <AVDictionary **>av_mallocz(s.nb_streams * sizeof(AVDictionary *))
    if opts == NULL:
        av_log(NULL, AV_LOG_ERROR, "Could not alloc memory for stream options.\n")
        return NULL
    for i in range(s.nb_streams):
        opts[i] = filter_codec_opts(codec_opts, s.streams[i].codec.codec_id,
                                    s, s.streams[i], NULL)
    return opts

cdef bytes py_pat = <bytes>("%7.2f %s:%7.3f fd=%4d aq=%5dKB vq=%5dKB sq=%5dB f=%" +
                            PRId64 + "/%" + PRId64 + "   \r")
cdef char *py_pat_str = py_pat
cdef bytes av_str = b"A-V", mv_str = b"M-V", ma_str = b"M-A", empty_str = b"   "
cdef char *str_av = av_str
cdef char *str_mv = mv_str
cdef char *str_ma = ma_str
cdef char *str_empty = empty_str


cdef class VideoState(object):

    def __cinit__(VideoState self):
        self.self_id = <PyObject*>self
        self.metadata = {'src_vid_size':(0, 0), 'sink_vid_size':(0, 0),
                         'title':'', 'duration':0.0, 'frame_rate':(0, 0),
                         'src_pix_fmt': ''}

    cdef int cInit(VideoState self, MTGenerator mt_gen, VideoSink vid_sink,
                   VideoSettings *player, int paused) nogil except 1:
        cdef int i
        self.player = player
        memset(self.pictq, 0, sizeof(self.pictq))

        for i in range(VIDEO_PICTURE_QUEUE_SIZE):
            self.pictq[i].pix_fmt = <AVPixelFormat>-1

        IF not CONFIG_AVFILTER:
            self.player.img_convert_ctx = NULL
        self.iformat = player.file_iformat
        with gil:
            self.subtitle_tid = None
            self.read_tid = None
            self.video_tid = None
            self.mt_gen = mt_gen
            self.vid_sink = vid_sink
            self.audioq = FFPacketQueue.__new__(FFPacketQueue, mt_gen)
            self.subtitleq = FFPacketQueue.__new__(FFPacketQueue, mt_gen)
            self.videoq = FFPacketQueue.__new__(FFPacketQueue, mt_gen)

            # start video display
            self.pictq_cond = MTCond.__new__(MTCond, mt_gen.mt_src)
            self.subpq_cond = MTCond.__new__(MTCond, mt_gen.mt_src)
            self.continue_read_thread = MTCond.__new__(MTCond, mt_gen.mt_src)
            self.pause_cond = MTCond.__new__(MTCond, mt_gen.mt_src)

            self.vidclk = Clock.__new__(Clock)
            self.audclk = Clock.__new__(Clock)
            self.extclk = Clock.__new__(Clock)

        self.vidclk.cInit(&self.videoq.serial)
        self.audclk.cInit(&self.audioq.serial)
        self.extclk.cInit(NULL)

        self.audio_clock_serial = -1
        self.audio_last_serial = -1
        self.av_sync_type = player.av_sync_type
        self.reached_eof = 0
        if paused:
            self.toggle_pause()

        with gil:
            self.read_tid = MTThread.__new__(MTThread, mt_gen.mt_src)
            self.read_tid.create_thread(read_thread_enter, self.self_id)
        return 0

    def __dealloc__(VideoState self):
        with nogil:
            self.cquit()

    cdef int cquit(VideoState self) nogil except 1:
        cdef int i
        # XXX: use a special url_shutdown call to abort parse cleanly
        if self.read_tid is None:
            return 0
        self.abort_request = 1
        self.pause_cond.lock()
        self.pause_cond.cond_signal()
        self.pause_cond.unlock()
        self.read_tid.wait_thread(NULL)

        with gil:
            self.read_tid = None
        # free all pictures
        for i in range(VIDEO_PICTURE_QUEUE_SIZE):
            self.vid_sink.free_alloc(&self.pictq[i])
        for i in range(SUBPICTURE_QUEUE_SIZE):
            avsubtitle_free(&self.subpq[i].sub)
        IF not CONFIG_AVFILTER:
            sws_freeContext(self.player.img_convert_ctx)

        return 0

    cdef int decode_interrupt_cb(VideoState self) nogil:
        return self.abort_request

    cdef int get_master_sync_type(VideoState self) nogil:
        if self.av_sync_type == AV_SYNC_VIDEO_MASTER:
            if self.video_st != NULL:
                return AV_SYNC_VIDEO_MASTER
            else:
                return AV_SYNC_AUDIO_MASTER
        elif self.av_sync_type == AV_SYNC_AUDIO_MASTER:
            if self.audio_st != NULL:
                return AV_SYNC_AUDIO_MASTER
            else:
                return AV_SYNC_EXTERNAL_CLOCK
        else:
            return AV_SYNC_EXTERNAL_CLOCK

    # get the current master clock value
    cdef double get_master_clock(VideoState self) nogil except? 0.0:
        cdef double val
        cdef int sync_type = self.get_master_sync_type()

        if sync_type == AV_SYNC_VIDEO_MASTER:
            val = self.vidclk.get_clock()
        elif sync_type == AV_SYNC_AUDIO_MASTER:
            val = self.audclk.get_clock()
        else:
            val = self.extclk.get_clock()
        return val

    cdef int check_external_clock_speed(VideoState self) nogil except 1:
        cdef double speed
        if self.video_stream >= 0 and self.videoq.nb_packets <= MIN_FRAMES / 2 or\
        self.audio_stream >= 0 and self.audioq.nb_packets <= MIN_FRAMES / 2:
            self.extclk.set_clock_speed(FFMAXD(EXTERNAL_CLOCK_SPEED_MIN, self.extclk.speed - EXTERNAL_CLOCK_SPEED_STEP))
        elif (self.video_stream < 0 or self.videoq.nb_packets > MIN_FRAMES * 2) and\
        (self.audio_stream < 0 or self.audioq.nb_packets > MIN_FRAMES * 2):
            self.extclk.set_clock_speed(FFMIND(EXTERNAL_CLOCK_SPEED_MAX, self.extclk.speed + EXTERNAL_CLOCK_SPEED_STEP))
        else:
            speed = self.extclk.speed
            if speed != 1.0:
                self.extclk.set_clock_speed(speed + EXTERNAL_CLOCK_SPEED_STEP * (1.0 - speed) / fabs(1.0 - speed))
        return 0

    # seek in the stream
    cdef int stream_seek(VideoState self, int64_t pos, int64_t rel, int seek_by_bytes, int flush) nogil except 1:
        if not self.seek_req:
            self.seek_pos = pos
            self.seek_rel = rel
            self.seek_flags &= ~AVSEEK_FLAG_BYTE
            if seek_by_bytes:
                self.seek_flags |= AVSEEK_FLAG_BYTE
            self.seek_req = 1
            self.continue_read_thread.lock()
            self.continue_read_thread.cond_signal()
            self.continue_read_thread.unlock()
            if flush:
                while self.pictq_size:
                    self.pictq_next_picture()
        return 0

    # pause or resume the video
    cdef int toggle_pause(VideoState self) nogil except 1:
        if self.paused:
            self.frame_timer += av_gettime() / 1000000.0 + self.vidclk.pts_drift - self.vidclk.pts
            if self.read_pause_return != AVERROR(ENOSYS):
                self.vidclk.paused = 0
            self.vidclk.set_clock(self.vidclk.get_clock(), self.vidclk.serial)
        self.extclk.set_clock(self.extclk.get_clock(), self.extclk.serial)
        self.paused = self.audclk.paused = self.vidclk.paused = self.extclk.paused = not self.paused
        self.pause_cond.lock()
        self.pause_cond.cond_signal()
        self.pause_cond.unlock()
        return 0

    cdef double compute_target_delay(VideoState self, double delay) nogil except? 0.0:
        cdef double sync_threshold, diff

        # update delay to follow master synchronisation source
        if self.get_master_sync_type() != AV_SYNC_VIDEO_MASTER:
            ''' if video is slave, we try to correct big delays by
               duplicating or deleting a frame '''
            diff = self.vidclk.get_clock() - self.get_master_clock()
            ''' skip or repeat frame. We take into account the
               delay to compute the threshold. I still don't know
               if it is the best guess '''
            sync_threshold = FFMAXD(AV_SYNC_THRESHOLD_MIN, FFMIND(AV_SYNC_THRESHOLD_MAX, delay))
            if (not isnan(diff)) and fabs(diff) < self.max_frame_duration:
                if diff <= -sync_threshold:
                    delay = FFMAXD(0, delay + diff)
                elif diff >= sync_threshold and delay > AV_SYNC_FRAMEDUP_THRESHOLD:
                    delay = delay + diff
                elif diff >= sync_threshold:
                    delay = 2 * delay

        #av_dlog(NULL, "video: delay=%0.3f A-V=%f\n", delay, -diff)
        return delay

    cdef double vp_duration(VideoState self, VideoPicture *vp, VideoPicture *nextvp) nogil except? 0.0:
        cdef double duration
        if vp.serial == nextvp.serial:
            duration = nextvp.pts - vp.pts
            if isnan(duration) or duration <= 0 or duration > self.max_frame_duration:
                return vp.duration
            else:
                return duration
        else:
            return 0.0

    cdef int pictq_next_picture(VideoState self) nogil except 1:
        # update queue size and signal for next picture
        self.pictq_rindex += 1
        if self.pictq_rindex == VIDEO_PICTURE_QUEUE_SIZE:
            self.pictq_rindex = 0

        self.pictq_cond.lock()
        self.pictq_size -= 1
        self.pictq_cond.cond_signal()
        self.pictq_cond.unlock()
        return 0

    cdef int pictq_prev_picture(VideoState self) nogil except -1:
        cdef VideoPicture *prevvp
        cdef int ret = 0
        # update queue size and signal for the previous picture
        prevvp = &self.pictq[(self.pictq_rindex + VIDEO_PICTURE_QUEUE_SIZE - 1) % VIDEO_PICTURE_QUEUE_SIZE]
        if prevvp.allocated and prevvp.serial == self.videoq.serial:
            self.pictq_cond.lock()
            if self.pictq_size < VIDEO_PICTURE_QUEUE_SIZE:
                self.pictq_rindex -= 1
                if self.pictq_rindex == -1:
                    self.pictq_rindex = VIDEO_PICTURE_QUEUE_SIZE - 1
                self.pictq_size += 1
                ret = 1
            self.pictq_cond.cond_signal()
            self.pictq_cond.unlock()
        return ret

    cdef void update_video_pts(VideoState self, double pts, int64_t pos, int serial) nogil:
        # update current video pts
        self.vidclk.set_clock(pts, serial)
        self.extclk.sync_clock_to_slave(self.vidclk)
        self.video_current_pos = pos

    #XXX refactor this crappy function
    cdef int video_refresh(VideoState self, Image next_image, double *pts, double *remaining_time,
                           int force_refresh) nogil except -1:
        ''' Returns: 1 = paused, 2 = eof, 3 = no pic but remaining_time is set, 0 = valid image
        '''
        cdef VideoPicture *vp
        cdef VideoPicture *vp_temp
        cdef VideoPicture *lastvp
        cdef double time
        cdef SubPicture *sp
        cdef SubPicture *sp2
        cdef int redisplay
        cdef LoopState state = retry
        cdef double last_duration, duration, delay
        cdef VideoPicture *nextvp
        cdef int64_t cur_time
        cdef int aqsize, vqsize, sqsize
        cdef double av_diff
        cdef const char *pat
        cdef char *m
        cdef int64_t m2, m3
        cdef int result = 3
        cdef AVFrame *frame
        remaining_time[0] = 0.

        self.alloc_picture()
        if self.paused and not force_refresh:
            return 1  # paused
        if (not self.paused) and self.get_master_sync_type() == AV_SYNC_EXTERNAL_CLOCK and self.realtime:
            self.check_external_clock_speed()

        if self.video_st != NULL:
            redisplay = 0
            if force_refresh:
                redisplay = self.pictq_prev_picture()
            while True:
                if state == retry:
                    if self.pictq_size == 0:
                        if self.reached_eof:
                            return 2  # eof
                        # nothing to do, no picture to display in the queue
                    else:
                        # dequeue the picture
                        vp = &self.pictq[self.pictq_rindex]
                        lastvp = &self.pictq[(self.pictq_rindex + VIDEO_PICTURE_QUEUE_SIZE - 1) % VIDEO_PICTURE_QUEUE_SIZE]
                        if vp.serial != self.videoq.serial:
                            self.pictq_next_picture()
                            redisplay = 0
                            continue

                        if self.paused:
                            state = display
                            continue

                        # compute nominal last_duration
                        last_duration = self.vp_duration(lastvp, vp)
                        if redisplay:
                            delay = 0.0
                        else:
                            delay = self.compute_target_delay(last_duration)

                        time = av_gettime() / 1000000.0
                        if time < self.frame_timer + delay and not redisplay:
                            remaining_time[0] = self.frame_timer + delay - time

                        self.frame_timer += delay
                        if delay > 0 and time - self.frame_timer > AV_SYNC_THRESHOLD_MAX:
                            self.frame_timer = time

                        self.pictq_cond.lock()
                        if (not redisplay) and not isnan(vp.pts):
                            self.update_video_pts(vp.pts, vp.pos, vp.serial)
                        self.pictq_cond.unlock()

                        if self.pictq_size > 1:
                            nextvp = &self.pictq[(self.pictq_rindex + 1) % VIDEO_PICTURE_QUEUE_SIZE]
                            duration = self.vp_duration(vp, nextvp)
                            if (redisplay or self.player.framedrop > 0 or\
                            (self.player.framedrop and self.get_master_sync_type() != AV_SYNC_VIDEO_MASTER))\
                            and time > self.frame_timer + duration:
                                if not redisplay:
                                    self.frame_drops_late += 1
                                self.pictq_next_picture()
                                redisplay = 0
                                continue

                        if self.subtitle_st != NULL:
                            while self.subpq_size > 0:
                                sp = &self.subpq[self.subpq_rindex]

                                if self.subpq_size > 1:
                                    sp2 = &self.subpq[(self.subpq_rindex + 1) % SUBPICTURE_QUEUE_SIZE]
                                else:
                                    sp2 = NULL

                                if sp.serial != self.subtitleq.serial\
                                or (self.vidclk.pts > (sp.pts + <float> sp.sub.end_display_time / 1000.))\
                                or (sp2 != NULL and self.vidclk.pts > (sp2.pts + <float> sp2.sub.start_display_time / 1000.)):
                                    avsubtitle_free(&sp.sub)

                                    # update queue size and signal for next picture
                                    self.subpq_rindex += 1
                                    if self.subpq_rindex == SUBPICTURE_QUEUE_SIZE:
                                        self.subpq_rindex = 0

                                    self.subpq_cond.lock()
                                    self.subpq_size -= 1
                                    self.subpq_cond.cond_signal()
                                    self.subpq_cond.unlock()
                                else:
                                    break
                        state = display
                        continue
                elif state == display:
                    # display picture
                    if (not self.player.video_disable) and self.video_st != NULL:
                        vp_temp = &(self.pictq[self.pictq_rindex])
                        if vp_temp.pict != NULL:
                            if CONFIG_AVFILTER or vp_temp.pix_fmt == <AVPixelFormat>vp_temp.pict_ref.format:
                                frame = vp_temp.pict_ref
                            else:
                                frame = vp_temp.pict
                            next_image.cython_init(frame)
                            pts[0] = vp_temp.pts
                            result = 0
                    self.pictq_next_picture()
                break

        if self.player.show_status:

            cur_time = av_gettime()
            if (not self.last_time) or (cur_time - self.last_time) >= 30000:
                aqsize = 0
                vqsize = 0
                sqsize = 0
                if self.audio_st != NULL:
                    aqsize = self.audioq.size
                if self.video_st != NULL:
                    vqsize = self.videoq.size
                if self.subtitle_st != NULL:
                    sqsize = self.subtitleq.size
                av_diff = 0
                if self.audio_st != NULL and self.video_st != NULL:
                    av_diff = self.audclk.get_clock() - self.vidclk.get_clock()
                elif self.video_st != NULL:
                    av_diff = self.get_master_clock() - self.vidclk.get_clock()
                elif self.audio_st != NULL:
                    av_diff = self.get_master_clock() - self.audclk.get_clock()

                m = (str_av if self.audio_st != NULL and self.video_st != NULL else\
                (str_mv if self.video_st != NULL else (str_ma if self.audio_st != NULL else str_empty)))
                m2 = self.video_st.codec.pts_correction_num_faulty_dts if self.video_st != NULL else 0
                m3 = self.video_st.codec.pts_correction_num_faulty_pts if self.video_st != NULL else 0

                av_log(NULL, AV_LOG_INFO,
                       py_pat_str,
                       self.get_master_clock(),
                       m,
                       av_diff,
                       self.frame_drops_early + self.frame_drops_late,
                       aqsize / 1024,
                       vqsize / 1024,
                       sqsize,
                       m2,
                       m3)
                self.last_time = cur_time
        return result


    ''' allocate a picture (needs to do that in main thread to avoid
    potential locking problems '''
    cdef int alloc_picture(VideoState self) nogil except 1:
        cdef VideoPicture *vp
        self.vid_sink.alloc_mutex.lock()
        if self.vid_sink.requested_alloc:
            vp = &self.pictq[self.pictq_windex]
            self.vid_sink.alloc_picture(vp)
            self.pictq_cond.lock()
            vp.allocated = 1
            self.pictq_cond.cond_signal()
            self.pictq_cond.unlock()
            self.vid_sink.requested_alloc = 0
        self.vid_sink.alloc_mutex.unlock()
        return 0


    cdef int queue_picture(VideoState self, AVFrame *src_frame, double pts,
                           double duration, int64_t pos, int serial,
                           AVPixelFormat out_fmt) nogil except 1:
        cdef VideoPicture *vp

        IF 0:# and defined(DEBUG_SYNC):
            av_log(NULL, AV_LOG_DEBUG, "frame_type=%c pts=%0.3f\n",
                   av_get_picture_type_char(src_frame.pict_type), pts)
        # wait until we have space to put a new picture
        self.pictq_cond.lock()
        # keep the last already displayed picture in the queue
        while (self.pictq_size >= VIDEO_PICTURE_QUEUE_SIZE - 1 and
               not self.videoq.abort_request):
            self.pictq_cond.cond_wait()
        self.pictq_cond.unlock()

        if self.videoq.abort_request:
            return -1

        vp = &self.pictq[self.pictq_windex]
        vp.sar = src_frame.sample_aspect_ratio

        # alloc or resize hardware picture buffer
        if (vp.pict == NULL or vp.reallocate or (not vp.allocated) or
            vp.width != src_frame.width or vp.height != src_frame.height
            or <int>vp.pix_fmt != <int>out_fmt):
            vp.allocated = 0
            vp.reallocate = 0
            vp.width = src_frame.width
            vp.height = src_frame.height
            vp.pix_fmt = out_fmt
            ''' the allocation must be done in the main thread to avoid
            locking problems. '''
            self.vid_sink.request_thread(FF_ALLOC_EVENT)
            # wait until the picture is allocated
            self.pictq_cond.lock()
            while (not vp.allocated) and not self.videoq.abort_request:
                self.pictq_cond.cond_wait()
            ''' if the queue is aborted, we have to pop the pending ALLOC event
            or wait for the allocation to complete '''
            if self.videoq.abort_request and self.vid_sink.peep_alloc():
                while not vp.allocated:
                    self.pictq_cond.cond_wait()
            self.pictq_cond.unlock()

            if self.videoq.abort_request:
                return -1

        # if the frame is not skipped, then display it
        if vp.pict != NULL:
            self.vid_sink.copy_picture(vp, src_frame, self.player)

            vp.pts = pts
            vp.duration = duration
            vp.pos = pos
            vp.serial = serial

            # now we can update the picture count
            self.pictq_windex += 1
            if self.pictq_windex == VIDEO_PICTURE_QUEUE_SIZE:
                self.pictq_windex = 0
            self.pictq_cond.lock()
            self.pictq_size += 1
            self.pictq_cond.unlock()
        return 0

    cdef int get_video_frame(VideoState self, AVFrame *frame, AVPacket *pkt, int *serial) nogil except 2:
        cdef int got_picture
        cdef int ret = 1
        cdef double dpts = NAN, diff
        if self.videoq.packet_queue_get(pkt, 1, serial) < 0:
            return -1
        if pkt.data == get_flush_packet().data:
            avcodec_flush_buffers(self.video_st.codec)

            self.pictq_cond.lock()
            ''' Make sure there are no long delay timers (ideally we should
            just flush the queue but that's harder)'''
            while self.pictq_size and not self.videoq.abort_request:
                self.pictq_cond.cond_wait()
            self.video_current_pos = -1
            self.frame_timer = <double>av_gettime() / 1000000.0
            self.pictq_cond.unlock()
            return 0
        if avcodec_decode_video2(self.video_st.codec, frame, &got_picture, pkt) < 0:
            return 0

        if (not got_picture) and not pkt.data:
            self.video_finished = serial[0]
        if got_picture:
            if self.player.decoder_reorder_pts == -1:
                frame.pts = av_frame_get_best_effort_timestamp(frame)
            elif self.player.decoder_reorder_pts:
                frame.pts = frame.pkt_pts
            else:
                frame.pts = frame.pkt_dts

            if frame.pts != AV_NOPTS_VALUE:
                dpts = av_q2d(self.video_st.time_base) * frame.pts

            frame.sample_aspect_ratio = av_guess_sample_aspect_ratio(self.ic, self.video_st, frame)

            if self.player.framedrop > 0 or (self.player.framedrop and\
            self.get_master_sync_type() != AV_SYNC_VIDEO_MASTER):
                if frame.pts != AV_NOPTS_VALUE:
                    diff = dpts - self.get_master_clock()
                    if (not isnan(diff)) and fabs(diff) < AV_NOSYNC_THRESHOLD and\
                    diff - self.frame_last_filter_delay < 0 and serial[0] == self.vidclk.serial and\
                    self.videoq.nb_packets:
                        self.frame_drops_early += 1
                        av_frame_unref(frame)
                        ret = 0
            return ret
        return 0

    IF CONFIG_AVFILTER:
        cdef int configure_filtergraph(VideoState self, AVFilterGraph *graph, const char *filtergraph,
                                       AVFilterContext *source_ctx, AVFilterContext *sink_ctx) nogil except? 1:
            cdef int ret = 0
            cdef AVFilterInOut *outputs = NULL
            cdef AVFilterInOut *inputs = NULL

            if filtergraph != NULL:
                outputs = avfilter_inout_alloc()
                inputs  = avfilter_inout_alloc()
                if outputs == NULL or inputs == NULL:
                    ret = AVERROR(ENOMEM)

                if not ret:
                    outputs.name       = av_strdup("in")
                    outputs.filter_ctx = source_ctx
                    outputs.pad_idx    = 0
                    outputs.next       = NULL

                    inputs.name        = av_strdup("out")
                    inputs.filter_ctx  = sink_ctx
                    inputs.pad_idx     = 0
                    inputs.next        = NULL

                    ret = avfilter_graph_parse_ptr(graph, filtergraph, &inputs,
                                                   &outputs, NULL)
                    if ret > 0:
                        ret = 0
            else:
                ret = avfilter_link(source_ctx, 0, sink_ctx, 0)
                if ret > 0:
                    ret = 0
            if not ret:
                ret = avfilter_graph_config(graph, NULL)
            avfilter_inout_free(&outputs)
            avfilter_inout_free(&inputs)
            return ret

        cdef int configure_video_filters(VideoState self, AVFilterGraph *graph,
                                         const char *vfilters, AVFrame *frame,
                                         AVPixelFormat pix_fmt) nogil except? 1:
            cdef char sws_flags_str[128]
            cdef char buffersrc_args[256]
            cdef char scale_args[256]
            cdef char str_flags[64]
            cdef int ret
            cdef AVFilterContext *filt_src = NULL
            cdef AVFilterContext *filt_out = NULL
            cdef AVFilterContext *filt_crop = NULL
            cdef AVFilterContext *filt_scale = NULL
            cdef AVCodecContext *codec = self.video_st.codec
            cdef AVRational fr = av_guess_frame_rate(self.ic, self.video_st, NULL)
            cdef AVPixelFormat *pix_fmts = [pix_fmt, AV_PIX_FMT_NONE]
            memset(str_flags, 0, sizeof(str_flags))
            strcpy(str_flags, "flags=%")
            strcat(str_flags, PRId64)

            av_opt_get_int(self.player.sws_opts, "sws_flags", 0, &self.player.sws_flags)
            snprintf(sws_flags_str, sizeof(sws_flags_str), str_flags, self.player.sws_flags)
            graph.scale_sws_opts = av_strdup(sws_flags_str)

            snprintf(buffersrc_args, sizeof(buffersrc_args),
                     "video_size=%dx%d:pix_fmt=%d:time_base=%d/%d:pixel_aspect=%d/%d",
                     frame.width, frame.height, frame.format,
                     self.video_st.time_base.num, self.video_st.time_base.den,
                     codec.sample_aspect_ratio.num, FFMAX(codec.sample_aspect_ratio.den, 1))
            if fr.num and fr.den:
                av_strlcatf(buffersrc_args, sizeof(buffersrc_args), ":frame_rate=%d/%d", fr.num, fr.den)

            ret = avfilter_graph_create_filter(&filt_src, avfilter_get_by_name("buffer"),
                                               "ffpyplayer_buffer", buffersrc_args, NULL, graph)
            if ret < 0:
                return ret

            ret = avfilter_graph_create_filter(&filt_out, avfilter_get_by_name("buffersink"),
                                               "ffpyplayer_buffersink", NULL, NULL, graph)
            if ret < 0:
                return ret

            ret = av_opt_set_int_list(filt_out, "pix_fmts", pix_fmts,
                                      sizeof(pix_fmts[0]), AV_PIX_FMT_NONE, AV_OPT_SEARCH_CHILDREN)
            if ret < 0:
                return ret


            ''' SDL YUV code is not handling odd width/height for some driver
            combinations, therefore we crop the picture to an even width/height. '''
            ret = avfilter_graph_create_filter(&filt_crop, avfilter_get_by_name("crop"),
                                               "ffpyplayer_crop", "floor(in_w/2)*2:floor(in_h/2)*2",
                                               NULL, graph)
            if ret < 0:
                return ret
            ret = avfilter_link(filt_crop, 0, filt_out, 0)
            if ret < 0:
                return ret

            if self.player.screen_height or self.player.screen_width:
                snprintf(scale_args, sizeof(scale_args), "%d:%d", self.player.screen_width,
                         self.player.screen_height)
                ret = avfilter_graph_create_filter(&filt_scale, avfilter_get_by_name("scale"),
                                                   "ffpyplayer_scale", scale_args,
                                                   NULL, graph)
                if ret < 0:
                    return ret

                ret = avfilter_link(filt_scale, 0, filt_crop, 0)
                if ret < 0:
                    return ret
                # this needs to be here in case user provided filter at the input
                ret = self.configure_filtergraph(graph, vfilters, filt_src, filt_scale)
                if ret < 0:
                    return ret
            else:
                ret = self.configure_filtergraph(graph, vfilters, filt_src, filt_crop)
                if ret < 0:
                    return ret

            self.in_video_filter  = filt_src
            self.out_video_filter = filt_out
            return ret

        cdef int configure_audio_filters(VideoState self, const char *afilters, int force_output_format) nogil except? 1:
            cdef int *sample_rates = [0, -1]
            cdef int64_t *channel_layouts = [0, -1]
            cdef int *channels = [0, -1]
            cdef AVFilterContext *filt_asrc = NULL
            cdef AVFilterContext *filt_asink = NULL
            cdef char aresample_swr_opts[512]
            cdef AVDictionaryEntry *e = NULL
            cdef char asrc_args[256]
            cdef char str_flags[64]
            cdef int ret

            memset(str_flags, 0, sizeof(str_flags))
            strcpy(str_flags, ":channel_layout=0x%")
            strcat(str_flags, PRIx64)
            aresample_swr_opts[0] = 0
            avfilter_graph_free(&self.agraph)
            self.agraph = avfilter_graph_alloc()
            if self.agraph == NULL:
                return AVERROR(ENOMEM)
            e = av_dict_get(self.player.swr_opts, "", e, AV_DICT_IGNORE_SUFFIX)
            while e != NULL:
                av_strlcatf(aresample_swr_opts, sizeof(aresample_swr_opts), "%s=%s:", e.key, e.value)
                e = av_dict_get(self.player.swr_opts, "", e, AV_DICT_IGNORE_SUFFIX)
            if strlen(aresample_swr_opts):
                aresample_swr_opts[strlen(aresample_swr_opts)-1] = '\0'
            av_opt_set(self.agraph, "aresample_swr_opts", aresample_swr_opts, 0)

            ret = snprintf(asrc_args, sizeof(asrc_args),
                           "sample_rate=%d:sample_fmt=%s:channels=%d:time_base=%d/%d",
                           self.audio_filter_src.freq, av_get_sample_fmt_name(self.audio_filter_src.fmt),
                           self.audio_filter_src.channels, 1, self.audio_filter_src.freq)
            if self.audio_filter_src.channel_layout:
                snprintf(asrc_args + ret, sizeof(asrc_args) - ret, str_flags,
                         self.audio_filter_src.channel_layout)

            ret = avfilter_graph_create_filter(&filt_asrc, avfilter_get_by_name("abuffer"),
                                               "ffpyplayer_abuffer", asrc_args, NULL, self.agraph)
            if ret >= 0:
                ret = avfilter_graph_create_filter(&filt_asink, avfilter_get_by_name("abuffersink"),
                                                   "ffpyplayer_abuffersink", NULL, NULL, self.agraph)
            if ret >= 0:
                ret = av_opt_set_int_list(filt_asink, "sample_fmts", sample_fmts, sizeof(sample_fmts[0]),
                                          AV_SAMPLE_FMT_NONE, AV_OPT_SEARCH_CHILDREN)
            if ret >= 0:
                ret = av_opt_set_int(filt_asink, "all_channel_counts", 1, AV_OPT_SEARCH_CHILDREN)
            if ret >= 0 and force_output_format:
                channel_layouts[0] = self.audio_tgt.channel_layout
                channels       [0] = self.audio_tgt.channels
                sample_rates   [0] = self.audio_tgt.freq
                ret = av_opt_set_int(filt_asink, "all_channel_counts", 0, AV_OPT_SEARCH_CHILDREN)
                if ret >= 0:
                    ret = av_opt_set_int_list(filt_asink, "channel_layouts", channel_layouts, sizeof(channel_layouts[0]),
                                              -1, AV_OPT_SEARCH_CHILDREN)
                if ret >= 0:
                    ret = av_opt_set_int_list(filt_asink, "channel_counts", channels, sizeof(channels[0]),
                                              -1, AV_OPT_SEARCH_CHILDREN)
                if ret >= 0:
                    ret = av_opt_set_int_list(filt_asink, "sample_rates", sample_rates, sizeof(sample_rates[0]),
                                              -1, AV_OPT_SEARCH_CHILDREN)
            if ret >= 0:
                ret = self.configure_filtergraph(self.agraph, afilters, filt_asrc, filt_asink)
            if ret >= 0:
                self.in_audio_filter  = filt_asrc
                self.out_audio_filter = filt_asink
            if ret < 0:
                avfilter_graph_free(&self.agraph)
            return ret

    cdef int video_thread(VideoState self) nogil except 1:
        cdef AVPacket pkt
        cdef AVFrame *frame = av_frame_alloc()
        cdef double pts, duration
        cdef int ret
        cdef int serial = 0
        cdef AVRational tb = self.video_st.time_base
        cdef AVRational tb_temp
        cdef AVRational frame_rate = av_guess_frame_rate(self.ic, self.video_st, NULL)
        cdef char errbuf[256]
        cdef char *errbuf_ptr = errbuf
        cdef AVPixelFormat last_out_fmt = self.vid_sink._get_out_pix_fmt()
        IF CONFIG_AVFILTER:
            cdef AVFilterGraph *graph = avfilter_graph_alloc()
            cdef AVFilterContext *filt_out = NULL
            cdef AVFilterContext *filt_in = NULL
            cdef int last_w = 0
            cdef int last_h = 0
            cdef int last_scr_h = 0, last_scr_w = 0
            cdef AVPixelFormat last_format = <AVPixelFormat>-2
            cdef AVPixelFormat last_out_fmt_temp
            cdef int last_serial = -1
        memset(&pkt, 0, sizeof(pkt))

        while 1:
            while self.paused and not self.videoq.abort_request:
                self.mt_gen.delay(10)

            avcodec_get_frame_defaults(frame)
            av_free_packet(&pkt)
            ret = self.get_video_frame(frame, &pkt, &serial)
            if ret < 0:
                break
            if not ret:
                continue

            IF CONFIG_AVFILTER:
                last_out_fmt_temp = self.vid_sink._get_out_pix_fmt()
                if (last_w != frame.width or last_h != frame.height
                    or last_scr_h != self.player.screen_height
                    or last_scr_w != self.player.screen_width
                    or last_format != frame.format or last_serial != serial
                    or last_out_fmt != last_out_fmt_temp):
                    av_log(NULL, AV_LOG_DEBUG,
                           "Video frame changed from size:%dx%d format:%s serial:%d to size:%dx%d format:%s serial:%d\n",
                           last_w, last_h,
                           <const char *>av_x_if_null(av_get_pix_fmt_name(last_format), "none"), last_serial,
                           frame.width, frame.height,
                           <const char *>av_x_if_null(av_get_pix_fmt_name(<AVPixelFormat>frame.format), "none"), serial)
                    avfilter_graph_free(&graph)
                    graph = avfilter_graph_alloc()
                    ret = self.configure_video_filters(graph, self.player.vfilters, frame, last_out_fmt_temp)
                    if ret < 0:
                        if av_strerror(ret, errbuf, sizeof(errbuf)) < 0:
                            errbuf_ptr = strerror(AVUNERROR(ret))
                        av_log(NULL, AV_LOG_FATAL, "%s\n", errbuf_ptr)
                        self.vid_sink.request_thread(FF_QUIT_EVENT)
                        av_free_packet(&pkt)
                        break
                    filt_in  = self.in_video_filter
                    filt_out = self.out_video_filter
                    last_w = frame.width
                    last_h = frame.height
                    last_scr_h = self.player.screen_height
                    last_scr_w = self.player.screen_width
                    last_format = <AVPixelFormat>frame.format
                    last_out_fmt = last_out_fmt_temp
                    last_serial = serial
                    frame_rate = filt_out.inputs[0].frame_rate
                    with gil:
                        self.metadata['src_vid_size'] = (last_w, last_h)
                        self.metadata['frame_rate'] = (frame_rate.num, frame_rate.den)
                ret = av_buffersrc_add_frame(filt_in, frame)
                if ret < 0:
                    break
                av_frame_unref(frame)
                avcodec_get_frame_defaults(frame)
                av_free_packet(&pkt)
                while ret >= 0:
                    self.frame_last_returned_time = av_gettime() / 1000000.0
                    ret = av_buffersink_get_frame_flags(filt_out, frame, 0)
                    if ret < 0:
                        if ret == AVERROR_EOF:
                            self.video_finished = serial
                        ret = 0
                        break

                    self.frame_last_filter_delay = av_gettime() / 1000000.0 - self.frame_last_returned_time
                    if fabs(self.frame_last_filter_delay) > AV_NOSYNC_THRESHOLD / 10.0:
                        self.frame_last_filter_delay = 0

                    tb = filt_out.inputs[0].time_base
                    duration = 0
                    if frame_rate.num and frame_rate.den:
                        tb_temp.num = frame_rate.den
                        tb_temp.den = frame_rate.num
                        duration = av_q2d(tb_temp)
                    if frame.pts == AV_NOPTS_VALUE:
                        pts = NAN
                    else:
                        pts = frame.pts * av_q2d(tb)
                    ret = self.queue_picture(frame, pts, duration, av_frame_get_pkt_pos(frame),
                                             serial, last_out_fmt)
                    #av_frame_unref(frame)
            ELSE:
                duration = 0
                if frame_rate.num and frame_rate.den:
                    tb_temp.num = frame_rate.den
                    tb_temp.den = frame_rate.num
                    duration = av_q2d(tb_temp)
                if frame.pts == AV_NOPTS_VALUE:
                    pts = NAN
                else:
                    pts = frame.pts * av_q2d(tb)
                with gil:
                    self.metadata['src_vid_size'] = (frame.width, frame.height)
                    self.metadata['frame_rate'] = (frame_rate.num, frame_rate.den)
                ret = self.queue_picture(frame, pts, duration, av_frame_get_pkt_pos(frame),
                                         serial, last_out_fmt)
                #av_frame_unref(frame)

            if ret < 0:
                break
        avcodec_flush_buffers(self.video_st.codec)
        IF CONFIG_AVFILTER:
            avfilter_graph_free(&graph)
        av_free_packet(&pkt)
        av_frame_free(&frame)
        return 0


    cdef int subtitle_thread(VideoState self) nogil except 1:
        cdef SubPicture *sp
        cdef AVPacket pkt1
        cdef AVPacket *pkt = &pkt1
        cdef int got_subtitle
        cdef int serial
        cdef double pts
        cdef int i, j
        cdef int r, g, b, y, u, v, a

        while 1:
            while self.paused and not self.subtitleq.abort_request:
                self.mt_gen.delay(10)
            if self.subtitleq.packet_queue_get(pkt, 1, &serial) < 0:
                break

            if pkt.data == get_flush_packet().data:
                avcodec_flush_buffers(self.subtitle_st.codec)
                continue
            self.subpq_cond.lock()
            while self.subpq_size >= SUBPICTURE_QUEUE_SIZE and not self.subtitleq.abort_request:
                self.subpq_cond.cond_wait()
            self.subpq_cond.unlock()

            if self.subtitleq.abort_request:
                return 0

            sp = &self.subpq[self.subpq_windex]

            ''' NOTE: ipts is the PTS of the _first_ picture beginning in
            this packet, if any '''
            pts = 0
            if pkt.pts != AV_NOPTS_VALUE:
                pts = av_q2d(self.subtitle_st.time_base) * pkt.pts

            avcodec_decode_subtitle2(self.subtitle_st.codec, &sp.sub, &got_subtitle, pkt)
#             if got_subtitle and sp.sub.format == 0:
#                 if sp.sub.pts != AV_NOPTS_VALUE:
#                     pts = sp.sub.pts / <double>AV_TIME_BASE
#                 sp.pts = pts
#                 sp.serial = serial
#
# #                 for i in range(sp.sub.num_rects):
# #                     for j in range(sp.sub.rects[i].nb_colors):
# #                         sp.sub.rects[i]
#
#                 # now we can update the picture count
#                 self.subpq_windex += 1
#                 if self.subpq_windex == SUBPICTURE_QUEUE_SIZE:
#                     self.subpq_windex = 0
#                 self.subpq_cond.lock()
#                 self.subpq_size += 1
#                 self.subpq_cond.unlock()
            if got_subtitle:
                if sp.sub.format != 0:
                    self.vid_sink.subtitle_display(&sp.sub)
                avsubtitle_free(&sp.sub)
            av_free_packet(pkt)
        return 0


    # copy samples for viewing in editor window
    cdef int update_sample_display(VideoState self, int16_t *samples, int samples_size) nogil except 1:
        cdef int size, len

        size = samples_size / sizeof(short)
        while size > 0:
            len = SAMPLE_ARRAY_SIZE - self.sample_array_index
            if len > size:
                len = size
            memcpy(&self.sample_array[self.sample_array_index], samples, len * sizeof(short))
            samples += len
            self.sample_array_index += len
            if self.sample_array_index >= SAMPLE_ARRAY_SIZE:
                self.sample_array_index = 0
            size -= len
        return 0

    ''' return the wanted number of samples to get better sync if sync_type is video
    or external master clock '''
    cdef int synchronize_audio(VideoState self, int nb_samples) nogil except -1:
        cdef int wanted_nb_samples = nb_samples
        cdef double diff, avg_diff
        cdef int min_nb_samples, max_nb_samples

        # if not master, then we try to remove or add samples to correct the clock
        if self.get_master_sync_type() != AV_SYNC_AUDIO_MASTER:
            diff = self.audclk.get_clock() - self.get_master_clock()

            if (not isnan(diff)) and fabs(diff) < AV_NOSYNC_THRESHOLD:
                self.audio_diff_cum = diff + self.audio_diff_avg_coef * self.audio_diff_cum
                if self.audio_diff_avg_count < AUDIO_DIFF_AVG_NB:
                    # not enough measures to have a correct estimate
                    self.audio_diff_avg_count += 1
                else:
                    # estimate the A-V difference
                    avg_diff = self.audio_diff_cum * (1.0 - self.audio_diff_avg_coef)
                    if fabs(avg_diff) >= self.audio_diff_threshold:
                        wanted_nb_samples = nb_samples + <int>(diff * self.audio_src.freq)
                        min_nb_samples = nb_samples * (100 - SAMPLE_CORRECTION_PERCENT_MAX) / 100
                        max_nb_samples = nb_samples * (100 + SAMPLE_CORRECTION_PERCENT_MAX) / 100
                        wanted_nb_samples = FFMIN(FFMAX(wanted_nb_samples, min_nb_samples), max_nb_samples)
#                     av_dlog(NULL, "diff=%f adiff=%f sample_diff=%d apts=%0.3f %f\n",
#                             diff, avg_diff, wanted_nb_samples - nb_samples,
#                             self.audio_clock, self.audio_diff_threshold)
            else:
                ''' too big difference : may be initial PTS errors, so
                   reset A-V filter '''
                self.audio_diff_avg_count = 0
                self.audio_diff_cum       = 0
        return wanted_nb_samples


    '''
       Decode one audio frame and return its uncompressed size.

       The processed audio frame is decoded, converted if required, and
       stored in is->audio_buf, with size in bytes given by the return
       value.
    '''
    cdef int audio_decode_frame(VideoState self) nogil except? 1:
        cdef AVPacket *pkt_temp = &self.audio_pkt_temp
        cdef AVPacket *pkt = &self.audio_pkt
        cdef AVCodecContext *dec = self.audio_st.codec
        cdef int len1, data_size, resampled_data_size
        cdef int64_t dec_channel_layout
        cdef int got_frame
        cdef double audio_clock0
        cdef int wanted_nb_samples
        cdef AVRational tb, tb2
        cdef int ret
        cdef int reconfigure
        cdef char buf1[1024]
        cdef char buf2[1024]

        cdef const uint8_t **input
        cdef uint8_t **out
        cdef int out_count
        cdef int out_size
        cdef int len2

        while 1:
            # NOTE: the audio packet can contain several frames
            while pkt_temp.stream_index != -1 or self.audio_buf_frames_pending:
                if self.frame == NULL:
                    self.frame = av_frame_alloc()
                    if self.frame == NULL:
                        return AVERROR(ENOMEM)
                else:
                    av_frame_unref(self.frame)
                    avcodec_get_frame_defaults(self.frame)

                if self.audioq.serial != self.audio_pkt_temp_serial:
                    break

                if self.paused:
                    return -1

                if not self.audio_buf_frames_pending:
                    len1 = avcodec_decode_audio4(dec, self.frame, &got_frame, pkt_temp)
                    if len1 < 0:
                        # if error, we skip the frame
                        pkt_temp.size = 0
                        break

                    pkt_temp.dts = pkt_temp.pts = AV_NOPTS_VALUE
                    pkt_temp.data += len1
                    pkt_temp.size -= len1
                    if pkt_temp.data != NULL and pkt_temp.size <= 0 or\
                    pkt_temp.data == NULL and not got_frame:
                        pkt_temp.stream_index = -1
                    if pkt_temp.data == NULL and not got_frame:
                        self.audio_finished = self.audio_pkt_temp_serial
                    if not got_frame:
                        continue

                    tb.num = 1
                    tb.den = self.frame.sample_rate
                    if self.frame.pts != AV_NOPTS_VALUE:
                        self.frame.pts = av_rescale_q(self.frame.pts, dec.time_base, tb)
                    elif self.frame.pkt_pts != AV_NOPTS_VALUE:
                        self.frame.pts = av_rescale_q(self.frame.pkt_pts, self.audio_st.time_base, tb)
                    elif self.audio_frame_next_pts != AV_NOPTS_VALUE:
                        tb2.num = 1
                        IF CONFIG_AVFILTER:
                            tb2.den = self.audio_filter_src.freq
                            self.frame.pts = av_rescale_q(self.audio_frame_next_pts, tb2, tb)
                        ELSE:
                            tb2.den = self.audio_src.freq
                            self.frame.pts = av_rescale_q(self.audio_frame_next_pts, tb2, tb)

                    if self.frame.pts != AV_NOPTS_VALUE:
                        self.audio_frame_next_pts = self.frame.pts + self.frame.nb_samples

                    IF CONFIG_AVFILTER:
                        dec_channel_layout = get_valid_channel_layout(self.frame.channel_layout,
                                                                      av_frame_get_channels(self.frame))
                        reconfigure = cmp_audio_fmts(self.audio_filter_src.fmt, self.audio_filter_src.channels,\
                        <AVSampleFormat>self.frame.format, av_frame_get_channels(self.frame)) != 0 or\
                        self.audio_filter_src.channel_layout != dec_channel_layout or\
                        self.audio_filter_src.freq           != self.frame.sample_rate or\
                        self.audio_pkt_temp_serial           != self.audio_last_serial

                        if reconfigure:
                            av_get_channel_layout_string(buf1, sizeof(buf1), -1, self.audio_filter_src.channel_layout)
                            av_get_channel_layout_string(buf2, sizeof(buf2), -1, dec_channel_layout)
                            av_log(NULL, AV_LOG_DEBUG,
                                   "Audio frame changed from rate:%d ch:%d fmt:%s layout:%s serial:%d to \
                                   rate:%d ch:%d fmt:%s layout:%s serial:%d\n",
                                   self.audio_filter_src.freq, self.audio_filter_src.channels,
                                   av_get_sample_fmt_name(self.audio_filter_src.fmt), buf1,
                                   self.audio_last_serial, self.frame.sample_rate,
                                   av_frame_get_channels(self.frame),
                                   av_get_sample_fmt_name(<AVSampleFormat>self.frame.format), buf2,
                                   self.audio_pkt_temp_serial)

                            self.audio_filter_src.fmt            = <AVSampleFormat>self.frame.format
                            self.audio_filter_src.channels       = av_frame_get_channels(self.frame)
                            self.audio_filter_src.channel_layout = dec_channel_layout
                            self.audio_filter_src.freq           = self.frame.sample_rate
                            self.audio_last_serial               = self.audio_pkt_temp_serial

                            ret = self.configure_audio_filters(self.player.afilters, 1)
                            if ret < 0:
                                return ret

                        ret = av_buffersrc_add_frame(self.in_audio_filter, self.frame)
                        if ret < 0:
                            return ret
                        av_frame_unref(self.frame)
                IF CONFIG_AVFILTER:
                    ret = av_buffersink_get_frame_flags(self.out_audio_filter, self.frame, 0)
                    if ret < 0:
                        if ret == AVERROR(EAGAIN):
                            self.audio_buf_frames_pending = 0
                            continue
                        if ret == AVERROR_EOF:
                            self.audio_finished = self.audio_pkt_temp_serial
                        return ret
                    self.audio_buf_frames_pending = 1
                    tb = self.out_audio_filter.inputs[0].time_base

                data_size = av_samples_get_buffer_size(NULL, av_frame_get_channels(self.frame),
                                                       self.frame.nb_samples, <AVSampleFormat>self.frame.format, 1)

                if self.frame.channel_layout and av_frame_get_channels(self.frame) ==\
                av_get_channel_layout_nb_channels(self.frame.channel_layout):
                    dec_channel_layout = self.frame.channel_layout
                else:
                    dec_channel_layout = av_get_default_channel_layout(av_frame_get_channels(self.frame))
                wanted_nb_samples = self.synchronize_audio(self.frame.nb_samples)

                if (self.frame.format != self.audio_src.fmt or
                    dec_channel_layout != self.audio_src.channel_layout or
                    self.frame.sample_rate != self.audio_src.freq or
                    (wanted_nb_samples != self.frame.nb_samples and self.swr_ctx == NULL)):
                    swr_free(&self.swr_ctx)
                    self.swr_ctx = swr_alloc_set_opts(NULL, self.audio_tgt.channel_layout,
                                                      self.audio_tgt.fmt, self.audio_tgt.freq,
                                                      dec_channel_layout, <AVSampleFormat>self.frame.format,
                                                      self.frame.sample_rate, 0, NULL)
                    if self.swr_ctx == NULL or swr_init(self.swr_ctx) < 0:
                        av_log(NULL, AV_LOG_ERROR, "Cannot create sample rate converter for \
                        conversion of %d Hz %s %d channels to %d Hz %s %d channels!\n",\
                        self.frame.sample_rate, av_get_sample_fmt_name(<AVSampleFormat>self.frame.format),\
                        av_frame_get_channels(self.frame), self.audio_tgt.freq,\
                        av_get_sample_fmt_name(self.audio_tgt.fmt), self.audio_tgt.channels)
                        break
                    self.audio_src.channel_layout = dec_channel_layout
                    self.audio_src.channels = av_frame_get_channels(self.frame)
                    self.audio_src.freq = self.frame.sample_rate
                    self.audio_src.fmt = <AVSampleFormat>self.frame.format

                if self.swr_ctx != NULL:
                    input = <const uint8_t **>self.frame.extended_data
                    out = &self.audio_buf1
                    out_count = <int64_t>wanted_nb_samples * self.audio_tgt.freq / self.frame.sample_rate + 256
                    out_size  = av_samples_get_buffer_size(NULL, self.audio_tgt.channels, out_count, self.audio_tgt.fmt, 0)
                    if out_size < 0:
                        av_log(NULL, AV_LOG_ERROR, "av_samples_get_buffer_size() failed\n")
                        break
                    if wanted_nb_samples != self.frame.nb_samples:
                        if swr_set_compensation(self.swr_ctx, (wanted_nb_samples - self.frame.nb_samples)\
                        * self.audio_tgt.freq / self.frame.sample_rate, wanted_nb_samples *\
                        self.audio_tgt.freq / self.frame.sample_rate) < 0:
                            av_log(NULL, AV_LOG_ERROR, "swr_set_compensation() failed\n")
                            break
                    av_fast_malloc(&self.audio_buf1, &self.audio_buf1_size, out_size)
                    if self.audio_buf1 == NULL:
                        return AVERROR(ENOMEM)
                    len2 = swr_convert(self.swr_ctx, out, out_count, input, self.frame.nb_samples)
                    if len2 < 0:
                        av_log(NULL, AV_LOG_ERROR, "swr_convert() failed\n")
                        break
                    if len2 == out_count:
                        av_log(NULL, AV_LOG_WARNING, "audio buffer is probably too small\n")
                        swr_init(self.swr_ctx)
                    self.audio_buf = self.audio_buf1
                    resampled_data_size = len2 * self.audio_tgt.channels * av_get_bytes_per_sample(self.audio_tgt.fmt)
                else:
                    self.audio_buf = self.frame.data[0]
                    resampled_data_size = data_size

                audio_clock0 = self.audio_clock
                # update the audio clock with the pts
                if self.frame.pts != AV_NOPTS_VALUE:
                    self.audio_clock = self.frame.pts * av_q2d(tb) + <double>self.frame.nb_samples\
                    / <double>self.frame.sample_rate
                else:
                    self.audio_clock = NAN
                self.audio_clock_serial = self.audio_pkt_temp_serial
#                 IF DEBUG:
#                     printf("audio: delay=%0.3f clock=%0.3f clock0=%0.3f\n",
#                            self.audio_clock - self.last_clock,
#                            self.audio_clock, audio_clock0)
#                     self.last_clock = is->audio_clock;
                return resampled_data_size

            # free the current packet
            if pkt.data != NULL:
                av_free_packet(pkt)
            memset(pkt_temp, 0, sizeof(pkt_temp[0]))
            pkt_temp.stream_index = -1
            if self.audioq.abort_request:
                return -1

            if self.audioq.nb_packets == 0:
                self.continue_read_thread.lock()
                self.continue_read_thread.cond_signal()
                self.continue_read_thread.unlock()

            # read next packet
            if self.audioq.packet_queue_get(pkt, 0, &self.audio_pkt_temp_serial) < 0:
                return -1

            if pkt.data == get_flush_packet().data:
                avcodec_flush_buffers(dec)
                self.audio_buf_frames_pending = 0
                self.audio_frame_next_pts = AV_NOPTS_VALUE
                if (self.ic.iformat.flags & (AVFMT_NOBINSEARCH | AVFMT_NOGENSEARCH |\
                AVFMT_NO_BYTE_SEEK)) and self.ic.iformat.read_seek == NULL:
                    self.audio_frame_next_pts = self.audio_st.start_time

            pkt_temp[0] = pkt[0]

    # prepare a new audio buffer
    cdef int sdl_audio_callback(VideoState self, uint8_t *stream, int len) nogil except 1:
        cdef int audio_size, len1
        cdef int bytes_per_sec
        cdef int frame_size = av_samples_get_buffer_size(NULL, self.audio_tgt.channels, 1, self.audio_tgt.fmt, 1)
        self.player.audio_callback_time = av_gettime()
        IF HAS_SDL2:
            memset(stream, 0, len)
        while len > 0:
            if self.audio_buf_index >= self.audio_buf_size:
                audio_size = self.audio_decode_frame()
                if audio_size < 0:
                    # if error, just output silence
                    self.audio_buf = self.silence_buf
                    self.audio_buf_size = sizeof(self.silence_buf) / frame_size * frame_size
                else:
#                     if self.show_mode != SHOW_MODE_VIDEO:
#                         self.update_sample_display(<int16_t *>self.audio_buf, audio_size)
                    self.audio_buf_size = audio_size
                self.audio_buf_index = 0
            len1 = self.audio_buf_size - self.audio_buf_index
            if len1 > len:
                len1 = len
            #SDL_MixAudio(stream, <uint8_t *>self.audio_buf + self.audio_buf_index, len1, self.player.volume)
            memcpy(stream, <uint8_t *>self.audio_buf + self.audio_buf_index, len1)
            len -= len1
            stream += len1
            self.audio_buf_index += len1
        bytes_per_sec = self.audio_tgt.freq * self.audio_tgt.channels * av_get_bytes_per_sample(self.audio_tgt.fmt)
        self.audio_write_buf_size = self.audio_buf_size - self.audio_buf_index
        # Let's assume the audio driver that is used by SDL has two periods.
        if not isnan(self.audio_clock):
            self.audclk.set_clock_at(self.audio_clock - <double>(2 * self.audio_hw_buf_size\
            + self.audio_write_buf_size) / bytes_per_sec, self.audio_clock_serial,\
            self.player.audio_callback_time / 1000000.0)
            self.extclk.sync_clock_to_slave(self.audclk)
        return 0

    cdef int audio_open(VideoState self, int64_t wanted_channel_layout, int wanted_nb_channels,
                        int wanted_sample_rate, AudioParams *audio_hw_params) nogil except? 1:
        cdef SDL_AudioSpec wanted_spec, spec
        cdef const char *env

        env = SDL_getenv("SDL_AUDIO_CHANNELS")
        if env != NULL:
            wanted_nb_channels = atoi(env)
            wanted_channel_layout = av_get_default_channel_layout(wanted_nb_channels)
        if ((not wanted_channel_layout) or wanted_nb_channels !=
            av_get_channel_layout_nb_channels(wanted_channel_layout)):
            wanted_channel_layout = av_get_default_channel_layout(wanted_nb_channels)
            wanted_channel_layout &= ~AV_CH_LAYOUT_STEREO_DOWNMIX
        wanted_spec.channels = av_get_channel_layout_nb_channels(wanted_channel_layout)
        wanted_spec.freq = wanted_sample_rate
        if wanted_spec.freq <= 0 or wanted_spec.channels <= 0:
            av_log(NULL, AV_LOG_ERROR, "Invalid sample rate or channel count!\n")
            return -1
        wanted_spec.format = AUDIO_S16SYS
        wanted_spec.silence = 0
        wanted_spec.samples = SDL_AUDIO_BUFFER_SIZE
        wanted_spec.callback = <void (*)(void *, uint8_t *, int)>self.sdl_audio_callback
        wanted_spec.userdata = self.self_id
        while SDL_OpenAudio(&wanted_spec, &spec) < 0:
            av_log(NULL, AV_LOG_WARNING, "SDL_OpenAudio (%d channels): %s\n",
                   wanted_spec.channels, SDL_GetError())
            wanted_spec.channels = next_nb_channels[FFMIN(7, wanted_spec.channels)]
            if not wanted_spec.channels:
                av_log(NULL, AV_LOG_ERROR,
                       "No more channel combinations to try, audio open failed\n")
                return -1
            wanted_channel_layout = av_get_default_channel_layout(wanted_spec.channels)
        if spec.format != AUDIO_S16SYS:
            av_log(NULL, AV_LOG_ERROR,
                   "SDL advised audio format %d is not supported!\n", spec.format)
            return -1
        if spec.channels != wanted_spec.channels:
            wanted_channel_layout = av_get_default_channel_layout(spec.channels)
            if not wanted_channel_layout:
                av_log(NULL, AV_LOG_ERROR,
                       "SDL advised channel count %d is not supported!\n", spec.channels)
                return -1

        audio_hw_params.fmt = AV_SAMPLE_FMT_S16
        audio_hw_params.freq = spec.freq
        audio_hw_params.channel_layout = wanted_channel_layout
        audio_hw_params.channels =  spec.channels
        return spec.size


    # open a given stream. Return 0 if OK
    cdef int stream_component_open(VideoState self, int stream_index) nogil except 1:
        cdef AVFormatContext *ic = self.ic
        cdef AVCodecContext *avctx
        cdef AVCodec *codec
        cdef const char *forced_codec_name = NULL
        cdef AVDictionary *opts
        cdef AVDictionaryEntry *t = NULL
        cdef int sample_rate, nb_channels
        cdef int64_t channel_layout
        cdef int ret
        cdef int stream_lowres = self.player.lowres
        cdef AVFilterLink *link
        if stream_index < 0 or stream_index >= ic.nb_streams:
            return -1
        avctx = ic.streams[stream_index].codec
        codec = avcodec_find_decoder(avctx.codec_id)

        if avctx.codec_type == AVMEDIA_TYPE_AUDIO:
            self.last_audio_stream = stream_index
            forced_codec_name = self.player.audio_codec_name
        elif avctx.codec_type == AVMEDIA_TYPE_SUBTITLE:
            self.last_subtitle_stream = stream_index
            forced_codec_name = self.player.subtitle_codec_name
        elif avctx.codec_type == AVMEDIA_TYPE_VIDEO:
            self.last_video_stream = stream_index
            forced_codec_name = self.player.video_codec_name

        if forced_codec_name != NULL:
            codec = avcodec_find_decoder_by_name(forced_codec_name)
        if codec == NULL:
            if forced_codec_name != NULL:
                av_log(NULL, AV_LOG_WARNING, "No codec could be found with name '%s'\n", forced_codec_name)
            else:
                av_log(NULL, AV_LOG_WARNING, "No codec could be found with id %d\n", avctx.codec_id)
            return -1
        avctx.codec_id = codec.id
        avctx.workaround_bugs = self.player.workaround_bugs
        if stream_lowres > av_codec_get_max_lowres(codec):
            av_log(avctx, AV_LOG_WARNING, "The maximum value for lowres supported by the decoder is %d\n",
                    av_codec_get_max_lowres(codec))
            stream_lowres = av_codec_get_max_lowres(codec)
        av_codec_set_lowres(avctx, stream_lowres)
        avctx.error_concealment = self.player.error_concealment

        if stream_lowres:
            avctx.flags |= CODEC_FLAG_EMU_EDGE
        if self.player.fast:
            avctx.flags2 |= CODEC_FLAG2_FAST
        if codec.capabilities & CODEC_CAP_DR1:
            avctx.flags |= CODEC_FLAG_EMU_EDGE

        opts = filter_codec_opts(self.player.codec_opts, avctx.codec_id, ic,
                                 ic.streams[stream_index], codec)
        if av_dict_get(opts, "threads", NULL, 0) == NULL:
            av_dict_set(&opts, "threads", "auto", 0)
        if stream_lowres:
            av_dict_set(&opts, "lowres", av_asprintf("%d", stream_lowres), AV_DICT_DONT_STRDUP_VAL)
        if avctx.codec_type == AVMEDIA_TYPE_VIDEO or avctx.codec_type == AVMEDIA_TYPE_AUDIO:
            av_dict_set(&opts, "refcounted_frames", "1", 0)
        if avcodec_open2(avctx, codec, &opts) < 0:
            return -1
        t = av_dict_get(opts, "", NULL, AV_DICT_IGNORE_SUFFIX)
        if t != NULL:
            av_log(NULL, AV_LOG_ERROR, "Option %s not found.\n", t.key)
            return AVERROR_OPTION_NOT_FOUND
        ic.streams[stream_index].discard = AVDISCARD_DEFAULT
        if avctx.codec_type == AVMEDIA_TYPE_AUDIO:
            IF CONFIG_AVFILTER:
                self.audio_filter_src.freq           = avctx.sample_rate
                self.audio_filter_src.channels       = avctx.channels
                self.audio_filter_src.channel_layout = get_valid_channel_layout(avctx.channel_layout, avctx.channels)
                self.audio_filter_src.fmt            = avctx.sample_fmt
                ret = self.configure_audio_filters(self.player.afilters, 0)
                if ret < 0:
                    return ret
                link = self.out_audio_filter.inputs[0]
                sample_rate    = link.sample_rate
                nb_channels    = link.channels
                channel_layout = link.channel_layout
            ELSE:
                sample_rate    = avctx.sample_rate
                nb_channels    = avctx.channels
                channel_layout = avctx.channel_layout

            # prepare audio output
            ret = self.audio_open(channel_layout, nb_channels, sample_rate, &self.audio_tgt)
            if ret < 0:
                return ret
            self.audio_hw_buf_size = ret
            self.audio_src = self.audio_tgt
            self.audio_buf_size  = 0
            self.audio_buf_index = 0

            # init averaging filter
            self.audio_diff_avg_coef  = exp(log(0.01) / <double>AUDIO_DIFF_AVG_NB)
            self.audio_diff_avg_count = 0
            ''' since we do not have a precise anough audio fifo fullness,
            we correct audio sync only if larger than this threshold '''
            self.audio_diff_threshold = 2.0 * self.audio_hw_buf_size /\
            <double>av_samples_get_buffer_size(NULL, self.audio_tgt.channels,\
            self.audio_tgt.freq, self.audio_tgt.fmt, 1)

            memset(&self.audio_pkt, 0, sizeof(self.audio_pkt))
            memset(&self.audio_pkt_temp, 0, sizeof(self.audio_pkt_temp))
            self.audio_pkt_temp.stream_index = -1

            self.audio_stream = stream_index
            self.audio_st = ic.streams[stream_index]

            self.audioq.packet_queue_start()
            SDL_PauseAudio(0)
        elif avctx.codec_type ==  AVMEDIA_TYPE_VIDEO:
            with gil:
                self.metadata['src_pix_fmt'] = av_get_pix_fmt_name(avctx.pix_fmt)
            self.video_stream = stream_index
            self.video_st = ic.streams[stream_index]
            self.videoq.packet_queue_start()
            with gil:
                self.video_tid = MTThread(self.mt_gen.mt_src)
                self.video_tid.create_thread(video_thread_enter, self.self_id)
            self.queue_attachments_req = 1
        elif avctx.codec_type ==  AVMEDIA_TYPE_SUBTITLE:
            self.subtitle_stream = stream_index
            self.subtitle_st = ic.streams[stream_index]
            self.subtitleq.packet_queue_start()
            with gil:
                self.subtitle_tid = MTThread(self.mt_gen.mt_src)
                self.subtitle_tid.create_thread(subtitle_thread_enter, self.self_id)
        return 0


    cdef int stream_component_close(VideoState self, int stream_index) nogil except 1:
        cdef AVFormatContext *ic = self.ic
        cdef AVCodecContext *avctx
        if stream_index < 0 or stream_index >= ic.nb_streams:
            return 0
        avctx = ic.streams[stream_index].codec

        if avctx.codec_type == AVMEDIA_TYPE_AUDIO:
            self.audioq.packet_queue_abort()

            SDL_CloseAudio()

            self.audioq.packet_queue_flush()
            av_free_packet(&self.audio_pkt)
            swr_free(&self.swr_ctx)
            av_freep(&self.audio_buf1)
            self.audio_buf1_size = 0
            self.audio_buf = NULL
            av_frame_free(&self.frame)

            IF CONFIG_AVFILTER:
                avfilter_graph_free(&self.agraph)
        elif avctx.codec_type == AVMEDIA_TYPE_VIDEO:
            self.videoq.packet_queue_abort()
            ''' note: we also signal this mutex to make sure we deblock the
            video thread in all cases '''
            self.pictq_cond.lock()
            self.pictq_cond.cond_signal()
            self.pictq_cond.unlock()
            self.video_tid.wait_thread(NULL)
            self.videoq.packet_queue_flush()
        elif avctx.codec_type == AVMEDIA_TYPE_SUBTITLE:
            self.subtitleq.packet_queue_abort()

            ''' note: we also signal this mutex to make sure we deblock the
               video thread in all cases '''
            self.subpq_cond.lock()
            self.subpq_cond.cond_signal()
            self.subpq_cond.unlock()

            self.subtitle_tid.wait_thread(NULL)
            self.subtitleq.packet_queue_flush()

        ic.streams[stream_index].discard = AVDISCARD_ALL
        avcodec_close(avctx)
        if avctx.codec_type == AVMEDIA_TYPE_AUDIO:
            self.audio_st = NULL
            self.audio_stream = -1
        elif avctx.codec_type == AVMEDIA_TYPE_VIDEO:
            self.video_st = NULL
            self.video_stream = -1
        elif avctx.codec_type == AVMEDIA_TYPE_SUBTITLE:
            self.subtitle_st = NULL
            self.subtitle_stream = -1
        return 0

    # this thread gets the stream from the disk or the network
    cdef int read_thread(VideoState self) nogil except 1:
        cdef AVFormatContext *ic = NULL
        cdef int err, i, ret
        cdef int st_index[<int>AVMEDIA_TYPE_NB]
        cdef AVPacket pkt1
        cdef AVPacket *pkt = &pkt1
        cdef int eof = 0
        cdef int64_t stream_start_time
        cdef int pkt_in_play_range = 0
        cdef AVDictionaryEntry *t
        cdef AVDictionary **opts
        cdef int orig_nb_streams
        cdef char errbuf[128]
        cdef const char *errbuf_ptr = errbuf
        cdef int64_t timestamp
        cdef int temp
        cdef int64_t seek_target, seek_min, seek_max
        cdef AVPacket copy
        cdef int64_t temp64, temp64_2
        self.last_video_stream = self.video_stream = -1
        self.last_audio_stream = self.audio_stream = -1
        self.last_subtitle_stream = self.subtitle_stream = -1
        memset(st_index, -1, sizeof(st_index))

        ic = avformat_alloc_context()
        #av_opt_set_int(ic, "threads", 1, 0)
        ic.interrupt_callback.callback = <int (*)(void *)>self.decode_interrupt_cb
        ic.interrupt_callback.opaque = self.self_id
        err = avformat_open_input(&ic, self.player.input_filename, self.iformat, &self.player.format_opts)
        if err < 0:
            if av_strerror(err, errbuf, sizeof(errbuf)) < 0:
                errbuf_ptr = strerror(AVUNERROR(err))
            av_log(NULL, AV_LOG_ERROR, "%s: %s\n", self.player.input_filename, errbuf_ptr)
            return self.failed(-1)
        t = av_dict_get(self.player.format_opts, "", NULL, AV_DICT_IGNORE_SUFFIX)
        if t != NULL:
            av_log(NULL, AV_LOG_ERROR, "Option %s not found.\n", t.key)
            return self.failed(AVERROR_OPTION_NOT_FOUND)
        self.ic = ic

        if self.player.genpts:
            ic.flags |= AVFMT_FLAG_GENPTS
        opts = setup_find_stream_info_opts(ic, self.player.codec_opts)
        orig_nb_streams = ic.nb_streams
        err = avformat_find_stream_info(ic, opts)
        if err < 0:
            av_log(NULL, AV_LOG_WARNING, "%s: could not find codec parameters\n", self.player.input_filename)
            return self.failed(-1)
        for i in range(orig_nb_streams):
            av_dict_free(&opts[i])
        av_freep(&opts)

        if ic.pb != NULL:
            ic.pb.eof_reached = 0 # FIXME hack, ffplay maybe should not use url_feof() to test for the end

        if self.player.seek_by_bytes < 0:
            self.player.seek_by_bytes = (not not ((ic.iformat.flags & AVFMT_TS_DISCONT) != 0))\
            and strcmp("ogg", ic.iformat.name) != 0

        self.max_frame_duration = 10.0 if ic.iformat.flags & AVFMT_TS_DISCONT else 3600.0

        t = av_dict_get(ic.metadata, "title", NULL, 0)
        if t != NULL:
            with gil:
                self.metadata['title'] = str(t.value)
        if ic.duration >= 0:
            with gil:
                self.metadata['duration'] = ic.duration / <double>AV_TIME_BASE

        # if seeking requested, we execute it
        if self.player.start_time != AV_NOPTS_VALUE:
            timestamp = self.player.start_time
            # add the stream start time
            if ic.start_time != AV_NOPTS_VALUE:
                timestamp += ic.start_time
            ret = avformat_seek_file(ic, -1, INT64_MIN, timestamp, INT64_MAX, 0)
            if ret < 0:
                av_log(NULL, AV_LOG_WARNING, "%s: could not seek to position %0.3f\n",
                       self.player.input_filename, <double>timestamp / <double>AV_TIME_BASE)

        self.realtime = is_realtime(ic)
        for i in range(ic.nb_streams):
            ic.streams[i].discard = AVDISCARD_ALL
        if not self.player.video_disable:
            st_index[<int>AVMEDIA_TYPE_VIDEO] = av_find_best_stream(ic, AVMEDIA_TYPE_VIDEO,\
            self.player.wanted_stream[<int>AVMEDIA_TYPE_VIDEO], -1, NULL, 0)
        if not self.player.audio_disable:
            st_index[<int>AVMEDIA_TYPE_AUDIO] = av_find_best_stream(ic, AVMEDIA_TYPE_AUDIO,\
            self.player.wanted_stream[<int>AVMEDIA_TYPE_AUDIO], st_index[<int>AVMEDIA_TYPE_VIDEO], NULL, 0)
        if st_index[<int>AVMEDIA_TYPE_AUDIO] >= 0:
            temp = st_index[<int>AVMEDIA_TYPE_AUDIO]
        else:
            temp = st_index[<int>AVMEDIA_TYPE_VIDEO]
        if (not self.player.video_disable) and not self.player.subtitle_disable:
            st_index[<int>AVMEDIA_TYPE_SUBTITLE] = av_find_best_stream(ic, AVMEDIA_TYPE_SUBTITLE,\
            self.player.wanted_stream[<int>AVMEDIA_TYPE_SUBTITLE], temp, NULL, 0)
        if self.player.show_status:
            av_dump_format(ic, 0, self.player.input_filename, 0)

        # open the streams
        if st_index[<int>AVMEDIA_TYPE_AUDIO] >= 0:
            self.stream_component_open(st_index[<int>AVMEDIA_TYPE_AUDIO])

        ret = -1
        if st_index[<int>AVMEDIA_TYPE_VIDEO] >= 0:
            ret = self.stream_component_open(st_index[<int>AVMEDIA_TYPE_VIDEO])
#         if self.show_mode == SHOW_MODE_NONE:
#             if ret >= 0:
#                 self.show_mode = SHOW_MODE_VIDEO
#             else:
#                 self.show_mode = SHOW_MODE_RDFT

        if st_index[<int>AVMEDIA_TYPE_SUBTITLE] >= 0:
            self.stream_component_open(st_index[<int>AVMEDIA_TYPE_SUBTITLE])

        if self.video_stream < 0 and self.audio_stream < 0:
            av_log(NULL, AV_LOG_FATAL, "Failed to open file '%s' or configure filtergraph\n",
                   self.player.input_filename)
            return self.failed(-1)

        if self.player.infinite_buffer < 0 and self.realtime:
            self.player.infinite_buffer = 1

        while 1:
            if self.abort_request:
                break
            if self.paused != self.last_paused:
                self.last_paused = self.paused
                if self.paused:
                    self.read_pause_return = av_read_pause(ic)
                else:
                    av_read_play(ic)
            IF CONFIG_RTSP_DEMUXER or CONFIG_MMSH_PROTOCOL:
                if self.paused and ((not strcmp(ic.iformat.name, "rtsp")) or\
                ic.pb != NULL and not strncmp(self.player.input_filename, "mmsh:", 5)):
                    # wait 10 ms to avoid trying to get another packet
                    # XXX: horrible
                    self.pause_cond.lock()
                    self.pause_cond.cond_wait()
                    self.pause_cond.unlock()
                    #self.mt_gen.delay(10)
                    continue
            if self.seek_req:
                self.reached_eof = 0
                seek_target = self.seek_pos
                if self.seek_rel > 0:
                    seek_min = seek_target - self.seek_rel + 2
                else:
                    seek_min = INT64_MIN
                if self.seek_rel < 0:
                    seek_max = seek_target - self.seek_rel - 2
                else:
                    seek_max = INT64_MAX
                ''' FIXME the +-2 is due to rounding being not done in the correct
                direction in generation of the seek_pos/seek_rel variables'''

                ret = avformat_seek_file(self.ic, -1, seek_min, seek_target,
                                         seek_max, self.seek_flags)
                if ret < 0:
                    av_log(NULL, AV_LOG_ERROR, "%s: error while seeking\n",
                           self.ic.filename)
                else:
                    if self.audio_stream >= 0:
                        self.audioq.packet_queue_flush()
                        self.audioq.packet_queue_put(get_flush_packet())
                    if self.subtitle_stream >= 0:
                        self.subtitleq.packet_queue_flush()
                        self.subtitleq.packet_queue_put(get_flush_packet())
                    if self.video_stream >= 0:
                        self.videoq.packet_queue_flush()
                        self.videoq.packet_queue_put(get_flush_packet())
                    if self.seek_flags & AVSEEK_FLAG_BYTE:
                        self.extclk.set_clock(NAN, 0)
                    else:
                        self.extclk.set_clock(seek_target / <double>AV_TIME_BASE, 0)
                self.seek_req = 0
                self.queue_attachments_req = 1
                eof = 0
            if self.queue_attachments_req:
                if self.video_st != NULL and self.video_st.disposition & AV_DISPOSITION_ATTACHED_PIC:
                    ret = av_copy_packet(&copy, &self.video_st.attached_pic)
                    if ret < 0:
                        return self.failed(ret)
                    self.videoq.packet_queue_put(&copy)
                    self.videoq.packet_queue_put_nullpacket(self.video_stream)
                self.queue_attachments_req = 0
            # if the queue are full, no need to read more
            if self.player.infinite_buffer < 1 and\
            (self.audioq.size + self.videoq.size + self.subtitleq.size > MAX_QUEUE_SIZE\
            or ((self.audioq.nb_packets > MIN_FRAMES or self.audio_stream < 0 or\
            self.audioq.abort_request) and (self.videoq.nb_packets > MIN_FRAMES or\
            self.video_stream < 0 or self.videoq.abort_request\
            or (self.video_st.disposition & AV_DISPOSITION_ATTACHED_PIC))\
            and (self.subtitleq.nb_packets > MIN_FRAMES or self.subtitle_stream < 0\
            or self.subtitleq.abort_request))):
                # wait 10 ms
                self.continue_read_thread.lock()
                self.continue_read_thread.cond_wait_timeout(10)
                self.continue_read_thread.unlock()
                continue
            if (not self.paused) and ((not self.audio_st) or\
            self.audio_finished == self.audioq.serial) and (self.video_st == NULL or\
            (self.video_finished == self.videoq.serial and self.pictq_size == 0)):
                if self.player.loop != 1:
                    if self.player.start_time != AV_NOPTS_VALUE:
                        temp64 = self.player.start_time
                    else:
                        temp64 = 0
                    if not self.player.loop:

                        self.stream_seek(temp64, 0, 0, 0)
                    else:
                        self.player.loop = self.player.loop - 1
                        if self.player.loop:
                            self.stream_seek(temp64, 0, 0, 0)
                elif self.player.autoexit:
                    return self.failed(AVERROR_EOF)
                else:
                    if not self.reached_eof:
                        self.reached_eof = 1
                        self.vid_sink.request_thread(FF_EOF_EVENT)
            if eof:
                if self.video_stream >= 0:
                    self.videoq.packet_queue_put_nullpacket(self.video_stream)
                if self.audio_stream >= 0:
                    self.audioq.packet_queue_put_nullpacket(self.audio_stream)
                self.mt_gen.delay(10)
                eof = 0
                continue
            ret = av_read_frame(ic, pkt)
            if ret < 0:
                if ret == AVERROR_EOF or url_feof(ic.pb):
                    eof = 1
                if ic.pb != NULL and ic.pb.error:
                    break
                self.continue_read_thread.lock()
                self.continue_read_thread.cond_wait_timeout(10)
                self.continue_read_thread.unlock()
                continue
            # check if packet is in play range specified by user, then queue, otherwise discard
            stream_start_time = ic.streams[pkt.stream_index].start_time
            if stream_start_time != AV_NOPTS_VALUE:
                temp64 = stream_start_time
            else:
                temp64 = 0
            if self.player.start_time != AV_NOPTS_VALUE:
                temp64_2 = self.player.start_time
            else:
                temp64_2 = 0
            pkt_in_play_range = self.player.duration == AV_NOPTS_VALUE or\
            (pkt.pts - temp64) * av_q2d(ic.streams[pkt.stream_index].time_base) -\
            <double>temp64_2 / 1000000.0 <= (<double>self.player.duration / 1000000.0)
            if pkt.stream_index == self.audio_stream and pkt_in_play_range:
                self.audioq.packet_queue_put(pkt)
            elif (pkt.stream_index == self.video_stream and pkt_in_play_range
                  and not (self.video_st.disposition & AV_DISPOSITION_ATTACHED_PIC)):
                self.videoq.packet_queue_put(pkt)
            elif pkt.stream_index == self.subtitle_stream and pkt_in_play_range:
                self.subtitleq.packet_queue_put(pkt)
            else:
                av_free_packet(pkt)
        # wait until the end
        while not self.abort_request:
            self.mt_gen.delay(100)
        ret = 0
        return self.failed(ret)

    cdef inline int failed(VideoState self, int ret) nogil except 1:
        # close each stream
        if self.audio_stream >= 0:
            self.stream_component_close(self.audio_stream)
        if self.video_stream >= 0:
            self.stream_component_close(self.video_stream)
        if self.subtitle_stream >= 0:
            self.stream_component_close(self.subtitle_stream)
        if self.ic != NULL:
            avformat_close_input(&self.ic)
        if ret != 0:
            self.vid_sink.request_thread(FF_QUIT_EVENT)
        return 0

    cdef int stream_cycle_channel(VideoState self, int codec_type,
                                  int requested_stream) nogil except 1:
        cdef AVFormatContext *ic = self.ic
        cdef int start_index, stream_index
        cdef int old_index, was_closed = 0
        cdef AVStream *st
        cdef AVProgram *p = NULL
        cdef int nb_streams = self.ic.nb_streams
        cdef double pos
        cdef int sync_type = self.get_master_sync_type()

        if codec_type == AVMEDIA_TYPE_VIDEO:
            start_index = self.last_video_stream
            old_index = self.video_stream
        elif codec_type == AVMEDIA_TYPE_AUDIO:
            start_index = self.last_audio_stream
            old_index = self.audio_stream
        else:
            start_index = self.last_subtitle_stream
            old_index = self.subtitle_stream
        was_closed = old_index == -1
        stream_index = start_index
        if codec_type != AVMEDIA_TYPE_VIDEO and self.video_stream != -1:
            p = av_find_program_from_stream(ic, NULL, self.video_stream)
            if p != NULL:
                nb_streams = p.nb_stream_indexes
                start_index = 0
                while start_index < nb_streams:
                    if p.stream_index[start_index] == stream_index:
                        break
                    start_index += 1
                if start_index == nb_streams:
                    start_index = -1
                stream_index = start_index
        while 1:
            if not was_closed:
                stream_index += 1
            if stream_index >= nb_streams:
                if codec_type == AVMEDIA_TYPE_SUBTITLE:
                    stream_index = -1
                    self.last_subtitle_stream = -1
                    break
                if start_index == -1:
                    return 0
                stream_index = 0
            if stream_index == start_index and not was_closed:
                return 0
            st = ic.streams[stream_index]
            if p != NULL:
                st = self.ic.streams[p.stream_index[stream_index]]
            else:
                st = self.ic.streams[stream_index]
            if (requested_stream == -1 or stream_index == requested_stream) and\
            st.codec.codec_type == codec_type:
                # check that parameters are OK
                if codec_type == AVMEDIA_TYPE_AUDIO:
                    if st.codec.sample_rate != 0 and st.codec.channels != 0:
                        break
                elif codec_type == AVMEDIA_TYPE_VIDEO or codec_type == AVMEDIA_TYPE_SUBTITLE:
                    break
        if p != NULL and stream_index != -1:
            stream_index = p.stream_index[stream_index]
        self.stream_component_close(old_index)
        self.stream_component_open(stream_index)
        if was_closed:
            if (sync_type == AV_SYNC_VIDEO_MASTER and
                codec_type != AVMEDIA_TYPE_VIDEO and
                self.video_stream != -1):
                pos = self.vidclk.get_clock()
            elif (sync_type == AV_SYNC_AUDIO_MASTER and
                codec_type != AVMEDIA_TYPE_AUDIO and
                self.audio_stream != -1):
                pos = self.audclk.get_clock()
            else:
                pos = self.extclk.get_clock()
            if isnan(pos):
                pos = <double>self.seek_pos / <double>AV_TIME_BASE
            if self.ic.start_time != AV_NOPTS_VALUE and pos < self.ic.start_time / <double>AV_TIME_BASE:
                pos = self.ic.start_time / <double>AV_TIME_BASE
            self.stream_seek(<int64_t>(pos * AV_TIME_BASE), 0, 0, 1)
        return 0
