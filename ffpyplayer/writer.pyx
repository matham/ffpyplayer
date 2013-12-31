'''
FFmpeg based media writer
=========================

A FFmpeg based python media writer. See :class:`MediaWriter` for details.
Currently writes only video.
'''

__all__ = ('MediaWriter', )


import copy
from tools import get_supported_framerates, get_supported_pixfmts
from tools import loglevels, _initialize_ffmpeg

cdef extern from "string.h" nogil:
    void *memset(void *, int, size_t)
    void *memcpy(void *, const void *, size_t)
    char *strerror(int)

cdef extern from "stdlib.h" nogil:
    void *malloc(size_t)
    void free(void *)

cdef extern from "math.h" nogil:
    double floor(double)

cdef extern from "errno.h" nogil:
    int EDOM
    int ENOENT


DEF VSYNC_PASSTHROUGH = 0
DEF VSYNC_CFR = 1
DEF VSYNC_VFR = 2
DEF VSYNC_DROP = 0xff

cdef inline char * emsg(int code, char *msg, int buff_size) except NULL:
    if av_strerror(code, msg, buff_size) < 0:
        if EDOM > 0:
            code = -code
        return strerror(code)
    return msg
cdef int AV_ENOENT = ENOENT if ENOENT < 0 else -ENOENT


