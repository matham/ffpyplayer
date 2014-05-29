
include 'ff_defs.pxi'

from ffpyplayer.ffthreading cimport MTGenerator, MTThread, MTMutex
from ffpyplayer.ffcore cimport VideoState
from ffpyplayer.sink cimport VideoSettings, VideoSink



cdef class MediaPlayer(object):
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
