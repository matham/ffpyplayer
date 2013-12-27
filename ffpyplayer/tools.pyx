
__all__ = ('loglevels', 'codecs', 'pix_fmts', 'set_log_callback',
           'get_supported_framerates', 'get_supported_pixfmts')


include 'ff_defs.pxi'


cimport ffthreading
from ffthreading cimport Py_MT, MTMutex


'see http://ffmpeg.org/ffmpeg.html for log levels'
loglevels = {"quiet":AV_LOG_QUIET, "panic":AV_LOG_PANIC, "fatal":AV_LOG_FATAL,
             "error":AV_LOG_ERROR, "warning":AV_LOG_WARNING, "info":AV_LOG_INFO,
             "verbose":AV_LOG_VERBOSE, "debug":AV_LOG_DEBUG}
''' FFmpeg log levels
'''
loglevel_inverse = {v:k for k, v in loglevels.iteritems()}

codecs = list_ffcodecs()
codecs_inverse = {v:k for k, v in codecs.iteritems()}
pix_fmts = list_pixfmts()
pix_fmts_inverse = {v:k for k, v in pix_fmts.iteritems()}


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
            _log_callback(str(line), loglevel_inverse[level])
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

cdef int ffmpeg_initialized = 0
def _initialize_ffmpeg():
    global ffmpeg_initialized
    if not ffmpeg_initialized:
        print_all_libs_info(INDENT|SHOW_CONFIG,  AV_LOG_INFO)
        print_all_libs_info(INDENT|SHOW_VERSION, AV_LOG_INFO)
        avcodec_register_all() # register all codecs, demux and protocols
        IF CONFIG_AVDEVICE:
            avdevice_register_all()
        IF CONFIG_AVFILTER:
            avfilter_register_all()
        av_register_all()
        avformat_network_init()
        ffmpeg_initialized = 1

cdef dict list_ffcodecs():
    cdef dict codecs = {}
    cdef AVCodecDescriptor *desc = NULL
    desc = avcodec_descriptor_next(desc)

    while desc != NULL:
        codecs[desc.name] = <int>desc.id
        desc = avcodec_descriptor_next(desc)
    return codecs

cdef dict list_pixfmts():
    cdef dict fmts = {}
    cdef AVPixFmtDescriptor *desc = NULL
    desc = av_pix_fmt_desc_next(desc)

    while desc != NULL:
        fmts[desc.name] = <int>av_pix_fmt_desc_get_id(desc)
        desc = av_pix_fmt_desc_next(desc)
    return fmts

def get_supported_framerates(codec_name, rate=()):
    ''' if rate, the closest is first element
    '''
    cdef AVRational rate_struct
    cdef list rate_list = []
    cdef int i = 0
    cdef AVCodec *codec = avcodec_find_encoder(<AVCodecID>codecs[codec_name])
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
    cdef AVCodec *codec = avcodec_find_encoder(<AVCodecID>codecs[codec_name])
    if codec == NULL:
        raise Exception('Codec %s not recognized.' % codec_name)
    if codec.pix_fmts == NULL:
        return fmt_list

    while codec.pix_fmts[i] != AV_PIX_FMT_NONE:
        fmt_list.append(pix_fmts_inverse[<int>codec.pix_fmts[i]])
    if pix_fmt:
        has_alpha = av_pix_fmt_desc_get(<AVPixelFormat>pix_fmts[pix_fmt]).nb_components % 2 == 0
        fmt = avcodec_find_best_pix_fmt_of_list(codec.pix_fmts, <AVPixelFormat>pix_fmts[pix_fmt],
                                                has_alpha, &loss)
        i = fmt_list.index(pix_fmts_inverse[<int>fmt])
        pix = fmt_list[i]
        del fmt_list[i]
        fmt_list.insert(0, pix)
    return fmt_list
