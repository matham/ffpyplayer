from distutils.core import setup
from distutils.extension import Extension
import os
import sys
from os.path import join, exists
from os import environ
from ffpyplayer import version
try:
    import Cython.Compiler.Options
    #Cython.Compiler.Options.annotate = True
    from Cython.Distutils import build_ext
    have_cython = True
    cmdclass = {'build_ext': build_ext}
except ImportError:
    have_cython = False
    cmdclass = {}


# select which ffmpeg libraries will be available
c_options = {
#If true, filters will be used'
'config_avfilter': True,
'config_avdevice': True,
'config_swscale': True,
'config_rtsp_demuxer': True,
'config_mmsh_protocol': True,
'config_postproc':True,
# whether sdl is included as an option
'config_sdl': True, # not implemented yet
'has_sdl2': False,
# these should be true
'config_avutil':True,
'config_avcodec':True,
'config_avformat':True,
'config_swresample':True
}
for key in list(c_options.keys()):
    ukey = key.upper()
    if ukey in environ:
        value = bool(int(environ[ukey]))
        print('Environ change {0} -> {1}'.format(key, value))
        c_options[key] = value
if (not c_options['config_avfilter']) and not c_options['config_swscale']:
    raise Exception('At least one of config_avfilter and config_swscale must be enabled.')
#if c_options['config_avfilter'] and ((not c_options['config_postproc']) or not c_options['config_swscale']):
#    raise Exception('config_avfilter implicitly requires the postproc and swscale binaries.')
c_options['config_avutil'] = c_options['config_avutil'] = True
c_options['config_avformat'] = c_options['config_swresample'] = True

# on windows we use .dll.a, not .a files
platform = sys.platform
if platform in ('win32', 'cygwin'):
    suffix = '.dll.a'
else:
    suffix = '.a'
prefix = 'lib'

# locate sdl and ffmpeg headers and binaries
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
for libname in ff_extra_objects[:]:
    for key, val in c_options.iteritems():
        if key.endswith(libname) and not val:
            ff_extra_objects.remove(libname)
            break
sdl_extra_objects = [sdl]

# if .so files are available use them
extra_objects = []
for ff_obj in ff_extra_objects:
    res = join(ffmpeg_root, 'lib', prefix + ff_obj + suffix)
    if exists(join(ffmpeg_root, 'lib', prefix + ff_obj + '.so')):
        res = join(ffmpeg_root, 'lib', prefix + ff_obj + '.so')
    extra_objects.append(res)
for sdl_obj in sdl_extra_objects:
    res = join(sdl_root, 'lib', prefix + sdl_obj + suffix)
    if exists(join(sdl_root, 'lib', prefix + sdl_obj + '.so')):
        res = join(sdl_root, 'lib', prefix + sdl_obj + '.so')
    extra_objects.append(res)

mods = ['player', 'ffqueue', 'ffthreading', 'sink', 'ffcore', 'ffclock', 'tools',
        'writer', 'pic']
extra_compile_args = ["-O3", '-fno-strict-aliasing']
c_options['has_sdl2'] = sdl == 'SDL2'

if have_cython:
    mod_suffix = '.pyx'
else:
    mod_suffix = '.c'


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


ext_modules = [Extension('ffpyplayer.' + src_file,
    sources=[join('ffpyplayer', src_file+mod_suffix), join('ffpyplayer', 'ffinfo.c')],
    include_dirs=include_dirs, extra_objects=extra_objects,
    extra_compile_args=extra_compile_args) for src_file in mods]

for e in ext_modules:
    e.cython_directives = {"embedsignature": True}

setup(name='ffpyplayer',
      version=version,
      author='Matthew Einhorn',
      license='LGPL3',
      description='A cython implementation of an ffmpeg based player.',
      classifiers=['License :: OSI Approved :: GNU Lesser General Public License v3 (LGPLv3)',
                   'Topic :: Multimedia :: Video',
                   'Topic :: Multimedia :: Video :: Display',
                   'Topic :: Multimedia :: Sound/Audio :: Players',
                   'Topic :: Multimedia :: Sound/Audio :: Players :: MP3',
                   'Programming Language :: Python :: 2.7',
                   'Operating System :: MacOS :: MacOS X',
                   'Operating System :: Microsoft :: Windows',
                   'Operating System :: POSIX :: BSD :: FreeBSD',
                   'Operating System :: POSIX :: Linux',
                   'Intended Audience :: Developers'],
      packages=['ffpyplayer'],
      cmdclass=cmdclass, ext_modules=ext_modules)
