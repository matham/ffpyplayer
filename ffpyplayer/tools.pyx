
__all__ = ('loglevels', 'codecs_enc', 'codecs_dec', 'pix_fmts', 'formats_in',
           'formats_out', 'set_log_callback', 'get_supported_framerates',
           'get_supported_pixfmts', 'emit_library_info')


include 'ff_defs.pxi'

cimport ffthreading
from ffthreading cimport Py_MT, MTMutex


cdef int ffmpeg_initialized = 0
def _initialize_ffmpeg():
    '''
    Initializes ffmpeg libraries. Must be called before anything can be used.
    '''
    global ffmpeg_initialized
    if not ffmpeg_initialized:
        avcodec_register_all() # register all codecs, demux and protocols
        IF CONFIG_AVDEVICE:
            avdevice_register_all()
        IF CONFIG_AVFILTER:
            avfilter_register_all()
        av_register_all()
        avformat_network_init()
        ffmpeg_initialized = 1
_initialize_ffmpeg()


'see http://ffmpeg.org/ffmpeg.html for log levels'
loglevels = {"quiet":AV_LOG_QUIET, "panic":AV_LOG_PANIC, "fatal":AV_LOG_FATAL,
             "error":AV_LOG_ERROR, "warning":AV_LOG_WARNING, "info":AV_LOG_INFO,
             "verbose":AV_LOG_VERBOSE, "debug":AV_LOG_DEBUG}
_loglevel_inverse = {v:k for k, v in loglevels.iteritems()}

codecs_enc = sorted(list_enc_codecs())
codecs_dec = sorted(list_dec_codecs())
pix_fmts = sorted(list_pixfmts())
formats_in = sorted(list_fmt_in())
formats_out = sorted(list_fmt_out())


cdef object _log_callback = None
cdef int _print_prefix
cdef MTMutex _log_mutex= MTMutex(Py_MT)

cdef void _log_callback_func(void* ptr, int level, const char* fmt, va_list vl) nogil:
    cdef char line[2048]
    global _print_prefix
    _log_mutex.lock()
    _print_prefix = 1
    av_log_format_line(ptr, level, fmt, vl, line, sizeof(line), &_print_prefix)
    if _log_callback is not None:
        with gil:
            _log_callback(str(line), _loglevel_inverse[level])
    _log_mutex.unlock()

