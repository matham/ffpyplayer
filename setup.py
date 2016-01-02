try:
    from setuptools import setup, Extension
except ImportError:
    from distutils.core import setup
    from distutils.extension import Extension
import os
import sys
from os.path import join, exists, isdir, dirname, abspath
from os import environ, listdir
from ffpyplayer import __version__
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


def getoutput(cmd):
    import subprocess
    p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE,
                         stderr=subprocess.PIPE)
    p.wait()
    if p.returncode:  # if not returncode == 0
        print('WARNING: A problem occured while running {0} (code {1})\n'
              .format(cmd, p.returncode))
        stderr_content = p.stderr.read()
        if stderr_content:
            print('{0}\n'.format(stderr_content))
        return ""
    return p.stdout.read()


def pkgconfig(*packages, **kw):
    flag_map = {'-I': 'include_dirs', '-L': 'library_dirs', '-l': 'libraries'}
    cmd = 'pkg-config --libs --cflags {}'.format(' '.join(packages))
    results = getoutput(cmd).split()
    for token in results:
        ext = token[:2].decode('utf-8')
        flag = flag_map.get(ext)
        if not flag:
            continue
        kw.setdefault(flag, []).append(token[2:].decode('utf-8'))
    return kw

libraries = []
library_dirs = []
include_dirs = []

if "KIVYIOSROOT" in environ:
    # enable kivy-ios compilation
    include_dirs = [
        environ.get("SDL_INCLUDE_DIR"),
        environ.get("FFMPEG_INCLUDE_DIR")]
    sdl = "SDL2"

elif "NDKPLATFORM" in environ:
    # enable python-for-android compilation
    include_dirs = [
        environ.get("SDL_INCLUDE_DIR"),
        environ.get("FFMPEG_INCLUDE_DIR")]
    ffmpeg_libdir = environ.get("FFMPEG_LIB_DIR")
    sdl = "SDL"
    libraries = ['avcodec', 'avdevice', 'avfilter', 'avformat',
                 'avutil', 'swscale', 'swresample', 'postproc',
                 'sdl']

else:

    # locate sdl and ffmpeg headers and binaries
    ffmpeg_root = environ.get('FFMPEG_ROOT')
    if ffmpeg_root is not None and not isdir(ffmpeg_root):
        ffmpeg_root = None

    if ffmpeg_root is not None:
        ffmpeg_include = environ.get('FFMPEG_INCLUDE_DIR', join(ffmpeg_root, 'include'))
        ffmpeg_lib = environ.get('FFMPEG_LIB_DIR', join(ffmpeg_root, 'lib'))
    else:
        ffmpeg_include = environ.get('FFMPEG_INCLUDE_DIR')
        ffmpeg_lib = environ.get('FFMPEG_LIB_DIR')
    if ffmpeg_include is not None and not isdir(ffmpeg_include):
        ffmpeg_include = None
    if ffmpeg_lib is not None and not isdir(ffmpeg_lib):
        ffmpeg_lib = None

    objects = ['avcodec', 'avdevice', 'avfilter', 'avformat',
                   'avutil', 'swscale', 'swresample', 'postproc']
    for libname in objects[:]:
        for key, val in c_options.iteritems():
            if key.endswith(libname) and not val:
                objects.remove(libname)
                break

    flags = {'include_dirs': [], 'library_dirs': [], 'libraries': []}
    if ffmpeg_lib is None and ffmpeg_include is None:
        flags = pkgconfig(*objects)

    library_dirs = flags.get('library_dirs', []) if ffmpeg_lib is None \
        else [ffmpeg_lib]
    include_dirs = flags.get('include_dirs', []) if ffmpeg_include is None \
        else [ffmpeg_include]
    libraries = objects[:]

    # sdl
    sdl_root = environ.get('SDL_ROOT')
    if sdl_root is not None and not isdir(sdl_root):
        sdl_root = None

    if sdl_root is not None:
        sdl_include = environ.get('SDL_INCLUDE_DIR', join(sdl_root, 'include'))
        sdl_lib = environ.get('SDL_LIB_DIR', join(sdl_root, 'lib'))
    else:
        sdl_include = environ.get('SDL_INCLUDE_DIR')
        sdl_lib = environ.get('SDL_LIB_DIR')
    if sdl_include is not None and not isdir(sdl_include):
        sdl_include = None
    if sdl_lib is not None and not isdir(sdl_lib):
        sdl_lib = None

    sdl = 'SDL2'
    flags = {'include_dirs': [], 'library_dirs': [], 'libraries': []}
    if sdl_lib is None and sdl_include is None:
        flags = pkgconfig('sdl2')
        if not flags:
            flags = pkgconfig('sdl')
            if flags:
                sdl = 'SDL'
    elif sdl_include is not None and not isdir(join(sdl_include, 'SDL2')):
        sdl = 'SDL'
    print('Selecting %s out of (SDL, SDL2)' % sdl)

    sdl_lib = flags.get('library_dirs', []) if sdl_lib is None \
        else [sdl_lib]
    sdl_include = flags.get('include_dirs', []) if sdl_include is None \
        else [join(sdl_include, sdl)]

    library_dirs.extend(sdl_lib)
    include_dirs.extend(sdl_include)
    libraries.append(sdl)


