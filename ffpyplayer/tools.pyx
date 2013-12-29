
__all__ = ('loglevels', 'codecs', 'pix_fmts', 'formats_in', 'formats_out',
           'set_log_callback', 'get_supported_framerates', 'get_supported_pixfmts',
           'emit_library_info')


include 'ff_defs.pxi'

cimport ffthreading
from ffthreading cimport Py_MT, MTMutex


cdef int ffmpeg_initialized = 0
def _initialize_ffmpeg():
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

codecs = sorted(list_ffcodecs())
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
    global _log_callback
    if callback is not None and not callable(callback):
        raise Exception('Log callback needs to be callable.')
    _log_mutex.lock()
    if callback is None:
        av_log_set_callback(&av_log_default_callback)
    else:
        av_log_set_callback(&_log_callback_func)
    _log_callback = callback
    _log_mutex.unlock()


cdef list list_ffcodecs():
    cdef list codecs = []
    cdef AVCodecDescriptor *desc = NULL
    desc = avcodec_descriptor_next(desc)

    while desc != NULL:
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
    ''' if rate, the closest is first element
    '''
    cdef AVRational rate_struct
    cdef list rate_list = []
    cdef int i = 0
    cdef AVCodec *codec = avcodec_find_encoder_by_name(codec_name)
    if codec == NULL:
        raise Exception('Codec %s not recognized.' % codec_name)
    if codec.supported_framerates == NULL:
        return rate_list

    while codec.supported_framerates[i].den:
        rate_list.append((codec.supported_framerates[i].num, codec.supported_framerates[i].den))
    if rate:
        rate_struct.num, rate_struct.den = rate
        i = av_find_nearest_q_idx(rate_struct, codec.supported_framerates)
        rate = rate_list[i]
        del rate_list[i]
        rate_list.insert(0, rate)
    return rate_list

def get_supported_pixfmts(codec_name, pix_fmt=''):
    ''' if rate, the closest is first element
    '''
    cdef AVPixelFormat fmt
    cdef list fmt_list = []
    cdef int i = 0, loss = 0, has_alpha = 0
    cdef AVCodec *codec = avcodec_find_encoder_by_name(codec_name)
    if codec == NULL:
        raise Exception('Codec %s not recognized.' % codec_name)
    if pix_fmt and av_get_pix_fmt(pix_fmt) == AV_PIX_FMT_NONE:
        raise Exception('Pixel format not recognized.')
    if codec.pix_fmts == NULL:
        return fmt_list

    while codec.pix_fmts[i] != AV_PIX_FMT_NONE:
        fmt_list.append(av_get_pix_fmt_name(codec.pix_fmts[i]))
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
    print_all_libs_info(INDENT|SHOW_CONFIG,  AV_LOG_INFO)
    print_all_libs_info(INDENT|SHOW_VERSION, AV_LOG_INFO)
