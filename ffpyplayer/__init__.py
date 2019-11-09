'''
FFPyPlayer library
==================
'''
import sys
import os
from os.path import join, isdir
import platform

__all__ = ('dep_bins', )

__version__ = '4.3.0.dev0'
version = __version__

# the ffmpeg src git version tested and upto date with,
# not including this commit
_ffmpeg_git = '915bb7881555c4966738b7ee78b28845c4665a40'
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

_ffmpeg = join(sys.prefix, 'share', 'ffpyplayer', 'ffmpeg', 'bin')
if isdir(_ffmpeg):
    if hasattr(os, 'add_dll_directory'):
        os.add_dll_directory(_ffmpeg)
    else:
        os.environ["PATH"] += os.pathsep + _ffmpeg
    dep_bins.append(_ffmpeg)

_sdl = join(sys.prefix, 'share', 'ffpyplayer', 'sdl', 'bin')
if isdir(_sdl):
    if hasattr(os, 'add_dll_directory'):
        os.add_dll_directory(_sdl)
    else:
        os.environ["PATH"] += os.pathsep + _sdl
    dep_bins.append(_sdl)

if 'SDL_AUDIODRIVER' not in os.environ and platform.system() == 'Windows':
    os.environ['SDL_AUDIODRIVER'] = 'DirectSound'
