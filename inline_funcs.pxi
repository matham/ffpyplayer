
cdef extern from "errno.h" nogil:
    int EINVAL

cdef extern from "limits.h" nogil:
    int INT_MAX


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

cdef inline unsigned int EVENTMASK(unsigned int X) nogil:
    return 1 << X

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

cdef inline uint8_t ALPHA_BLEND(int a, uint8_t oldp, int newp, uint8_t s) nogil:
    return ((((oldp << s) * (255 - (a))) + (newp * (a))) / (255 << s)) 
 
cdef inline void RGBA_IN(int *r, int *g, int *b, int *a, uint32_t* s) nogil:
    cdef unsigned int v = (<const uint32_t *>s)[0]
    a[0] = (v >> 24) & 0xff
    r[0] = (v >> 16) & 0xff
    g[0] = (v >> 8) & 0xff
    b[0] = v & 0xff
 
cdef inline void YUVA_IN(int *y, int *u, int *v, int *a, const uint8_t *s, const uint32_t *pal) nogil:
    cdef unsigned int val = pal[s[0]]
    a[0] = (val >> 24) & 0xff
    y[0] = (val >> 16) & 0xff
    u[0] = (val >> 8) & 0xff
    v[0] = val & 0xff
 
cdef inline void YUVA_OUT(uint32_t *d, int y, int u, int v, int a) nogil:
    d[0] = (a << 24) | (y << 16) | (u << 8) | v


DEF SCALEBITS = 10
DEF ONE_HALF = 1 << (SCALEBITS - 1)
cdef inline int FIX(double x) nogil:
    return <int>(<int>x * (1 << SCALEBITS) + 0.5)

cdef inline int RGB_TO_Y_CCIR(int r, int g, int b) nogil:
    return (FIX(0.29900*219.0/255.0) * r + FIX(0.58700*219.0/255.0) * g +\
    FIX(0.11400*219.0/255.0) * b + (ONE_HALF + (16 << SCALEBITS))) >> SCALEBITS

cdef inline int RGB_TO_U_CCIR(int r1, int g1, int b1, int shift) nogil:
    return ((- FIX(0.16874*224.0/255.0) * r1 - FIX(0.33126*224.0/255.0) * g1 +\
    FIX(0.50000*224.0/255.0) * b1 + (ONE_HALF << shift) - 1) >> (SCALEBITS + shift)) + 128

cdef inline int RGB_TO_V_CCIR(int r1, int g1, int b1, int shift) nogil:
    return ((FIX(0.50000*224.0/255.0) * r1 - FIX(0.41869*224.0/255.0) * g1 -\
    FIX(0.08131*224.0/255.0) * b1 + (ONE_HALF << shift) - 1) >> (SCALEBITS + shift)) + 128

