from distutils.core import setup
from distutils.extension import Extension
import os
import sys
from os.path import join, realpath
from os import environ
try:
    import Cython.Compiler.Options
    Cython.Compiler.Options.annotate = True
    from Cython.Distutils import build_ext
    have_cython = True
    cmdclass = {'build_ext': build_ext}
except ImportError:
    have_cython = False
    cmdclass = {}


platform = sys.platform
if platform in ('win32', 'cygwin'):
    suffix = '.dll.a'
else:
    suffix = '.a'
prefix = 'lib'

ffmpeg_root = environ.get('FFMPEG_ROOT')
sdl_root = environ.get('SDL_ROOT')
if (not ffmpeg_root) and os.path.exists('./ffmpeg'):
    ffmpeg_root = os.path.realpath('./ffmpeg')
if (not sdl_root) and os.path.exists('./sdl'):
    sdl_root = os.path.realpath('./sdl')
if not sdl_root:
    raise Exception('Cannot locate sdl root.')
if not ffmpeg_root:
    raise Exception('Cannot locate ffmpeg root.')
sdl = 'SDL2' if os.path.exists(join(sdl_root, 'include', 'SDL2')) else 'SDL'
print 'Selecting %s out of (SDL, SDL2)' % sdl

include_dirs = [join(sdl_root, 'include', sdl), join(ffmpeg_root, 'include')]
ff_extra_objects = ['avcodec', 'avdevice', 'avfilter', 'avformat',
               'avutil', 'swscale', 'swresample', 'postproc']
sdl_extra_objects = [sdl]
extra_objects = [join(ffmpeg_root, 'lib', prefix + obj + suffix) for obj in ff_extra_objects]
extra_objects += [join(sdl_root, 'lib', prefix + obj + suffix) for obj in sdl_extra_objects]
runtime_library_dirs = [join(ffmpeg_root, 'bin'), join(sdl_root, 'bin')]
mods = ['ffpyplayer', 'ffqueue', 'ffthreading', 'sink', 'ffcore', 'ffclock']
extra_compile_args = ["-O3"]

if have_cython:
    mod_suffix = '.pyx'
else:
    mod_suffix = '.c'


c_options = {
#If true, filters will be used'
'config_avfilter': True,
'config_avdevice': True,
'config_swscale': True,
'config_rtsp_demuxer': True,
'config_mmsh_protocol': True,
# whether sdl is included as an option
'config_sdl': True,
'has_sdl2': sdl == 'SDL2',
# these should be true
'config_avutil':True,
'config_avcodec':True,
'config_avformat':True,
'config_swresample':True,
'config_postproc':True
}


print 'Generating ffconfig.h'
with open(join('ffpyplayer', 'ffconfig.h'), 'wb') as f:
    f.write('''
#ifndef _FFCONFIG_H
#define _FFCONFIG_H

#include "SDL_version.h"
#define SDL_VERSIONNUM(X, Y, Z) ((X)*1000 + (Y)*100 + (Z))
#define SDL_VERSION_ATLEAST(X, Y, Z) (SDL_COMPILEDVERSION >= SDL_VERSIONNUM(X, Y, Z))
#if defined(__APPLE__) && SDL_VERSION_ATLEAST(1, 2, 14)
#define MAC_REALLOC 1
#else
#define MAC_REALLOC 0
#endif

#if !defined(__MINGW32__) && !defined(__APPLE__)
#define NOT_WIN_MAC 1
#else
#define NOT_WIN_MAC 0
#endif

''')
    for k, v in c_options.iteritems():
        f.write('#define %s %d\n' % (k.upper(), int(v)))
    f.write('''
#endif
''')

print 'Generating ffconfig.pxi'
with open(join('ffpyplayer', 'ffconfig.pxi'), 'wb') as f:
    for k, v in c_options.iteritems():
        f.write('DEF %s = %d\n' % (k.upper(), int(v)))


ext_modules = [Extension('ffpyplayer.' + src_file, [join('ffpyplayer', src_file+mod_suffix)],
                         include_dirs=include_dirs, extra_objects=extra_objects,
                         extra_compile_args=extra_compile_args) for src_file in mods]

setup(cmdclass={'build_ext': build_ext}, ext_modules=ext_modules)

#python setup.py build_ext --inplace --force