def get_wheel_data():
    data = []
    ff = environ.get('FFMPEG_ROOT')
    if ff:
        if isdir(join(ff, 'bin')):
            data.append(
                ('share/ffpyplayer/ffmpeg/bin', listdir(join(ff, 'bin'))))
        if isdir(join(ff, 'licenses')):
            data.append(
                ('share/ffpyplayer/ffmpeg/licenses',
                 listdir(join(ff, 'licenses'))))
        if exists(join(ff, 'README.txt')):
            data.append(('share/ffpyplayer/ffmpeg', [join(ff, 'README.txt')]))

    sdl = environ.get('SDL_ROOT')
    if sdl:
        if isdir(join(sdl, 'bin')):
            data.append(
                ('share/ffpyplayer/sdl/bin', listdir(join(sdl, 'bin'))))
    return data


mods = [
    'pic', 'threading', 'tools', 'writer', 'player/clock', 'player/core',
    'player/decoder', 'player/frame_queue', 'player/player', 'player/queue']
extra_compile_args = ["-O3", '-fno-strict-aliasing']
c_options['has_sdl2'] = sdl == 'SDL2'

if have_cython:
    mod_suffix = '.pyx'
else:
    mod_suffix = '.c'


print('Generating ffconfig.h')
with open(join('ffpyplayer', 'includes', 'ffconfig.h'), 'wb') as f:
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

#if !defined(_WIN32) && !defined(__APPLE__)
#define NOT_WIN_MAC 1
#else
#define NOT_WIN_MAC 0
#endif

#if defined(_WIN32)
#define WIN_IS_DEFINED 1
#else
#define WIN_IS_DEFINED 0
#endif

''')
    for k, v in c_options.iteritems():
        f.write('#define %s %d\n' % (k.upper(), int(v)))
    f.write('''
#endif
''')

print('Generating ffconfig.pxi')
with open(join('ffpyplayer', 'includes', 'ffconfig.pxi'), 'wb') as f:
    for k, v in c_options.iteritems():
        f.write('DEF %s = %d\n' % (k.upper(), int(v)))

include_dirs.extend(
    [join(abspath(dirname(__file__)), 'ffpyplayer'),
     join(abspath(dirname(__file__)), 'ffpyplayer', 'includes')])
ext_modules = [Extension(
    'ffpyplayer.' + src_file.replace('/', '.'),
    sources=[join('ffpyplayer', *(src_file + mod_suffix).split('/')),
             join('ffpyplayer', 'clib', 'misc.c')],
    libraries=libraries,
    include_dirs=include_dirs,
    library_dirs=library_dirs,
    extra_compile_args=extra_compile_args)
               for src_file in mods]

for e in ext_modules:
    e.cython_directives = {"embedsignature": True}

setup(name='ffpyplayer',
      version=__version__,
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
      packages=['ffpyplayer', 'ffpyplayer.player'],
      data_files=get_wheel_data(),
      cmdclass=cmdclass, ext_modules=ext_modules,
      setup_requires=['cython'])
