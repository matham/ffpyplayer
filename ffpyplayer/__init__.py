'''
FFPyPlayer library
==================
'''
import sys
import site
import os
from os.path import join
import platform

__all__ = ('dep_bins', )

__version__ = '4.3.5'
version = __version__

# the ffmpeg src git version tested and upto date with,
# not including this commit
_ffmpeg_git = 'ebee8085952de079946d903f0cc6e37aee3bc035'
# skipped all show modes and subtitle display related functionality commits

# TODO:
# * Implement CONFIG_SDL to be able to compile without needing SDL at all.
# * Currently, it only supports text subtitles - bitmap subtitles are ignored.
#   Unless one uses a filter to overlay the subtitle.
# * We can not yet visualize audio to video. Provide a filter chain link between
#   audio to video filters to acomplish this.

dep_bins = []
'''A list of paths to the binaries used by the library. It can be used during
packaging for including required binaries.

It is read only.
'''

for d in [sys.prefix, site.USER_BASE]:
    for lib in ('ffmpeg', 'sdl'):
        p = join(d, 'share', 'ffpyplayer', lib, 'bin')
        if os.path.isdir(p):
            os.environ["PATH"] = p + os.pathsep + os.environ["PATH"]
            if hasattr(os, 'add_dll_directory'):
                os.add_dll_directory(p)
            dep_bins.append(p)

if 'SDL_AUDIODRIVER' not in os.environ and platform.system() == 'Windows':
    os.environ['SDL_AUDIODRIVER'] = 'DirectSound'
