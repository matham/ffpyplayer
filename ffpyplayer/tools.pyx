'''
FFmpeg tools
============

Module for manipulating and finding information of FFmpeg formats, codecs,
devices, pixel formats and more.
'''

__all__ = (
    'initialize_sdl_aud', 'loglevels', 'codecs_enc', 'codecs_dec', 'pix_fmts',
    'formats_in', 'formats_out', 'set_log_callback', 'get_log_callback',
    'set_loglevel', 'get_loglevel', 'get_codecs', 'get_fmts',
    'get_format_codec',
    'get_supported_framerates', 'get_supported_pixfmts', 'get_best_pix_fmt',
    'emit_library_info',
    'list_dshow_devices', 'encode_to_bytes', 'decode_to_unicode',
    'convert_to_str', 'list_dshow_opts')

include "includes/ffmpeg.pxi"
include "includes/inline_funcs.pxi"

cdef extern from "stdlib.h" nogil:
    void *malloc(size_t)
    void free(void *)

from ffpyplayer.threading cimport Py_MT, MTMutex, get_lib_lockmgr, SDL_MT
import ffpyplayer.threading  # for sdl init
import re
import sys
from functools import partial

cdef int sdl_aud_initialized = 0
def initialize_sdl_aud():
    '''Initializes sdl audio subsystem. Must be called before audio can be used.
    It is automatically called by the modules that use SDL audio.
    '''
    global sdl_aud_initialized
    if sdl_aud_initialized:
        return

    # Try to work around an occasional ALSA buffer underflow issue when the
    # period size is NPOT due to ALSA resampling by forcing the buffer size.
    if not SDL_getenv("SDL_AUDIO_ALSA_SET_BUFFER_SIZE"):
        SDL_setenv("SDL_AUDIO_ALSA_SET_BUFFER_SIZE", "1", 0)

    if SDL_InitSubSystem(SDL_INIT_AUDIO):
        raise ValueError('Could not initialize SDL audio - %s' % SDL_GetError())
    sdl_aud_initialized = 1


cdef int ffmpeg_initialized = 0
def _initialize_ffmpeg():
    '''Initializes ffmpeg libraries. Must be called before anything can be used.
    Called automatically when importing this module.
    '''
    global ffmpeg_initialized
    if not ffmpeg_initialized:
        av_log_set_flags(AV_LOG_SKIP_REPEATED)
        IF CONFIG_AVDEVICE:
            avdevice_register_all()
        avformat_network_init()
        ffmpeg_initialized = 1
_initialize_ffmpeg()


def _get_item0(x):
    return x[0]

'see http://ffmpeg.org/ffmpeg.html for log levels'
loglevels = {
    "quiet": AV_LOG_QUIET, "panic": AV_LOG_PANIC, "fatal": AV_LOG_FATAL,
    "error": AV_LOG_ERROR, "warning": AV_LOG_WARNING, "info": AV_LOG_INFO,
    "verbose": AV_LOG_VERBOSE, "debug": AV_LOG_DEBUG, "trace": AV_LOG_TRACE}
'''A dictionary with all the available ffmpeg log levels. The keys are the loglevels
and the values are their ffmpeg values. The lower the value, the more important
the log. Note, this is ooposite python where the higher the level the more important
the log.
'''
_loglevel_inverse = {v:k for k, v in loglevels.iteritems()}

cdef object _log_callback = None
cdef MTMutex _log_mutex= MTMutex(SDL_MT)
cdef int log_level = AV_LOG_WARNING
cdef int print_prefix = 1

cdef void gil_call_callback(char *line, int level):
    cdef object callback
    callback = _log_callback
    if callback is None:
        return
    callback(tcode(line), _loglevel_inverse[level])

cdef void call_callback(char *line, int level) nogil:
    with gil:
        gil_call_callback(line, level)

cdef void _log_callback_func(void* ptr, int level, const char* fmt, va_list vl) noexcept nogil:
    cdef char line[2048]
    if fmt == NULL or level > log_level:
        return

    av_log_format_line(ptr, level, fmt, vl, line, sizeof(line), &print_prefix)
    call_callback(line, level)

