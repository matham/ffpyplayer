
include 'ff_defs.pxi'

cimport ffthreading
from ffthreading cimport MTGenerator, MTThread
cimport ffcore
from ffcore cimport VideoState, VideoSettings


cdef class FFPyPlayer(object):
    cdef:
        VideoSettings settings
        MTGenerator mt_gen
        VideoState ivs
        MTThread update_thread
        bytes py_window_title
        bytes py_vfilters
        bytes py_afilters
        bytes py_audio_codec_name
        bytes py_video_codec_name
        bytes py_subtitle_codec_name
        bytes py_filename
    cdef void event_loop(FFPyPlayer self) nogil
    