
include 'ff_defs.pxi'

from ffpyplayer.ffthreading cimport MTGenerator, MTThread, MTMutex
from ffpyplayer.ffcore cimport VideoState
from ffpyplayer.sink cimport VideoSettings, VideoSink
from ffpyplayer.pic cimport Image


cdef class MediaPlayer(object):
    cdef:
        VideoSettings settings
        MTGenerator mt_gen
        VideoSink vid_sink
        VideoState ivs
        bytes py_window_title
        bytes py_vfilters
        bytes py_afilters
        bytes py_avfilters
        bytes py_audio_codec_name
        bytes py_video_codec_name
        bytes py_subtitle_codec_name
        Image next_image

    cdef void _seek(self, double pts, int relative, int seek_by_bytes) nogil
