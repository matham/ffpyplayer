from distutils.core import setup
from distutils.extension import Extension
import Cython.Compiler.Options
Cython.Compiler.Options.annotate = True
from Cython.Distutils import build_ext
import os


bin = 'bins'
share = '.dll'

ff_includes = os.path.join('includes', 'ffmpeg')
sdl_includes = os.path.join('includes', 'SDL')
include_dirs = [ff_includes, sdl_includes]

c_options = {
#If true, filters will be used'
'config_avfilter': True,
'config_avdevice': True,
'config_swscale': True,
'config_rtsp_demuxer': True,
'config_mmsh_protocol': True,
# whether sdl is included as an option
'config_sdl': True
}


print 'Generating ffconfig.h'
with open('ffconfig.h', 'wb') as f:
    f.write('''
#ifndef _FFCONFIG_H
#define _FFCONFIG_H

''' + 
'#include "' + os.path.join(sdl_includes, 'SDL_version.h') + '"\n' + 
'''
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

#endif
''')
    
print 'Generating ffconfig.pxi'
with open('ffconfig.pxi', 'wb') as f:
    for k, v in c_options.iteritems():
        f.write('DEF %s = %d\n' % (k.upper(), int(v)))



extra_objects=['avcodec-55', 'avdevice-55', 'avfilter-3', 'avformat-55',
               'avutil-52', 'swscale-2', 'swresample-0', 'SDL']
extra_objects = [os.path.join(bin, obj + share) for obj in extra_objects]
mods = ['ffpyplayer', 'ffqueue', 'ffthreading', 'sink', 'ffcore', 'ffclock']
extra_compile_args = ["-O3"]

ext_modules = [Extension(src_file, [src_file+'.pyx'], include_dirs=include_dirs,
                         extra_objects=extra_objects,
                         extra_compile_args=extra_compile_args) for src_file in mods]

setup(cmdclass={'build_ext': build_ext}, ext_modules=ext_modules)


#python setup.py build_ext --inplace --force