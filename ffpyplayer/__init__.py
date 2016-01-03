
import sys
from os.path import join, isdir
import platform

__version__ = '4.0.dev0'

# Dec 2015, the ffmpeg src git version tested and upto date with, including this commit
_ffmpeg_git = 'c413d9e6356e843aa492be9bb0ddf66ae6c97501'
# skipped all show modes and subtitle display related functionality commits


try:
    if platform.system() != 'Windows':
        raise ImportError()

    import ctypes
    try:
        _AddDllDirectory = ctypes.windll.kernel32.AddDllDirectory
        _AddDllDirectory.argtypes = [ctypes.c_wchar_p]
        # Needed to initialize AddDllDirectory modifications
        ctypes.windll.kernel32.SetDefaultDllDirectories(0x1000)
    except AttributeError:
        _AddDllDirectory = ctypes.windll.kernel32.SetDllDirectoryW
        _AddDllDirectory.argtypes = [ctypes.c_wchar_p]

    _ffmpeg = join(sys.prefix, 'share', 'ffpyplayer', 'ffmpeg', 'bin')
    if isdir(_ffmpeg):
        _AddDllDirectory(_ffmpeg)

    _sdl = join(sys.prefix, 'share', 'ffpyplayer', 'sdl', 'bin')
    if isdir(_sdl):
        _AddDllDirectory(_sdl)
except ImportError:
    pass
