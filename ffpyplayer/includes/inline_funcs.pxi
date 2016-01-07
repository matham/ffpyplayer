
cdef extern from "string.h" nogil:
    char *strerror(int)

cdef extern from "errno.h" nogil:
    int EINVAL
    int EDOM

cdef extern from "limits.h" nogil:
    int INT_MAX

import sys

cdef int PY3 = sys.version_info > (3, )

cdef inline int FFMAX(int a, int b) nogil:
    if a > b:
        return a
    else:
        return b
cdef inline double FFMAXD(double a, double b) nogil:
    if a > b:
        return a
    else:
        return b
cdef inline void * FFMAXptr(void *a, void *b) nogil:
    if a > b:
        return a
    else:
        return b
cdef inline int FFMIN(int a, int b) nogil:
    if a > b:
        return b
    else:
        return a
cdef inline double FFMIND(double a, double b) nogil:
    if a > b:
        return b
    else:
        return a
cdef inline void * FFMINptr(void *a, void *b) nogil:
    if a > b:
        return b
    else:
        return a
cdef inline int compute_mod(int a, int b) nogil:
    if a < 0:
        return a%b + b
    else:
        return a%b

cdef inline int av_opt_set_int_list(void *obj, const char *name, const void *val,
                                    size_t val_deref_size, uint64_t term, int flags) nogil:
    if av_int_list_length_for_size(val_deref_size, val, term) > INT_MAX / val_deref_size:
        return AVERROR(EINVAL)
    else:
        return av_opt_set_bin(obj, name, <const uint8_t *>val,\
        av_int_list_length_for_size(val_deref_size, val, term) * val_deref_size, flags)

cdef inline int cmp_audio_fmts(AVSampleFormat fmt1, int64_t channel_count1,
                   AVSampleFormat fmt2, int64_t channel_count2) nogil:
    # If channel count == 1, planar and non-planar formats are the same
    if channel_count1 == 1 and channel_count2 == 1:
        return av_get_packed_sample_fmt(fmt1) != av_get_packed_sample_fmt(fmt2)
    else:
        return channel_count1 != channel_count2 or fmt1 != fmt2

cdef inline int64_t get_valid_channel_layout(int64_t channel_layout, int channels) nogil:
    if channel_layout and av_get_channel_layout_nb_channels(channel_layout) == channels:
        return channel_layout
    else:
        return 0

cdef inline char * emsg(int code, char *msg, int buff_size) except NULL:
    if av_strerror(code, msg, buff_size) < 0:
        if EDOM > 0:
            code = -code
        return strerror(code)
    return msg

cdef inline char * fmt_err(int code, char *msg, int buff_size) nogil:
    if av_strerror(code, msg, buff_size) < 0:
        if EDOM > 0:
            code = -code
        return strerror(code)
    return msg

cdef inline int insert_filt(
        const char *name, const char *arg, AVFilterGraph *graph,
        AVFilterContext **last_filter) nogil:
    cdef int ret
    cdef AVFilterContext *filt_ctx

    ret = avfilter_graph_create_filter(
        &filt_ctx, avfilter_get_by_name(name), name, arg, NULL, graph)
    if ret < 0:
        return ret

    ret = avfilter_link(filt_ctx, 0, last_filter[0], 0)
    if ret < 0:
        return ret

    last_filter[0] = filt_ctx
    return 0

cdef inline object tcode(bytes s):
    if PY3:
        return s.decode('utf8')
    return s