def set_log_callback(object callback):
    '''
    Sets a callback to be used for printing ffmpeg logs.

    **Args**:
        *callback* (callable, or None): A function which will be called with strings to
        be printed. Takes two parameters: *message* and *level*. *message* is the
        string to be printed. *level* is the log level of the string and is one
        of the keys of the :attr:`loglevels` dict. If None, the default ffmpeg
        log callback will be set, which prints to stderr.

    **Returns**:
        The last callback set, or None.

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
    _log_mutex.lock()
    old_callback = _log_callback
    if callback is None:
        av_log_set_callback(&av_log_default_callback)
    else:
        av_log_set_callback(&_log_callback_func)
    _log_callback = callback
    _log_mutex.unlock()
    return old_callback


cdef list list_enc_codecs():
    cdef list codecs = []
    cdef AVCodecDescriptor *desc = NULL
    desc = avcodec_descriptor_next(desc)

    while desc != NULL:
        if avcodec_find_encoder(desc.id) != NULL and desc.type == AVMEDIA_TYPE_VIDEO:
            codecs.append(desc.name)
        desc = avcodec_descriptor_next(desc)
    return codecs

cdef list list_dec_codecs():
    cdef list codecs = []
    cdef AVCodecDescriptor *desc = NULL
    desc = avcodec_descriptor_next(desc)

    while desc != NULL:
        if avcodec_find_decoder(desc.id) != NULL and desc.type == AVMEDIA_TYPE_VIDEO:
            codecs.append(desc.name)
        desc = avcodec_descriptor_next(desc)
    return codecs

cdef list list_pixfmts():
    cdef list fmts = []
    cdef AVPixFmtDescriptor *desc = NULL
    desc = av_pix_fmt_desc_next(desc)

    while desc != NULL:
        fmts.append(desc.name)
        desc = av_pix_fmt_desc_next(desc)
    return fmts

cdef list list_fmt_out():
    cdef list fmts = []
    cdef AVOutputFormat *fmt = NULL
    fmt = av_oformat_next(fmt)

    while fmt != NULL:
        fmts.extend(fmt.name.split(','))
        fmt = av_oformat_next(fmt)
    return fmts

cdef list list_fmt_in():
    cdef list fmts = []
    cdef AVInputFormat *fmt = NULL
    fmt = av_iformat_next(fmt)

    while fmt != NULL:
        fmts.extend(fmt.name.split(','))
        fmt = av_iformat_next(fmt)
    return fmts

def get_supported_framerates(codec_name, rate=()):
    '''
    Returns the supported frame rates for encoding codecs. If a desired rate is
    provided, it also returns the closest valid rate.

    **Args**:
        *codec_name* (str): The name of a encoding codec.

        *rate* (2-tuple of ints, or empty tuple): If provided, a 2-tuple where the
        first element is the numerator, and the second the denominator of the frame
        rate we wish to use. E.g. (2997, 100) means a frame rate of 29.97.

    **Returns**:
        (list of 2-tuples, or empty list): If there are no restrictions on the frame
        rate it returns a empty list, otherwise it returns a list with the valid
        frame rates. If rate is provided and there are restrictions to the frame
        rates, the closest frame rate is the zero'th element in the list.

    ::

        >>> print get_supported_framerates('mpeg1video', ())
        [(24000, 1001), (24, 1), (25, 1), (30000, 1001), (30, 1), (50, 1),
        (60000, 1001), (60, 1), (15, 1), (5, 1), (10, 1), (12, 1), (15, 1)]

        >>> print get_supported_framerates('mpeg1video', (2997, 100))
        [(30000, 1001), (24000, 1001), (24, 1), (25, 1), (30, 1), (50, 1),
        (60000, 1001), (60, 1), (15, 1), (5, 1), (10, 1), (12, 1), (15, 1)]
    '''
    cdef AVRational rate_struct
    cdef list rate_list = []
    cdef int i = 0
    cdef AVCodec *codec = avcodec_find_encoder_by_name(codec_name)
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
    '''
    Returns the supported pixel formats for encoding codecs. If a desired format
    is provided, it also returns the closest format (i.e. the format with minimum
    conversion loss).

    **Args**:
        *codec_name* (str): The name of a encoding codec.

        *pix_fmt* (str): If not empty, the name of a pixel format we wish to use
        with this codec, e.g. 'rgb24'.

    **Returns**:
        (list of pixel formats, or empty list): If there are no restrictions on the
        pixel formats it returns a empty list, otherwise it returns a list with the
        valid formats. If pix_fmt is not empty and there are restrictions to the
        formats, the closest format which results in the minimum loss when converting
        will be returned as the zero'th element in the list.

    ::

        >>> print get_supported_pixfmts('ffv1', '')
        ['yuv420p', 'yuva420p', 'yuva422p', 'yuv444p', 'yuva444p', 'yuv440p', ...
        'gray16le', 'gray', 'gbrp9le', 'gbrp10le', 'gbrp12le', 'gbrp14le']

        >>> print get_supported_pixfmts('ffv1', 'gray')
        ['gray', 'yuv420p', 'yuva420p', 'yuva422p', 'yuv444p', 'yuva444p', ...
        'gray16le', 'gbrp9le', 'gbrp10le', 'gbrp12le', 'gbrp14le']
    '''
    cdef AVPixelFormat fmt
    cdef list fmt_list = []
    cdef int i = 0, loss = 0, has_alpha = 0
    cdef AVCodec *codec = avcodec_find_encoder_by_name(codec_name)
    if codec == NULL:
        raise Exception('Encoder codec %s not available.' % codec_name)
    if pix_fmt and av_get_pix_fmt(pix_fmt) == AV_PIX_FMT_NONE:
        raise Exception('Pixel format not recognized.')
    if codec.pix_fmts == NULL:
        return fmt_list

    while codec.pix_fmts[i] != AV_PIX_FMT_NONE:
        fmt_list.append(av_get_pix_fmt_name(codec.pix_fmts[i]))
        i += 1
    if pix_fmt:
        has_alpha = av_pix_fmt_desc_get(av_get_pix_fmt(pix_fmt)).nb_components % 2 == 0
        fmt = avcodec_find_best_pix_fmt_of_list(codec.pix_fmts, av_get_pix_fmt(pix_fmt),
                                                has_alpha, &loss)
        i = fmt_list.index(av_get_pix_fmt_name(fmt))
        pix = fmt_list[i]
        del fmt_list[i]
        fmt_list.insert(0, pix)
    return fmt_list

def emit_library_info():
    '''
    Prints to the ffmpeg log all the ffmpeg library's versions and configure
    options.
    '''
    print_all_libs_info(INDENT|SHOW_CONFIG,  AV_LOG_INFO)
    print_all_libs_info(INDENT|SHOW_VERSION, AV_LOG_INFO)

def list_dshow_devices():
    cdef AVFormatContext *fmt = avformat_alloc_context()
    cdef AVDictionary* opts = NULL
    cdef AVInputFormat *ifmt

    res = []
    def log_callback(message, level):
        res.append(message)

    av_dict_set(&opts, "list_devices", "true", 0)
    ifmt = av_find_input_format("dshow")

    old_callback = set_log_callback(log_callback)
    avformat_open_input(&fmt, "video=dummy", ifmt, &opts)
    set_log_callback(old_callback)
    return res