def _logger_callback(logger_dict, message, level):
    message = message.strip()
    if message:
        logger_dict[level]('FFPyPlayer: {}'.format(message))

def set_log_callback(object callback=None, logger=None, int default_only=False):
    '''Sets a callback to be used by ffmpeg when emitting logs.
    This function is thread safe.

    See also :func:`set_loglevel`.

    :Parameters:

        `callback`: callable or None
            A function which will be called with strings to be printed. It takes
            two parameters: ``message`` and ``level``. ``message`` is the string
            to be printed. ``level`` is the log level of the string and is one
            of the keys of the :attr:`loglevels` dict. If ``callback`` and ``logger``
            are None, the default ffmpeg log callback will be set, which prints to stderr.
            Defaults to None.
        `logger`: a python logger object or None
            If ``callback`` is None and this is not None, this logger object's
            ``critical``, ``error``, ``warning``, ``info``, ``debug``, and ``trace``
            methods will be called directly to forward ffmpeg's log outputs.

            .. note::

                If the logger doesn't have a trace method, the trace output will be
                redirected to debug. However, the trace level outputs a lot of logs.

        `default_only`: bool
            If True, when ``callback`` or ``logger`` are not ``None``, they
            will only be set if a callback or logger has not already been set.

    :returns:

        The previous callback set (None, if it has not been set).

    >>> from ffpyplayer.tools import set_log_callback, loglevels
    >>> loglevel_emit = 'error' # This and worse errors will be emitted.
    >>> def log_callback(message, level):
    ...     message = message.strip()
    ...     if message and loglevels[level] <= loglevels[loglevel_emit]:
    ...         print '%s: %s' %(level, message.strip())
    >>> set_log_callback(log_callback)
    ...
    >>> set_log_callback(None)
    '''
    global _log_callback
    if callback is not None and not callable(callback):
        raise Exception('Log callback needs to be callable.')

    if callback is None and logger is not None:
        logger_dict = {
            'quiet': logger.critical, 'panic': logger.critical,
            'fatal': logger.critical, 'error': logger.error, 'warning': logger.warning,
            'info': logger.info, 'verbose': logger.debug, 'debug': logger.debug,
            'trace': getattr(logger, 'trace', logger.debug)}
        callback = partial(_logger_callback, logger_dict)

    _log_mutex.lock()
    old_callback = _log_callback
    if callback is None:
        av_log_set_callback(&av_log_default_callback)
        _log_callback = None
    elif not default_only or old_callback is None:
        av_log_set_callback(&_log_callback_func)
        _log_callback = callback
    _log_mutex.unlock()
    return old_callback

def get_log_callback():
    '''Returns the last log callback set, or None if it has not been set.
    See :func:`set_log_callback`.
    '''
    _log_mutex.lock()
    old_callback = _log_callback
    _log_mutex.unlock()
    return old_callback


def set_loglevel(loglevel):
    '''This sets the global FFmpeg log level. less important log levels are filtered
    and not passsed on to the logger or callback set by :func:`set_log_callback`.
    It also set the loglevel of FFmpeg if not callback or logger is set.

    The global log level, if not set, defaults to ``'warning'``.

    :Parameters:

        `loglevel`: str
            The log level. Can be one of the keys of :attr:`loglevels`.
    '''
    cdef int level
    global log_level
    if loglevel not in loglevels:
        raise ValueError('Invalid loglevel {}'.format(loglevel))
    level = loglevels[loglevel]
    _log_mutex.lock()
    av_log_set_level(level)
    log_level = level
    _log_mutex.unlock()
set_loglevel(_loglevel_inverse[log_level])

def get_loglevel():
    '''Returns the log level set with :func:`set_loglevel`, or the default level if not
    set. It is one of the keys of :attr:`loglevels`.
    '''
    cdef int level
    _log_mutex.lock()
    level = log_level
    _log_mutex.unlock()
    return _loglevel_inverse[level]


