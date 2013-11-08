'''
------------------------------------------------------------------------------- 
XXX: this should be checked for every version of SDL since these
are constants defined in the headers and they may change between versions.
'''
DEF FF_ALLOC_EVENT = 24 # SDL_USEREVENT
DEF FF_QUIT_EVENT = FF_ALLOC_EVENT + 2
DEF FF_EOF_EVENT = FF_ALLOC_EVENT + 3
'-----------------------------------------------------------------------------'
include "ffconfig.pxi"

cdef extern from "ffconfig.h":
    bint MAC_REALLOC
    bint NOT_WIN_MAC



''' SDL audio buffer size, in samples. Should be small to have precise
A/V sync as SDL does not have hardware buffer fullness info. '''
DEF SDL_AUDIO_BUFFER_SIZE = 1024
DEF AUDIO_BUFFER_SIZE = SDL_AUDIO_BUFFER_SIZE
DEF CURSOR_HIDE_DELAY = 1000000

DEF MAX_QUEUE_SIZE = (15 * 1024 * 1024)
DEF MIN_FRAMES = 5

'no AV sync correction is done if below the minimum AV sync threshold '
DEF AV_SYNC_THRESHOLD_MIN = 0.01
'AV sync correction is done if above the maximum AV sync threshold '
DEF AV_SYNC_THRESHOLD_MAX = 0.1
'If a frame duration is longer than this, it will not be duplicated to compensate AV sync'
DEF AV_SYNC_FRAMEDUP_THRESHOLD = 0.1
'no AV correction is done if too big error'
DEF AV_NOSYNC_THRESHOLD = 10.0

'maximum audio speed change to get correct sync'
DEF SAMPLE_CORRECTION_PERCENT_MAX = 10

'external clock speed adjustment constants for realtime sources based on buffer fullness'
DEF EXTERNAL_CLOCK_SPEED_MIN = 0.900
DEF EXTERNAL_CLOCK_SPEED_MAX = 1.010
DEF EXTERNAL_CLOCK_SPEED_STEP = 0.001

'we use about AUDIO_DIFF_AVG_NB A-V differences to make the average'
DEF AUDIO_DIFF_AVG_NB = 20

'polls for possible required screen refresh at least this often, should be less than 1/fps'
DEF REFRESH_RATE = 0.01

'''NOTE: the size must be big enough to compensate the hardware audio buffersize size
TODO: We assume that a decoded and resampled frame fits into this buffer'''
DEF SAMPLE_ARRAY_SIZE = (8 * 65536)

DEF VIDEO_PICTURE_QUEUE_SIZE = 3
DEF SUBPICTURE_QUEUE_SIZE = 4