cdef class MediaWriter(object):

    def __cinit__(self, filename, streams, fmt='', lib_opts={}, metadata={},
                  loglevel='error', overwrite=False, **kwargs):
        cdef int res = 0, n = len(streams), r, linesize[4]
        cdef char *format_name = NULL, msg[256]
        cdef MediaStream *s
        cdef list linesizes, frame_sizes
        cdef AVDictionaryEntry *dict_temp = NULL
        cdef AVPicture dummy_pic
        cdef bytes msg2
        cdef const AVCodecDescriptor *codec_desc

        self.format_opts = NULL
        if loglevel not in loglevels:
            raise ValueError('Invalid log level option.')
        av_log_set_flags(AV_LOG_SKIP_REPEATED)
        av_log_set_level(loglevels[loglevel])
        _initialize_ffmpeg()
        memset(msg, 0, sizeof(msg))
        if fmt:
            format_name = fmt
        if not n:
            raise Exception('Streams parameters not provided.')
        conf = [copy.deepcopy(kwargs) for i in streams]
        for r in range(n):
            conf[r].update(streams[r])
        self.config = conf

        self.fmt_ctx = NULL
        res = avformat_alloc_output_context2(&self.fmt_ctx, NULL, format_name, filename)
        if res < 0 or self.fmt_ctx == NULL:
            raise Exception('Failed to create format context: ' + emsg(res, msg, sizeof(msg)))
        self.streams = <MediaStream *>malloc(n * sizeof(MediaStream))
        if self.streams == NULL:
            self.clean_up()
            raise MemoryError()
        s = self.streams
        self.n_streams = n
        memset(s, 0, n * sizeof(MediaStream))
        #self.linesizes = linesizes = [[0, ] * 4 for i in range(n)]
        #self.frame_sizes = frame_sizes = [0, ] * n
        linesizes = [[0, ] * 4 for i in range(n)]
        frame_sizes = [0, ] * n
        if type(lib_opts) is dict:
            lib_opts = [lib_opts, ] * n
        elif len(lib_opts) == 1:
            lib_opts = lib_opts * n

        for r in range(n):
            s[r].codec_opts = NULL
            config = conf[r]
            if 'pix_fmt_out' not in config or not config['pix_fmt_out']:
                config['pix_fmt_out'] = config['pix_fmt_in']
            if 'width_out' not in config or not config['width_out']:
                config['width_out'] = config['width_in']
            if 'height_out' not in config or not config['height_out']:
                config['height_out'] = config['height_in']
            codec_desc = avcodec_descriptor_get_by_name(config['codec'])
            if codec_desc == NULL:
                self.clean_up()
                raise Exception('Codec %s not found.' % config['codec'])
            s[r].codec_id = codec_desc.id
            s[r].width_in = config['width_in']
            s[r].width_out = config['width_out']
            s[r].height_in = config['height_in']
            s[r].height_out = config['height_out']
            s[r].num, s[r].den = config['frame_rate']
            if av_get_pix_fmt(config['pix_fmt_in']) == AV_PIX_FMT_NONE:
                self.clean_up()
                raise Exception('Pixel format %s not found.' % config['pix_fmt_in'])
            if av_get_pix_fmt(config['pix_fmt_out']) == AV_PIX_FMT_NONE:
                self.clean_up()
                raise Exception('Pixel format %s not found.' % config['pix_fmt_out'])
            s[r].pix_fmt_in = av_get_pix_fmt(config['pix_fmt_in'])
            s[r].pix_fmt_out = av_get_pix_fmt(config['pix_fmt_out'])

            s[r].codec = avcodec_find_encoder(s[r].codec_id);
            if s[r].codec == NULL:
                self.clean_up()
                raise Exception('Codec %s not found.' % config['codec'])
            s[r].av_stream = avformat_new_stream(self.fmt_ctx, s[r].codec);
            if s[r].av_stream == NULL:
                self.clean_up()
                raise Exception("Couldn't create stream %d." % r)
            s[r].index = s[r].av_stream.index

            s[r].codec_ctx = s[r].av_stream.codec
            s[r].codec_ctx.width = s[r].width_out
            s[r].codec_ctx.height = s[r].height_out
            supported_rates = get_supported_framerates(config['codec'], (s[r].num, s[r].den))
            if supported_rates and supported_rates[0] != (s[r].num, s[r].den):
                self.clean_up()
                raise Exception('%d/%d is not a supported frame rate for codec %s, the \
                closest valid rate is %d/%d' % (s[r].num, s[r].den, config['codec'],
                                                supported_rates[0][0], supported_rates[0][1]))
            s[r].av_stream.avg_frame_rate.num = s[r].num
            s[r].av_stream.avg_frame_rate.den = s[r].den
            s[r].av_stream.r_frame_rate.num = s[r].num
            s[r].av_stream.r_frame_rate.den = s[r].den
            s[r].codec_ctx.time_base.den = s[r].num
            s[r].codec_ctx.time_base.num = s[r].den
            s[r].codec_ctx.pix_fmt = s[r].pix_fmt_out

            for k, v in metadata.iteritems():
                res = av_dict_set(&s[r].av_stream.metadata, k, v, 0)
                if res < 0:
                    av_dict_free(&s[r].av_stream.metadata)
                    self.clean_up()
                    raise Exception('Failed to set option %s: %s for stream %d; %s'\
                                    % (k, v, r, emsg(res, msg, sizeof(msg))))
            # Some formats want stream headers to be separate
            if self.fmt_ctx.oformat.flags & AVFMT_GLOBALHEADER:
                s[r].codec_ctx.flags |= CODEC_FLAG_GLOBAL_HEADER

            supported_fmts = get_supported_pixfmts(config['codec'], config['pix_fmt_out'])
            if supported_fmts and supported_fmts[0] != config['pix_fmt_out']:
                self.clean_up()
                raise Exception('%s is not a supported pixel format for codec %s, the \
                best valid format is %s' % (config['pix_fmt_out'], config['codec'],
                                            supported_fmts[0]))

            s[r].av_frame = av_frame_alloc()
            if s[r].av_frame == NULL:
                self.clean_up()
                raise MemoryError()
            res = av_image_fill_linesizes(s[r].av_frame.linesize, s[r].pix_fmt_out, s[r].width_out)
            if res < 0:
                self.clean_up()
                raise Exception('Failed to fill linesizes: ' + emsg(res, msg, sizeof(msg)))
            ''' See avpicture_fill, av_image_fill_pointers, avpicture_layout, and avpicture_get_size for how
            different pixfmts are stored in the linear buffer.
            avpicture_fill will be called on the data buffer of each incoming picture so we don't need to allocate
            a buffer for incoming pics, just the frame. '''
            if (s[r].codec_ctx.pix_fmt != s[r].pix_fmt_in or s[r].codec_ctx.width != s[r].width_in or
                s[r].codec_ctx.height != s[r].height_in):
                res = av_image_alloc(s[r].av_frame.data, s[r].av_frame.linesize, s[r].codec_ctx.width,
                                     s[r].codec_ctx.height, s[r].codec_ctx.pix_fmt, 1)
                if res < 0:
                    self.clean_up()
                    raise Exception('Failed to allocate image: ' + emsg(res, msg, sizeof(msg)))

                s[r].av_frame_src = av_frame_alloc()
                if s[r].av_frame_src == NULL:
                    self.clean_up()
                    raise MemoryError()
                # But we still need to know the linesizes of the input image for the conversion.
                res = av_image_fill_linesizes(s[r].av_frame_src.linesize, s[r].pix_fmt_in, s[r].width_in)
                if res < 0:
                    self.clean_up()
                    raise Exception('Failed to fill linesizes: ' + emsg(res, msg, sizeof(msg)))
                s[r].sws_ctx = sws_getCachedContext(NULL, s[r].width_in, s[r].height_in, s[r].pix_fmt_in,\
                s[r].codec_ctx.width, s[r].codec_ctx.height, s[r].codec_ctx.pix_fmt, SWS_BICUBIC, NULL, NULL, NULL)
                if s[r].sws_ctx == NULL:
                    self.clean_up()
                    raise Exception('Cannot find conversion context.')

            for k, v in lib_opts[r].iteritems():
                if opt_default(k, v, s[r].sws_ctx, NULL, &self.format_opts, &s[r].codec_opts) < 0:
                    raise Exception('library option %s: %s not found' % (k, v))

            res = avcodec_open2(s[r].codec_ctx, s[r].codec, &s[r].codec_opts)
            bad_vals = ''
            dict_temp = av_dict_get(s[r].codec_opts, "", dict_temp, AV_DICT_IGNORE_SUFFIX)
            while dict_temp != NULL:
                bad_vals += '%s: %s, ' % (dict_temp.key, dict_temp.value)
                dict_temp = av_dict_get(s[r].codec_opts, "", dict_temp, AV_DICT_IGNORE_SUFFIX)
            av_dict_free(&s[r].codec_opts)
            if bad_vals:
                msg2 = bytes("The following options were not recognized: %s.\n" % bad_vals)
                av_log(NULL, AV_LOG_ERROR, msg2)
            if res < 0:
                self.clean_up()
                raise Exception('Failed to open codec for stream %d; %s' % (r, emsg(res, msg, sizeof(msg))))

            # the required size of the buffer of the input image. includes padding and alignment
            res = avpicture_fill(&dummy_pic, NULL, s[r].pix_fmt_in, s[r].width_in, s[r].height_in)
            frame_sizes[r] = res
            s[r].buff_len = res
            if res >= 0:
                res = av_image_fill_linesizes(linesize, s[r].pix_fmt_in, s[r].width_in)
            if res < 0:
                self.clean_up()
                raise Exception('Failed to fill linesizes: ' + emsg(res, msg, sizeof(msg)))
            linesizes[r][:] = linesize[0], linesize[1], linesize[2], linesize[3]
            s[r].pts = 0
            if self.fmt_ctx.oformat.flags & AVFMT_VARIABLE_FPS:
                if self.fmt_ctx.oformat.flags & AVFMT_NOTIMESTAMPS:
                    s[r].sync_fmt = VSYNC_PASSTHROUGH
                else:
                    s[r].sync_fmt = VSYNC_VFR
            else:
                s[r].sync_fmt = VSYNC_CFR
            config['linesize'] = linesizes[r]
            config['frame_buffer_size'] = frame_sizes[r]

        if not (self.fmt_ctx.oformat.flags & AVFMT_NOFILE):
            res = avio_check(filename, 0)
            if (not res) and not overwrite:
                self.clean_up()
                raise Exception('File %s already exists.' % filename)
            elif res < 0 and res != AV_ENOENT:
                self.clean_up()
                raise Exception('File error: ' + emsg(res, msg, sizeof(msg)))
            res = avio_open2(&self.fmt_ctx.pb, filename, AVIO_FLAG_WRITE, NULL, NULL)
            if res < 0:
                self.clean_up()
                raise Exception('File error: ' + emsg(res, msg, sizeof(msg)))
        res = avformat_write_header(self.fmt_ctx, &self.format_opts)
        bad_vals = ''
        dict_temp = av_dict_get(self.format_opts, "", dict_temp, AV_DICT_IGNORE_SUFFIX)
        while dict_temp != NULL:
            bad_vals += '%s: %s, ' % (dict_temp.key, dict_temp.value)
            dict_temp = av_dict_get(self.format_opts, "", dict_temp, AV_DICT_IGNORE_SUFFIX)
        av_dict_free(&self.format_opts)
        if bad_vals:
            msg2 = bytes("The following options were not recognized: %s.\n" % bad_vals)
            av_log(NULL, AV_LOG_ERROR, msg2)
        if res < 0:
            self.clean_up()
            raise Exception('Error writing header: ' + emsg(res, msg, sizeof(msg)))

    def __init__(self, filename, streams, fmt='', lib_opts={}, metadata={},
                 loglevel='error', overwrite=False, **kwargs):
        pass

    def __dealloc__(self):
        cdef int r, got_pkt, res
        cdef AVPacket pkt

        if self.fmt_ctx == NULL or (not self.n_streams) or self.streams[0].codec_ctx == NULL:
            self.clean_up()
            return
        for r in range(self.n_streams):
            if ((not self.streams[r].count) or
                (self.streams[r].codec_ctx.codec_type == AVMEDIA_TYPE_VIDEO and
                 (self.fmt_ctx.oformat.flags & AVFMT_RAWPICTURE) and
                 self.streams[r].codec_ctx.codec.id == AV_CODEC_ID_RAWVIDEO)):
                continue
            while 1:
                av_init_packet(&pkt)
                pkt.data = NULL
                pkt.size = 0
                # flush
                res = avcodec_encode_video2(self.streams[r].codec_ctx, &pkt, NULL, &got_pkt)
                if res < 0 or not got_pkt:
                    break
                if pkt.pts != AV_NOPTS_VALUE:
                    pkt.pts = av_rescale_q(pkt.pts, self.streams[r].codec_ctx.time_base,
                                           self.streams[r].av_stream.time_base)
                if pkt.dts != AV_NOPTS_VALUE:
                    pkt.dts = av_rescale_q(pkt.dts, self.streams[r].codec_ctx.time_base,
                                           self.streams[r].av_stream.time_base)
                pkt.stream_index = self.streams[r].av_stream.index
                if av_interleaved_write_frame(self.fmt_ctx, &pkt) < 0:
                    break
        av_write_trailer(self.fmt_ctx)
        self.clean_up()

    def write_frame(MediaWriter self, double pts, int stream, bytes buffer=bytes(''),
                   size_t frame_ref=0):
        '''
        Takes a refrence such as one from :meth:`ffpyplayer.player.MediaPlayer.get_frame`.
        '''
        cdef int res = 0, count = 1, i, got_pkt
        cdef AVFrame *frame_in = <AVFrame *>frame_ref, *frame_out
        cdef MediaStream *s
        cdef uint8_t *buff = buffer
        cdef double ipts, dpts
        cdef AVPacket pkt
        cdef char msg[256]
        if stream >= self.n_streams:
            raise Exception('Invalid stream number %d' % stream)
        s = self.streams + stream
        if len(buffer) < s.buff_len and frame_in == NULL:
            raise Exception('Buffer is too small, or frame pointer is invalid.')

        with nogil:
            if s.av_frame_src != NULL:
                frame_out = s.av_frame
                if frame_in == NULL:
                    frame_in = s.av_frame_src
                    avpicture_fill(<AVPicture *>frame_in, buff, s.pix_fmt_in, s.width_in, s.height_in)
                sws_scale(s.sws_ctx, frame_in.data, frame_in.linesize,
                          0, s.height_in, frame_out.data, frame_out.linesize)
            else:
                frame_out = frame_in
                if frame_in == NULL:
                    frame_out = s.av_frame
                    avpicture_fill(<AVPicture *>frame_out, buff, s.pix_fmt_in, s.width_in, s.height_in)

            ipts = pts / av_q2d(s.codec_ctx.time_base)
            if s.sync_fmt != VSYNC_PASSTHROUGH and s.sync_fmt != VSYNC_DROP:
                dpts = ipts - <double>s.pts
                if dpts < -1.1:
                    count = 0
                elif s.sync_fmt == VSYNC_VFR:
                    if dpts <= -0.6:
                        count = 0
                    elif dpts > 0.6:
                        s.pts = <int64_t>floor(dpts + 0.5)
                elif dpts > 1.1:
                    count = <int>floor(dpts + 0.5)
            else:
                s.pts = <int64_t>floor(dpts + 0.5)
            if count <= 0:
                with gil:
                    raise Exception('Received bad timestamp.')

            for i in range(count):
                av_init_packet(&pkt)
                pkt.data = NULL
                pkt.size = 0

                if self.fmt_ctx.oformat.flags & AVFMT_RAWPICTURE and s.codec.id == AV_CODEC_ID_RAWVIDEO:
                    ''' raw pictures are written as AVPicture structure to
                    avoid any copies. We support temporarily the older
                    method. '''
                    s.codec_ctx.coded_frame.interlaced_frame = frame_out.interlaced_frame
                    s.codec_ctx.coded_frame.top_field_first = frame_out.top_field_first
                    pkt.data = <uint8_t *>frame_out
                    pkt.size = sizeof(AVPicture)
                    pkt.pts = av_rescale_q(s.pts, s.codec_ctx.time_base, s.av_stream.time_base)
                    pkt.flags |= AV_PKT_FLAG_KEY
                    pkt.stream_index = s.av_stream.index
                    # will the original data be freed?
                    res = av_interleaved_write_frame(self.fmt_ctx, &pkt)
                    if res < 0:
                        with gil:
                            raise Exception('Error writing frame: ' + emsg(res, msg, sizeof(msg)))
                else:
                    got_pkt = 0
                    if not s.codec_ctx.me_threshold:
                        frame_out.pict_type = AV_PICTURE_TYPE_NONE
                    frame_out.pts = s.pts
                    res = avcodec_encode_video2(s.codec_ctx, &pkt, frame_out, &got_pkt)
                    if res < 0:
                        with gil:
                            raise Exception('Error encoding frame: ' + emsg(res, msg, sizeof(msg)))

                    if got_pkt:
                        if pkt.pts == AV_NOPTS_VALUE and not (s.codec_ctx.codec.capabilities & CODEC_CAP_DELAY):
                            pkt.pts = s.pts
                        if pkt.pts != AV_NOPTS_VALUE:
                            pkt.pts = av_rescale_q(pkt.pts, s.codec_ctx.time_base, s.av_stream.time_base)
                        if pkt.dts != AV_NOPTS_VALUE:
                            pkt.dts = av_rescale_q(pkt.dts, s.codec_ctx.time_base, s.av_stream.time_base)
                        if s.sync_fmt == VSYNC_DROP:
                            pkt.pts = pkt.dts = AV_NOPTS_VALUE
                        pkt.stream_index = s.av_stream.index
                        res = av_interleaved_write_frame(self.fmt_ctx, &pkt)
                        if res < 0:
                            with gil:
                                raise Exception('Error writing frame: ' + emsg(res, msg, sizeof(msg)))

                s.pts += 1
                s.count += 1
        return 0

    def get_configuration(self):
        '''
        Returns the configuration parameters used to initialize the writer.
        '''
        return self.config

    cdef void clean_up(MediaWriter self):
        cdef int r

        for r in range(self.n_streams):
            # If the in and out formats are different we must delete the out frame data buffer
            if self.streams[r].av_frame != NULL:
                if self.streams[r].av_frame_src != NULL and self.streams[r].av_frame.data[0] != NULL:
                    av_freep(&self.streams[r].av_frame.data[0])
                av_frame_free(&self.streams[r].av_frame)
                self.streams[r].av_frame = NULL
            # The temp frames data is only temporary data (supplied by user for each pic), so don't delete it.
            if self.streams[r].av_frame_src != NULL:
                av_frame_free(&self.streams[r].av_frame_src)
                self.streams[r].av_frame_src = NULL
            if self.streams[r].sws_ctx != NULL:
                sws_freeContext(self.streams[r].sws_ctx)
                self.streams[r].sws_ctx= NULL
            if self.streams[r].codec_opts:
                av_dict_free(&self.streams[r].codec_opts)
        free(self.streams)
        self.streams = NULL
        self.n_streams = 0

        if self.fmt_ctx != NULL:
            if self.fmt_ctx.pb != NULL and not (self.fmt_ctx.oformat.flags & AVFMT_NOFILE):
                avio_close(self.fmt_ctx.pb)
            avformat_free_context(self.fmt_ctx)
            self.fmt_ctx = NULL
        av_dict_free(&self.format_opts)