cpdef get_codecs(
        int encode=False, int decode=False, int video=False, int audio=False,
        int data=False, int subtitle=False, int attachment=False, other=False):
    '''Returns a list of codecs (e.g. h264) that is available by ffpyplayer for
    encoding or decoding and matches the media types, e.g. video or audio.

    The parameters determine which codecs is included in the result. The parameters
    all default to False.

    :Parameters:

        `encode`: bool
            If True, includes the encoding codecs in the result. Defaults to False.
        `decode`: bool
            If True, includes the decoding codecs in the result. Defaults to False.
        `video`: bool
            If True, includes the video codecs in the result. Defaults to False.
        `audio`: bool
            If True, includes the audio codecs in the result. Defaults to False.
        `data`: bool
            If True, includes the (continuous) side data codecs in the result. Defaults to False.
        `subtitle`: bool
            If True, includes the subtitle codecs in the result. Defaults to False.
        `attachment`: bool
            If True, includes the (sparse) data attachment codecs in the result. Defaults to False.
        `other`: bool
            If True, returns all the codec media types.

    :returns:

        A sorted list of the matching codec names.
    '''
    cdef list codecs = []
    cdef AVCodec *codec = NULL
    cdef void *iter_codec = NULL
    codec = av_codec_iterate(&iter_codec)

    while codec != NULL:
        if ((encode and av_codec_is_encoder(codec) or
             decode and av_codec_is_decoder(codec)) and
            (video and codec.type == AVMEDIA_TYPE_VIDEO or
             audio and codec.type == AVMEDIA_TYPE_AUDIO or
             data and codec.type == AVMEDIA_TYPE_DATA or
             subtitle and codec.type == AVMEDIA_TYPE_SUBTITLE or
             attachment and codec.type == AVMEDIA_TYPE_ATTACHMENT or
             other)):
            codecs.append(tcode(codec.name))
        codec = av_codec_iterate(&iter_codec)
    return sorted(codecs)

codecs_enc = get_codecs(encode=True, video=True)
'''A list of all the codecs available for encoding video. '''
codecs_dec = get_codecs(decode=True, video=True, audio=True)
'''A list of all the codecs available for decoding video and audio. '''

cdef list list_pixfmts():
    cdef list fmts = []
    cdef const AVPixFmtDescriptor *desc = NULL
    desc = av_pix_fmt_desc_next(desc)

    while desc != NULL:
        fmts.append(tcode(desc.name))
        desc = av_pix_fmt_desc_next(desc)
    return sorted(fmts)

pix_fmts = list_pixfmts()
'''A list of all the pixel formats available to ffmpeg. '''

cpdef get_fmts(int input=False, int output=False):
    '''Returns the formats available in FFmpeg.

    :Parameters:

        `input`: bool
            If True, also includes input formats in the result. Defaults to False
        `output`: bool
            If True, also includes output formats in the result. Defaults to False

    :returns:

        A 3-tuple of 3 lists, ``formats``, ``full_names``, and ``extensions``.
        Each of the three lists are of identical length.

        `formats`: list
            A list of the names of the formats.
        `full_names`: list
            A list of the corresponding human readable names for each of the
            formats. Can be the empty string if none is available.
        `extensions`: list
            A list of the extensions associated with the corresponding formats.
            Each item is a (possibly empty) list of extensions names.
    '''
    cdef list fmts = [], full_names = [], exts = []
    cdef AVOutputFormat *ofmt = NULL
    cdef AVInputFormat *ifmt = NULL
    cdef void *ifmt_opaque = NULL
    cdef void *ofmt_opaque = NULL
    cdef object names, full_name, ext

    if output:
        ofmt = av_muxer_iterate(&ofmt_opaque)
        while ofmt != NULL:
            if ofmt.name != NULL:
                names = tcode(ofmt.name).split(',')
                full_name = tcode(ofmt.long_name) if ofmt.long_name != NULL else ''
                ext = tcode(ofmt.extensions).split(',') if ofmt.extensions != NULL else []

                fmts.extend(names)
                full_names.extend([full_name, ] * len(names))
                exts.extend([ext, ] * len(names))
            ofmt = av_muxer_iterate(&ofmt_opaque)

    if input:
        ifmt = av_demuxer_iterate(&ifmt_opaque)
        while ifmt != NULL:
            if ifmt.name != NULL:
                names = tcode(ifmt.name).split(',')
                full_name = tcode(ifmt.long_name) if ifmt.long_name != NULL else ''
                ext = tcode(ifmt.extensions).split(',') if ifmt.extensions != NULL else []

                fmts.extend(names)
                full_names.extend([full_name, ] * len(names))
                exts.extend([ext, ] * len(names))
            ifmt = av_demuxer_iterate(&ifmt_opaque)

    exts = [x for (y, x) in sorted(zip(fmts, exts), key=_get_item0)]
    full_names = [x for (y, x) in sorted(zip(fmts, full_names), key=_get_item0)]
    fmts = sorted(fmts)
    return fmts, full_names, exts

