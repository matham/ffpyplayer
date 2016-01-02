
include '../includes/ffmpeg.pxi'

from ffpyplayer.threading cimport MTGenerator, MTThread, MTMutex
from ffpyplayer.player.core cimport VideoState, VideoSettings
from ffpyplayer.pic cimport Image


cdef class MediaPlayer(object):
    cdef:
        VideoSettings settings
        MTGenerator mt_gen
        VideoState ivs
        bytes py_window_title
        bytes py_vfilters
        bytes py_afilters
        bytes py_avfilters
        bytes py_audio_codec_name
        bytes py_video_codec_name
        bytes py_subtitle_codec_name
        Image next_image
        int is_closed
        dict ff_opts

    cdef void _seek(self, double pts, int relative, int seek_by_bytes, int accurate) nogil
    cpdef close_player(self)
