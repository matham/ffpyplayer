
include 'ff_defs.pxi'

cimport ffthreading
from ffthreading cimport MTGenerator, MTThread, MTMutex
cimport ffcore
from ffcore cimport VideoState
cimport sink
from sink cimport VideoSettings, VideoSink



cdef class FFPyPlayer(object):
    cdef:
        VideoSettings settings
        MTGenerator mt_gen
        VideoSink vid_sink
        VideoState ivs
        MTMutex settings_mutex
        bytes py_window_title
        bytes py_vfilters
        bytes py_afilters
        bytes py_avfilters
        bytes py_audio_codec_name
        bytes py_video_codec_name
        bytes py_subtitle_codec_name