formats_in = get_fmts(input=True)[0]
'''A list of all the formats (e.g. file formats) available for reading. '''
formats_out = get_fmts(output=True)[0]
'''A list of all the formats (e.g. file formats) available for writing. '''

def get_format_codec(filename=None, fmt=None):
    '''Returns the best codec associated with the file format. The format
    can be provided using either ``filename`` or ``fmt``.

    :Parameters:
        `filename`: str or None
            The output filename. If provided, the extension of the filename
            is used to guess the format.
        `fmt`: str or None.
            The format to use. Can be one of :attr:`ffpyplayer.tools.formats_out`.

    :returns:

        str:
            The name from :attr:`ffpyplayer.tools.codecs_enc`
            of the best codec that can be used with this format.

    For example:

    .. code-block:: python

        >>> get_format_codecs('test.png')
        'mjpeg'
        >>> get_format_codecs('test.jpg')
        'mjpeg'
        >>> get_format_codecs('test.mkv')
        'libx264'
        >>> get_format_codecs(fmt='h264')
        'libx264'
    '''
    cdef int res
    cdef char *format_name = NULL
    cdef char *name = NULL
    cdef const AVCodec *codec_desc = NULL
    cdef AVFormatContext *fmt_ctx = NULL
    cdef char msg[256]
    cdef AVCodecID codec_id

    if fmt:
        fmt = fmt.encode('utf8')
        format_name = fmt
    if filename:
        filename = filename.encode('utf8')
        name = filename

    res = avformat_alloc_output_context2(&fmt_ctx, NULL, format_name, name)
    if res < 0 or fmt_ctx == NULL or fmt_ctx.oformat == NULL:
        raise Exception('Failed to find format: ' + tcode(emsg(res, msg, sizeof(msg))))

    codec_id = fmt_ctx.oformat.video_codec
    codec_desc = avcodec_find_encoder(codec_id)
    if codec_desc == NULL:
        raise Exception('Default codec not found for format')
    return tcode(codec_desc.name)


