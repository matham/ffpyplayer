from ffpyplayer.tools import set_loglevel, set_log_callback
import logging

set_log_callback(logger=logging, default_only=True)
set_loglevel('trace')
