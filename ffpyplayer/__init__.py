
__all__ = ('version', )
version = '3.2-dev'
# Dec 2015, the ffmpeg src git version tested and upto date with, including this commit
_ffmpeg_git = 'c413d9e6356e843aa492be9bb0ddf66ae6c97501'


# skipped all show modes and subtitle display related functionality commits

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