def get_supported_framerates(codec_name, rate=()):
    '''Returns the supported frame rates for encoding codecs. If a desired rate is
    provided, it also returns the closest valid rate.

    :Parameters:

        `codec_name`: str
            The name of a encoding codec.
        `rate`: 2-tuple of ints, or empty tuple.
            If provided, a 2-tuple where the first element is the numerator,
            and the second the denominator of the frame rate we wish to use. E.g.
            (2997, 100) means a frame rate of 29.97.

    :returns:

        (list of 2-tuples, or empty list):
            If there are no restrictions on the frame rate (i.e. all rates are valid)
            it returns a empty list, otherwise it returns a list with the valid
            frame rates. If `rate` is provided and there are restrictions on the frame
            rates, the closest frame rate is the zero'th element in the list.

    For example:

    .. code-block:: python

        >>> print get_supported_framerates('mpeg1video')
        [(24000, 1001), (24, 1), (25, 1), (30000, 1001), (30, 1), (50, 1),
        (60000, 1001), (60, 1), (15, 1), (5, 1), (10, 1), (12, 1), (15, 1)]

        >>> print get_supported_framerates('mpeg1video', (2997, 100))
        [(30000, 1001), (24000, 1001), (24, 1), (25, 1), (30, 1), (50, 1),
        (60000, 1001), (60, 1), (15, 1), (5, 1), (10, 1), (12, 1), (15, 1)]
    '''
    cdef AVRational rate_struct
    cdef list rate_list = []
    cdef int i = 0
    cdef bytes name = codec_name if isinstance(codec_name, bytes) else codec_name.encode('utf8')
    cdef AVCodec *codec = avcodec_find_encoder_by_name(name)
    if codec == NULL:
        raise Exception('Encoder codec %s not available.' % codec_name)
    if codec.supported_framerates == NULL:
        return rate_list

    while codec.supported_framerates[i].den:
        rate_list.append((codec.supported_framerates[i].num, codec.supported_framerates[i].den))
        i += 1
    if rate:
        rate_struct.num, rate_struct.den = rate
        i = av_find_nearest_q_idx(rate_struct, codec.supported_framerates)
        rate = rate_list[i]
        del rate_list[i]
        rate_list.insert(0, rate)
    return rate_list

def get_supported_pixfmts(codec_name, pix_fmt=''):
    '''Returns the supported pixel formats for encoding codecs. If a desired format
    is provided, it also returns the closest format (i.e. the format with minimum
    conversion loss).

    :Parameters:

        `codec_name`: str
            The name of a encoding codec.
        `pix_fmt`: str
            If not empty, the name of a pixel format we wish to use with this codec,
            e.g. 'rgb24'.

    :returns:

        (list of pixel formats, or empty list):
            If there are no restrictions on the pixel formats (i.e. all the formats
            are valid) it returns a empty list, otherwise it returns a list with the
            valid formats. If pix_fmt is not empty and there are restrictions to the
            formats, the closest format which results in the minimum loss when converting
            will be returned as the zero'th element in the list.

    For example:

    .. code-block:: python

        >>> print get_supported_pixfmts('ffv1')
        ['yuv420p', 'yuva420p', 'yuva422p', 'yuv444p', 'yuva444p', 'yuv440p', ...
        'gray16le', 'gray', 'gbrp9le', 'gbrp10le', 'gbrp12le', 'gbrp14le']

        >>> print get_supported_pixfmts('ffv1', 'gray')
        ['gray', 'yuv420p', 'yuva420p', 'yuva422p', 'yuv444p', 'yuva444p', ...
        'gray16le', 'gbrp9le', 'gbrp10le', 'gbrp12le', 'gbrp14le']
    '''
    cdef AVPixelFormat fmt
    cdef bytes name = codec_name if isinstance(codec_name, bytes) else codec_name.encode('utf8')
    cdef bytes fmt_b = pix_fmt if isinstance(pix_fmt, bytes) else pix_fmt.encode('utf8')
    cdef list fmt_list = []
    cdef int i = 0, loss = 0, has_alpha = 0
    cdef AVCodec *codec = avcodec_find_encoder_by_name(name)
    if codec == NULL:
        raise Exception('Encoder codec %s not available.' % codec_name)
    if pix_fmt and av_get_pix_fmt(fmt_b) == AV_PIX_FMT_NONE:
        raise Exception('Pixel format not recognized.')
    if codec.pix_fmts == NULL:
        return fmt_list

    while codec.pix_fmts[i] != AV_PIX_FMT_NONE:
        fmt_list.append(tcode(av_get_pix_fmt_name(codec.pix_fmts[i])))
        i += 1
    if pix_fmt:
        # XXX: fix this to check if NULL (although kinda already checked above)
        has_alpha = av_pix_fmt_desc_get(av_get_pix_fmt(fmt_b)).nb_components % 2 == 0
        fmt = avcodec_find_best_pix_fmt_of_list(codec.pix_fmts, av_get_pix_fmt(fmt_b),
                                                has_alpha, &loss)
        i = fmt_list.index(tcode(av_get_pix_fmt_name(fmt)))
        pix = fmt_list[i]
        del fmt_list[i]
        fmt_list.insert(0, pix)
    return fmt_list

