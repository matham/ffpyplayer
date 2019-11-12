'''
FFmpeg based media writer
=========================

A FFmpeg based python media writer. See :class:`MediaWriter` for details.
Currently writes only video.
'''

__all__ = ('MediaWriter', )

include "includes/inline_funcs.pxi"

cdef extern from "string.h" nogil:
    void *memset(void *, int, size_t)

cdef extern from "stdlib.h" nogil:
    void *malloc(size_t)
    void free(void *)

cdef extern from "math.h" nogil:
    double floor(double)

cdef extern from "errno.h" nogil:
    int ENOENT
    int EAGAIN

from ffpyplayer.pic cimport Image

import ffpyplayer.tools  # required to init ffmpeg
from ffpyplayer.tools import encode_to_bytes, convert_to_str
from copy import deepcopy
from ffpyplayer.tools import get_supported_framerates, get_supported_pixfmts

DEF VSYNC_PASSTHROUGH = 0
DEF VSYNC_CFR = 1
DEF VSYNC_VFR = 2
DEF VSYNC_DROP = 0xff

cdef int AV_ENOENT = ENOENT if ENOENT < 0 else -ENOENT
cdef int AV_EAGAIN = EAGAIN if EAGAIN < 0 else -EAGAIN


cdef class MediaWriter(object):
    '''An FFmpeg based media writer class. Currently only supports video.

    With this class one can write images frames stored in many different pixel
    formats into a multi-stream video file using :meth:`write_frame`. All FFmpeg
    codecs and pixel formats are supported.

    :Parameters:

        `filename`: str
            The filename of the media file to create. Will be encoded using utf8
            berfore passing to FFmpeg.
        `streams`: list of dicts
            A list of streams to create in the file. ``streams``
            is a list of dicts, where each dict configures the corresponding stream.
            The keywords listed below are available. One can also specify default
            values for the keywords for all streams using ``kwargs``. Keywords also
            found in ``streams`` will overwrite those in ``kwargs``:

                `pix_fmt_in`: str
                    The pixel format of the :class:`~ffpyplayer.pic.Image`
                    to be passed to :meth:`write_frame` for this stream. Can be one of
                    :attr:`ffpyplayer.tools.pix_fmts`.
                `width_in`: int
                    The width of the :class:`ffpyplayer.pic.Image` that will be
                    passed to :meth:`write_frame` for this stream.
                `height_in`: int
                    The height of the :class:`ffpyplayer.pic.Image` that will be
                    passed to :meth:`write_frame` for this stream.
                `pix_fmt_out`: str
                    The pixel format in which frames will be
                    written to the file for this stream. Can be one of
                    :attr:`ffpyplayer.tools.pix_fmts`. Defaults to ``pix_fmt_in``
                    if not provided. Not every pixel format is supported for each
                    encoding codec, see :func:`~ffpyplayer.tools.get_supported_pixfmts`
                    for which pixel formats are supported for ``codec``.
                `width_out`: int
                    The width at which frames will be written to the file for this
                    stream. Defaults to ``width_in`` if not provided.
                `height_out`: int
                    The height at which frames will be written to the file for this
                    stream. Defaults to ``height_in`` if not provided.
                `codec`: str
                    The codec used to write the frames to the file. Can be one of
                    the encoding codecs in :attr:`ffpyplayer.tools.codecs_enc`.

                    If not provided, it defaults to the default best codec for the format
                    provided in ``fmt`` or guessed from the ``filename``.
                    See :func:`ffpyplayer.tools.get_format_codecs`
                `frame_rate`: 2-tuple of ints
                    A 2-tuple of ints representing the frame rate to be used when writing
                    the file. The first element is the numerator, while the second is the
                    denuminator of a ratio describing the rate. E.g. (2997, 100) describes
                    29.97 fps.

                    The timestamps of the frames written using :meth:`write_frame` do
                    not necessarily need to be multiples of the frame rate because they might be
                    forced to matching timestamps if required. Not every frame rate is
                    supported for each encoding codec, see
                    :func:`ffpyplayer.tools.get_supported_framerates` for which frame
                    rates are supported for ``codec``.

        `fmt`: str
            The format to use for the output. Can be one of
            :attr:`ffpyplayer.tools.formats_out`. Defaults to empty string.
            If not provided, ``filename`` will be used determine the format,
            otherwise this arg will be used.
        `lib_opts`: dict or list of dicts
            A dictionary of options that will be passed
            to the ffmpeg libraries, codecs, sws, and formats when opening them.
            This accepts most of the options that can be passed to ffmpeg libraries.
            See below for examples. Both the keywords and values must be strings.
            It can be passed a dict in which case it'll be applied to all the streams
            or a list containing a dict for each stream.
        `metadata`: dict or list of dicts
            Metadata that will be written to the streams, if
            supported by the stream. See below for examples. Both the keywords and
            values must be strings. It can be passed a dict in which case it'll be
            applied to all the streams or a list containing a dict for each stream.
            If (these) metadata is not supported, it will silently fail to write them.
        `overwrite`: bool
            Whether we should overwrite an existing file.
            If False, an error will be raised if the file already exists. If True,
            the file will be overwritten if it exists.
        `**kwargs`:
            Accepts default values for all ``streams`` which will be used if these
            keywords are not provided for any stream.

    See :ref:`write-simple` and :ref:`write-h264` for examples.
    '''

    def __cinit__(self, filename, streams, fmt='', lib_opts={}, metadata={},
                  overwrite=False, **kwargs):
        cdef int res = 0, n = len(streams), r
        cdef char *format_name = NULL
        cdef char msg[256]
        cdef MediaStream *s
        cdef AVDictionaryEntry *dict_temp = NULL
        cdef bytes msg2
        cdef const AVCodec *codec_desc

        filename = encode_to_bytes(filename)
        streams = encode_to_bytes(deepcopy(streams))
        if fmt:
            fmt = fmt.encode('utf8')
        lib_opts = encode_to_bytes(deepcopy(lib_opts))
        metadata = encode_to_bytes(deepcopy(metadata))
        kwargs = encode_to_bytes(deepcopy(kwargs))

        self.total_size = 0
        self.closed = 0
        self.format_opts = NULL
        if fmt:
            format_name = fmt
        if not n:
            raise Exception('Streams parameters not provided.')
        conf = [deepcopy(kwargs) for i in streams]
        for r in range(n):
            conf[r].update(streams[r])
        self.config = conf

        self.fmt_ctx = NULL
        res = avformat_alloc_output_context2(&self.fmt_ctx, NULL, format_name, filename)
        if res < 0 or self.fmt_ctx == NULL:
            raise Exception('Failed to create format context: ' + tcode(emsg(res, msg, sizeof(msg))))
        self.streams = <MediaStream *>malloc(n * sizeof(MediaStream))
        if self.streams == NULL:
            self.clean_up()
            raise MemoryError()
        s = self.streams
        self.n_streams = n
        memset(s, 0, n * sizeof(MediaStream))
        if isinstance(lib_opts, dict):
            lib_opts = [lib_opts, ] * n
        elif len(lib_opts) == 1:
            lib_opts = lib_opts * n
        if isinstance(metadata, dict):
            metadata = [metadata, ] * n
        elif len(metadata) == 1:
            metadata = metadata * n

        for r in range(n):
            s[r].codec_opts = NULL
            config = conf[r]
            if 'pix_fmt_out' not in config or not config['pix_fmt_out']:
                config['pix_fmt_out'] = config['pix_fmt_in']
            if 'width_out' not in config or not config['width_out']:
                config['width_out'] = config['width_in']
            if 'height_out' not in config or not config['height_out']:
                config['height_out'] = config['height_in']
            if 'codec' not in config or not config['codec']:
                s[r].codec_id = self.fmt_ctx.oformat.video_codec
                codec_desc = avcodec_find_encoder(s[r].codec_id)
                if codec_desc == NULL:
                    raise Exception('Default codec not found for output file.')
                config['codec'] = codec_desc.name
            else:
                codec_desc = avcodec_find_encoder_by_name(config['codec'])
                if codec_desc == NULL:
                    self.clean_up()
                    raise Exception('Encoder codec %s not available.' % config['codec'])
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

            s[r].codec = avcodec_find_encoder(s[r].codec_id)
            if s[r].codec == NULL:
                self.clean_up()
                raise Exception('Codec %s not found.' % config['codec'])
            s[r].av_stream = avformat_new_stream(self.fmt_ctx, NULL)
            if s[r].av_stream == NULL:
                self.clean_up()
                raise Exception("Couldn't create stream %d." % r)
            s[r].index = s[r].av_stream.index

            s[r].codec_ctx = avcodec_alloc_context3(s[r].codec)
            if s[r].codec_ctx == NULL:
                self.clean_up()
                raise MemoryError("Couldn't create stream %d." % r)

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

            for k, v in metadata[r].items():
                k_b = k.encode('utf8')
                res = av_dict_set(&s[r].av_stream.metadata, k_b, v, 0)
                if res < 0:
                    av_dict_free(&s[r].av_stream.metadata)
                    self.clean_up()
                    raise Exception('Failed to set option %s: %s for stream %d; %s'
                                    % (k, v, r, tcode(emsg(res, msg, sizeof(msg)))))
            # Some formats want stream headers to be separate
            if self.fmt_ctx.oformat.flags & AVFMT_GLOBALHEADER:
                s[r].codec_ctx.flags |= AV_CODEC_FLAG_GLOBAL_HEADER

            supported_fmts = get_supported_pixfmts(config['codec'], config['pix_fmt_out'])
            if supported_fmts and supported_fmts[0] != config['pix_fmt_out'].decode('utf8'):
                self.clean_up()
                raise Exception('%s is not a supported pixel format for codec %s, the '
                'best valid format is %s' % (config['pix_fmt_out'], config['codec'],
                                            supported_fmts[0]))

            if (s[r].codec_ctx.pix_fmt != s[r].pix_fmt_in or s[r].codec_ctx.width != s[r].width_in or
                s[r].codec_ctx.height != s[r].height_in):
                s[r].av_frame = av_frame_alloc()
                if s[r].av_frame == NULL:
                    self.clean_up()
                    raise MemoryError()
                s[r].av_frame.format = s[r].pix_fmt_out
                s[r].av_frame.width = s[r].width_out
                s[r].av_frame.height = s[r].height_out
                if av_frame_get_buffer(s[r].av_frame, 32) < 0:
                    raise Exception('Cannot allocate frame buffers.')

                s[r].sws_ctx = sws_getCachedContext(NULL, s[r].width_in, s[r].height_in,\
                s[r].pix_fmt_in, s[r].codec_ctx.width, s[r].codec_ctx.height,\
                s[r].codec_ctx.pix_fmt, SWS_BICUBIC, NULL, NULL, NULL)
                if s[r].sws_ctx == NULL:
                    self.clean_up()
                    raise Exception('Cannot find conversion context.')

            for k, v in lib_opts[r].items():
                k_b = k.encode('utf8')
                if opt_default(k_b, v, s[r].sws_ctx, NULL, NULL, NULL, &self.format_opts, &s[r].codec_opts) < 0:
                    raise Exception('library option %s: %s not found' % (k, v))

            res = avcodec_open2(s[r].codec_ctx, s[r].codec, &s[r].codec_opts)
            bad_vals = ''
            dict_temp = av_dict_get(s[r].codec_opts, b"", dict_temp, AV_DICT_IGNORE_SUFFIX)
            while dict_temp != NULL:
                bad_vals += '%s: %s, ' % (dict_temp.key, dict_temp.value)
                dict_temp = av_dict_get(s[r].codec_opts, b"", dict_temp, AV_DICT_IGNORE_SUFFIX)
            av_dict_free(&s[r].codec_opts)
            if bad_vals:
                msg2 = ("The following options were not recognized: %s.\n" % bad_vals).encode('utf8')
                av_log(NULL, AV_LOG_ERROR, '%s', msg2)
            if res < 0:
                self.clean_up()
                raise Exception('Failed to open codec for stream %d; %s' % (r, tcode(emsg(res, msg, sizeof(msg)))))

            res = avcodec_parameters_from_context(s[r].av_stream.codecpar, s[r].codec_ctx)
            if res < 0:
                self.clean_up()
                raise Exception('Failed to initialize stream parameters for stream %d; %s' % (r, tcode(emsg(res, msg, sizeof(msg)))))

            s[r].pts = 0
            if self.fmt_ctx.oformat.flags & AVFMT_VARIABLE_FPS:
                if self.fmt_ctx.oformat.flags & AVFMT_NOTIMESTAMPS:
                    s[r].sync_fmt = VSYNC_PASSTHROUGH
                else:
                    s[r].sync_fmt = VSYNC_VFR
            else:
                s[r].sync_fmt = VSYNC_CFR

        if not (self.fmt_ctx.oformat.flags & AVFMT_NOFILE):
            res = avio_check(filename, 0)
            if (not res) and not overwrite:
                self.clean_up()
                raise Exception('File %s already exists.' % filename)
            elif res < 0 and res != AV_ENOENT:
                self.clean_up()
                raise Exception('File error: ' + tcode(emsg(res, msg, sizeof(msg))))
            res = avio_open2(&self.fmt_ctx.pb, filename, AVIO_FLAG_WRITE, NULL, NULL)
            if res < 0:
                self.clean_up()
                raise Exception('File error: ' + tcode(emsg(res, msg, sizeof(msg))))
        res = avformat_write_header(self.fmt_ctx, &self.format_opts)
        bad_vals = ''
        dict_temp = av_dict_get(self.format_opts, b"", dict_temp, AV_DICT_IGNORE_SUFFIX)
        while dict_temp != NULL:
            bad_vals += '%s: %s, ' % (dict_temp.key, dict_temp.value)
            dict_temp = av_dict_get(self.format_opts, "", dict_temp, AV_DICT_IGNORE_SUFFIX)
        av_dict_free(&self.format_opts)
        if bad_vals:
            msg2 = ("The following options were not recognized: %s.\n" % bad_vals).encode('utf8')
            av_log(NULL, AV_LOG_ERROR, '%s', msg2)
        if res < 0:
            self.clean_up()
            raise Exception('Error writing header: ' + tcode(emsg(res, msg, sizeof(msg))))

    def __dealloc__(self):
        self.close()

    cpdef close(self):
        '''Closes the writer and writes any frames cached and not yet written.

        Until called, or until the instance is deleted (and this is implicitly called)
        the file is not fully written.

        .. warning::

            After calling this method, calling any other class method on this instance may
            result in a crash or program corruption.
        '''
        cdef int r, res, wrote = 0
        cdef char msg[256]
        cdef AVPacket pkt
        if self.closed:
            return
        self.closed = 1

        with nogil:
            if self.fmt_ctx == NULL or (not self.n_streams) or self.streams[0].codec_ctx == NULL:
                self.clean_up()
                with gil:
                    return

            for r in range(self.n_streams):
                if not self.streams[r].count:
                    continue
                wrote = 1

                av_init_packet(&pkt)
                pkt.data = NULL
                pkt.size = 0

                # flush
                res = avcodec_send_frame(self.streams[r].codec_ctx, NULL)
                if res < 0:
                    with gil:
                        raise Exception('Error sending NULL frame: ' + tcode(emsg(res, msg, sizeof(msg))))

                while True:
                    res = avcodec_receive_packet(self.streams[r].codec_ctx, &pkt)
                    if res < 0:
                        if res != AVERROR_EOF:
                            with gil:
                                raise Exception('Error getting encoded packet: ' + tcode(emsg(res, msg, sizeof(msg))))
                        break

                    if pkt.pts != AV_NOPTS_VALUE:
                        pkt.pts = av_rescale_q(pkt.pts, self.streams[r].codec_ctx.time_base, self.streams[r].av_stream.time_base)
                    if pkt.dts != AV_NOPTS_VALUE:
                        pkt.dts = av_rescale_q(pkt.dts, self.streams[r].codec_ctx.time_base, self.streams[r].av_stream.time_base)
                    pkt.stream_index = self.streams[r].av_stream.index
                    self.total_size += pkt.size

                    res = av_interleaved_write_frame(self.fmt_ctx, &pkt)
                    if res < 0:
                        with gil:
                            raise Exception('Error writing packet: ' + tcode(emsg(res, msg, sizeof(msg))))
            if wrote:
                av_write_trailer(self.fmt_ctx)
            self.clean_up()

    def write_frame(MediaWriter self, Image img, double pts, int stream=0):
        '''Writes a :class:`ffpyplayer.pic.Image` frame to the specified stream.

        If the input data is different than the frame written to disk in either
        size or pixel format as specified when creating the stream, the frame
        is converted before writing. But the input image must match the size and
        format as that specified when creating this stream.

        :Parameters:

            `img`: :class:`ffpyplayer.pic.Image`
                The :class:`ffpyplayer.pic.Image` instance containing the frame
                to be written to disk.
            `pts`: float
                The timestamp of this frame in video time. E.g. 0.5
                means the frame should be displayed by a player at 0.5 seconds after
                the video started playing. In a sense, the frame rate defines which
                timestamps are valid timestamps. However, this is not always the
                case, so if timestamps are invalid for a particular format, they are
                forced to valid values, if possible.
            `stream`: int
                The stream number to which to write this frame. Defaults to 0.

        :returns:

            (int): The approximate number of bytes written to disk so far for this file.

            .. note::

                This is not the same as the number of bytes passed to this function
                so far, because the encoders cache data before writing to disk.
                So although some frames may have been passed, the return value
                may not represent this.

                An extreme example is where the same frame is passed many times
                to h264; the encoder will only write this frame once when the Writer
                object is closed and encoders are flushed, so this function
                will only return 0.

        See :ref:`examples` for its usage.
        '''
        cdef int res = 0, got_pkt
        cdef int frame_cloned = 0
        cdef AVFrame *frame_in = img.frame
        cdef AVFrame *frame_out
        cdef MediaStream *s
        cdef double ipts, dpts
        cdef int64_t rounded_pts
        cdef AVPacket pkt
        cdef char msg[256]
        if stream >= self.n_streams:
            raise Exception('Invalid stream number %d' % stream)
        s = self.streams + stream
        if (frame_in.width != s.width_in or frame_in.height != s.height_in or
            frame_in.format != <AVPixelFormat>s.pix_fmt_in):
            raise Exception("Input image doesn't match stream specified parameters.")

        with nogil:
            if s.av_frame != NULL:
                frame_out = s.av_frame
                sws_scale(s.sws_ctx, <const uint8_t *const *>frame_in.data, frame_in.linesize,
                          0, frame_in.height, frame_out.data, frame_out.linesize)
            else:
                frame_out = av_frame_clone(frame_in)
                frame_cloned = 1
                if frame_out == NULL:
                    with gil:
                        raise MemoryError

            rounded_pts = <int64_t>floor(pts / av_q2d(s.codec_ctx.time_base) + 0.5)
            frame_out.pict_type = AV_PICTURE_TYPE_NONE
            frame_out.pts = rounded_pts

            av_init_packet(&pkt)
            pkt.data = NULL
            pkt.size = 0

            res = avcodec_send_frame(s.codec_ctx, frame_out)
            if res < 0:
                if frame_cloned:
                    av_frame_free(&frame_out)
                with gil:
                    raise Exception('Error sending frame: ' + tcode(emsg(res, msg, sizeof(msg))))

            while True:
                res = avcodec_receive_packet(s.codec_ctx, &pkt)
                if res < 0:
                    if frame_cloned:
                        av_frame_free(&frame_out)
                    if res != AVERROR_EOF and res != AV_EAGAIN:
                        with gil:
                            raise Exception('Error getting encoded packet: ' + tcode(emsg(res, msg, sizeof(msg))))
                    break

                if pkt.pts != AV_NOPTS_VALUE:
                    pkt.pts = av_rescale_q(pkt.pts, s.codec_ctx.time_base, s.av_stream.time_base)
                if pkt.dts != AV_NOPTS_VALUE:
                    pkt.dts = av_rescale_q(pkt.dts, s.codec_ctx.time_base, s.av_stream.time_base)
                pkt.stream_index = s.av_stream.index
                self.total_size += pkt.size

                res = av_interleaved_write_frame(self.fmt_ctx, &pkt)
                if res < 0:
                    if frame_cloned:
                        av_frame_free(&frame_out)
                    with gil:
                        raise Exception('Error writing packet: ' + tcode(emsg(res, msg, sizeof(msg))))

            s.pts += 1
            s.count += 1
            if frame_cloned:
                av_frame_free(&frame_out)
        return self.total_size

    def get_configuration(self):
        '''Returns the configuration parameters used to initialize all the streams for this
        instance.

        This is not the same as the dicts passed when creating the file because
        this uses the actual parameters used.

        :returns:

            list: List of dicts for each stream.

        For example:

        .. code-block:: python

            from ffpyplayer.writer import MediaWriter

            w, h = 640, 480
            out_opts = {'pix_fmt_in':'rgb24', 'width_in':w, 'height_in':h, 'codec':'rawvideo',
                        'frame_rate':(5, 1)}
            writer = MediaWriter('output.avi', [out_opts] * 2, width_out=w/2, height_out=h/2)

            print writer.get_configuration()
            [{'height_in': 480, 'codec': 'rawvideo', 'width_in': 640, 'frame_rate': (5, 1),
            'pix_fmt_in': 'rgb24', 'width_out': 320, 'height_out': 240, 'pix_fmt_out': 'rgb24'},
            {'height_in': 480, 'codec': 'rawvideo', 'width_in': 640, 'frame_rate': (5, 1),
            'pix_fmt_in': 'rgb24', 'width_out': 320, 'height_out': 240, 'pix_fmt_out': 'rgb24'}]
        '''
        return convert_to_str(deepcopy(self.config))

    cdef void clean_up(MediaWriter self) nogil:
        cdef int r

        for r in range(self.n_streams):
            # If the in and out formats are different we must delete the out frame data buffer
            if self.streams[r].av_frame != NULL:
                av_frame_free(&self.streams[r].av_frame)
                self.streams[r].av_frame = NULL
            if self.streams[r].sws_ctx != NULL:
                sws_freeContext(self.streams[r].sws_ctx)
                self.streams[r].sws_ctx= NULL
            if self.streams[r].codec_opts:
                av_dict_free(&self.streams[r].codec_opts)
            if self.streams[r].codec_ctx:
                avcodec_free_context(&self.streams[r].codec_ctx)
        free(self.streams)
        self.streams = NULL
        self.n_streams = 0

        if self.fmt_ctx != NULL:
            if self.fmt_ctx.pb != NULL and not (self.fmt_ctx.oformat.flags & AVFMT_NOFILE):
                avio_close(self.fmt_ctx.pb)
            avformat_free_context(self.fmt_ctx)
            self.fmt_ctx = NULL
        av_dict_free(&self.format_opts)
        self.total_size = 0

