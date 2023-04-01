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

__version__ = '4.5.0'
version = __version__

# the ffmpeg src git version tested and upto date with,
# and including this commit
_ffmpeg_git = 'c926140558c60786dc577b121df6b3c6b430bd98'
# excludes commits bdf9ed41fe4bdf4e254615b7333ab0feb1977e98,
# 1be3d8a0cb77f8d34c1f39b47bf5328fe10c82d7,
# f1907faab4023517af7d10d746b5684cccc5cfcc, and
# 0995e1f1b31f6e937a1b527407ed3e850f138098 because they require ffmpeg 5.1/5.2
# which is too new as of now

# also skipped all show modes and subtitle display related functionality commits

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
    if d is None:
        continue
    for lib in ('ffmpeg', 'sdl'):
        p = join(d, 'share', 'ffpyplayer', lib, 'bin')
        if os.path.isdir(p):
            os.environ["PATH"] = p + os.pathsep + os.environ["PATH"]
            if hasattr(os, 'add_dll_directory'):
                os.add_dll_directory(p)
            dep_bins.append(p)

if 'SDL_AUDIODRIVER' not in os.environ and platform.system() == 'Windows':
    os.environ['SDL_AUDIODRIVER'] = 'DirectSound'