def get_best_pix_fmt(pix_fmt, pix_fmts):
    '''Returns the best pixel format with the least conversion loss from the
    original pixel format, given a list of potential pixel formats.

    :Parameters:

        `pix_fmt`: str
            The name of a original pixel format.
        `pix_fmts`: list-type of strings
            A list of possible pixel formats from which the best will be chosen.

    :returns:

        The pixel format with the least conversion loss.

    .. note::

        The returned pixel format seems to be somewhat sensitive to the order
        of the input pixel formats. Higher quality pixel formats should therefore
        be at the beginning of the list.


    For example:

    .. code-block:: python

        >>> get_best_pix_fmt('yuv420p', ['rgb24', 'rgba', 'yuv444p', 'gray'])
        'rgb24'
        >>> get_best_pix_fmt('gray', ['rgb24', 'rgba', 'yuv444p', 'gray'])
        'gray'
        >>> get_best_pix_fmt('rgb8', ['rgb24', 'yuv420p', 'rgba', 'yuv444p', 'gray'])
        'rgb24'
    '''
    cdef AVPixelFormat fmt, fmt_src
    cdef bytes fmt_src_b = pix_fmt if isinstance(pix_fmt, bytes) else pix_fmt.encode('utf8')
    cdef bytes fmt_b
    cdef int i = 0, loss = 0, has_alpha = 0
    cdef AVPixelFormat *fmts = NULL

    if not pix_fmt or not pix_fmts:
        raise ValueError('Invalid arguments {}, {}'.format(pix_fmt, pix_fmts))
    fmt_src = av_get_pix_fmt(fmt_src_b)
    if fmt_src == AV_PIX_FMT_NONE:
        raise Exception('Pixel format {} not recognized.'.format(pix_fmt))

    fmts = <AVPixelFormat *>malloc(sizeof(AVPixelFormat) * (len(pix_fmts) + 1))
    if fmts == NULL:
        raise MemoryError()

    try:
        fmts[len(pix_fmts)] = AV_PIX_FMT_NONE

        for i, fmt_s in enumerate(pix_fmts):
            fmt_b = fmt_s if isinstance(fmt_s, bytes) else fmt_s.encode('utf8')
            fmts[i] = av_get_pix_fmt(fmt_b)
            if fmts[i] == AV_PIX_FMT_NONE:
                raise Exception('Pixel format {} not recognized.'.format(fmt_s))

        has_alpha = av_pix_fmt_desc_get(fmt_src).nb_components % 2 == 0
        fmt = avcodec_find_best_pix_fmt_of_list(fmts, fmt_src, has_alpha, &loss)
    finally:
        free(fmts)

    return tcode(av_get_pix_fmt_name(fmt))

def emit_library_info():
    '''Prints to the ffmpeg log all the ffmpeg library's versions and configure
    options.
    '''
    print_all_libs_info(INDENT|SHOW_CONFIG,  AV_LOG_INFO)
    print_all_libs_info(INDENT|SHOW_VERSION, AV_LOG_INFO)

def _dshow_log_callback(log, message, level):
    message = message.encode('utf8')

    if not log:
        log.append((message, level))
        return

    last_msg, last_level = log[-1]
    if last_level == level:
        log[-1] = last_msg + message, level
    else:
        log.append((message, level))


