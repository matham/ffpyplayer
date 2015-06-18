
__all__ = ('version', )
version = '3.2-dev'
# The ffmpeg src git version tested with. Nov, 18, 2013
_ffmpeg_git = '1f7b7d54471711b89f8a64bef1c6636b6aa08c12'

import os
import sys
from os.path import join
from os import environ
# needed for windows so dlls are found
ffmpeg_root = environ.get('FFMPEG_ROOT')
sdl_root = environ.get('SDL_ROOT')
if ffmpeg_root and os.path.exists(join(ffmpeg_root, 'bin')):
    bin_path = join(ffmpeg_root, 'bin')
    if bin_path not in os.pathsep.split(os.environ['PATH']):
        os.environ['PATH'] = bin_path + os.pathsep + os.environ['PATH']
if sdl_root and os.path.exists(join(sdl_root, 'bin')):
    bin_path = join(sdl_root, 'bin')
    if bin_path not in os.pathsep.split(os.environ['PATH']):
        os.environ['PATH'] = bin_path + os.pathsep + os.environ['PATH']