cpdef int list_dshow_opts(list log, bytes stream, bytes option) except 1:
    cdef AVFormatContext *fmt = NULL
    cdef AVDictionary* opts = NULL
    cdef AVInputFormat *ifmt
    cdef object old_callback
    cdef int level
    cdef list temp_log = []
    cdef bytes item
    global log_level

    ifmt = av_find_input_format(b"dshow")
    if ifmt == NULL:
        raise Exception('Direct show not found.')

    av_dict_set(&opts, option, b"true", 0)
    _log_mutex.lock()
    old_callback = set_log_callback(partial(_dshow_log_callback, temp_log))
    level = log_level

    av_log_set_level(AV_LOG_TRACE)
    log_level = AV_LOG_TRACE
    avformat_open_input(&fmt, stream, ifmt, &opts)

    av_log_set_level(level)
    log_level = level
    set_log_callback(old_callback)

    _log_mutex.unlock()
    avformat_close_input(&fmt)
    av_dict_free(&opts)

    for item, l in temp_log:
        for line in item.splitlines():
            log.append((line, l))
    return 0

def list_dshow_devices():
    '''Returns a list of the dshow devices available.

    :returns:

        `3-tuple`: A 3-tuple, of (`video`, `audio`, `names`)

            `video`: dict
                A dict of all the direct show **video** devices. The keys
                of the dict are the unique names of the available direct show devices. The values
                are a list of the available configurations for that device. Each
                element in the list has the following format:
                ``(pix_fmt, codec_fmt, (frame_width, frame_height), (min_framerate, max_framerate))``
            `audio`: dict
                A dict of all the direct show **audio** devices. The keys
                of the dict are the unique names of the available direct show devices. The values
                are a list of the available configurations for that device. Each
                element in the list has the following format:
                ``((min_num_channels, min_num_channels), (min_bits, max_bits), (min_rate, max_rate))``.
            `names`: dict
                A dict mapping the unique names of the video and audio devices to
                a more human friendly (possibly non-unique) name. Either of these
                names can be used when opening the device. However, if using the non-unique
                name, it's not guarenteed which of the devices sharing the name will be opened.


    For example:

    .. code-block:: python

        >>> from ffpyplayer.player import MediaPlayer
        >>> from ffpyplayer.tools import list_dshow_devices
        >>> import time, weakref
        >>> dev = list_dshow_devices()
        >>> print dev
        ({'@device_pnp_...223196\\global': [('bgr24', '', (160, 120), (5, 30)),
        ('bgr24', '', (176, 144), (5, 30)), ('bgr24', '', (320, 176), (5, 30)),
        ('bgr24', '', (320, 240), (5, 30)), ('bgr24', '', (352, 288), (5, 30)),
        ...
        ('yuv420p', '', (320, 240), (5, 30)), ('yuv420p', '', (352, 288), (5, 30))],
        '@device_pnp_...223196\\global': [('bgr24', '', (160, 120), (30, 30)),
        ...
        ('yuyv422', '', (352, 288), (30, 30)),
        ('yuyv422', '', (640, 480), (30, 30))]},
        {'@device_cm_...2- HD Webcam C615)': [((1, 2), (8, 16), (11025, 44100))],
        '@device_cm_...HD Webcam C615)': [((1, 2), (8, 16), (11025, 44100))]},
        {'@device_cm_...- HD Webcam C615)': 'Microphone (2- HD Webcam C615)',
         '@device_cm_...2- HD Webcam C615)': 'Microphone (3- HD Webcam C615)',
        ...
         '@device_pnp...223196\\global': 'HD Webcam C615',
         '@device_pnp...223196\\global': 'Laptop Integrated Webcam'})

    See :ref:`dshow-example` for a full example.
    '''
    cdef list res = []
    cdef dict video = {}, audio = {}, curr = None
    cdef object last
    cdef bytes msg, msg2
    cdef dict name_map = {}

    # list devices
    list_dshow_opts(res, b'dummy', b'list_devices')
    pname = re.compile(' *\[dshow *@ *[\w]+\] *"(.+)" *\\((video|audio)\\) *')
    apname = re.compile(' *\[dshow *@ *[\w]+\] *Alternative name *"(.+)" *')
    m = None
    for msg, level in res:
        message = msg.decode('utf8')

        m_temp = pname.match(message)
        if m_temp:
            m = m_temp
            curr = audio if m.group(2) == 'audio' else video
            curr[m.group(1)] = []
            name_map[m.group(1)] = m.group(1)
            continue

        m_temp = apname.match(message)
        if m_temp and m:
            curr[m_temp.group(1)] = []
            name_map[m_temp.group(1)] = m.group(1)
            del curr[m.group(1)]
            del name_map[m.group(1)]
        else:
            msg2 = message.encode('utf8')
            av_log(NULL, loglevels[level], '%s', msg2)

    # list video devices options
    vid_opts = re.compile(' *\[dshow *@ *[\w]+\] +(pixel_format|vcodec)=([\w]+) +min +s=\d+x\d+ +fps=(\d+)\
 +max +s=(\d+)x(\d+) +fps=(\d+).*')
    pheader1 = re.compile(' *\[dshow *@ *[\w]+\] *(?:Pin|Selecting pin) (?:"Capture"|"Output"|Capture|Output).*')
    pheader2 = re.compile(' *\[dshow *@ *[\w]+\] *DirectShow (?:video|audio) (?:only )?device options.*')
    for video_stream in video:
        res = []
        list_dshow_opts(res, ("video=%s" % video_stream).encode('utf8'), b'list_options')

        for msg, level in res:
            message = msg.decode('utf8')
            opts = vid_opts.match(message)

            if not opts:
                if not pheader1.match(message) and not pheader2.match(message):
                    av_log(NULL, loglevels[level], '%s', msg)
                continue

            g1, g2, g3, g4, g5, g6 = opts.groups()
            if g1 == 'pixel_format':
                item = g2, "", (int(g4), int(g5)), (int(g3), int(g6))
            else:
                item = "", g2, (int(g4), int(g5)), (int(g3), int(g6))

            if item not in video[video_stream]:
                video[video_stream].append(item)

        video[video_stream] = sorted(video[video_stream])

    # list audio devices options
    paud_opts = re.compile(' *\[dshow *@ *[\w]+\] +ch= *(\d+), +bits= *(\d+),\
 +rate= *(\d+).*')
    for audio_stream in audio:
        res = []
        list_dshow_opts(res, ("audio=%s" % audio_stream).encode('utf8'), b'list_options')
        for msg, level in res:
            message = msg.decode('utf8')
            mopts = paud_opts.match(message)

            if mopts:
                opts = (int(mopts.group(1)), int(mopts.group(2)), int(mopts.group(3)))
                if opts not in audio[audio_stream]:
                    audio[audio_stream].append(opts)
            elif (not pheader1.match(message)) and (not pheader2.match(message)):
                av_log(NULL, loglevels[level], '%s', msg)
        audio[audio_stream] = sorted(audio[audio_stream])

    return video, audio, name_map


cdef object encode_text(object item, int encode):
    if isinstance(item, basestring):
        if encode:
            return item.encode('utf8')
        return item.decode('utf8')

    if isinstance(item, dict):
        for k, v in item.items():
            item[k] = encode_text(v, encode)
        return item

    try:
        iter(item)
    except TypeError:
        return item

    return item.__class__((encode_text(i, encode) for i in item))

def encode_to_bytes(item):
    '''Takes the item and walks it recursively whether it's a string, int, iterable,
    etc. and encodes all the strings to utf-8.

    :Parameters:

        `item`: anything
            The object to be walked and encoded.

    :returns:

        An object identical to the ``item``, but with all strings encoded to utf-8.
    '''
    return encode_text(item, 1)

def decode_to_unicode(item):
    '''Takes the item and walks it recursively whether it's a string, int, iterable,
    etc. and encodes all the strings to utf-8.

    :Parameters:

        `item`: anything
            The object to be walked and encoded.

    :returns:

        An object identical to the ``item``, but with all strings encoded to utf-8.
    '''
    return encode_text(item, 0)

def convert_to_str(item):
    '''Takes the item and walks it recursively whether it's a string, int, iterable,
    etc. and encodes all the strings to utf-8.

    :Parameters:

        `item`: anything
            The object to be walked and encoded.

    :returns:

        An object identical to the ``item``, but with all strings encoded to utf-8.
    '''
    return encode_text(item, False)
