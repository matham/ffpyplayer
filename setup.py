from os.path import join, exists, isdir, dirname, abspath
from os import environ, listdir, mkdir
from distutils.command.build_ext import build_ext
import sys
import ffpyplayer

try:
    from setuptools import setup, Extension
    print('Using setuptools')
except ImportError:
    from distutils.core import setup
    from distutils.extension import Extension
    print('Using distutils')


# Determine on which platform we are
platform = sys.platform

# detect Python for android project (http://github.com/kivy/python-for-android)
# or kivy-ios (http://github.com/kivy/kivy-ios)
ndkplatform = environ.get('NDKPLATFORM')
if ndkplatform is not None and environ.get('LIBLINK'):
    platform = 'android'
kivy_ios_root = environ.get('KIVYIOSROOT', None)
if kivy_ios_root is not None:
    platform = 'ios'


# There are issues with using cython at all on some platforms;
# exclude them from using or declaring cython.

# This determines whether Cython specific functionality may be used.
can_use_cython = True
# This sets whether or not Cython gets added to setup_requires.
declare_cython = False

if platform in ('ios', 'android'):
    # NEVER use or declare cython on these platforms
    print('Not using cython on %s' % platform)
    can_use_cython = False
else:
    declare_cython = True

src_path = build_path = dirname(__file__)

# select which ffmpeg libraries will be available
c_options = {
    # If true, filters will be used'
    'config_avfilter': True,
    'config_avdevice': True,
    'config_swscale': True,
    'config_rtsp_demuxer': True,
    'config_mmsh_protocol': True,
    'config_postproc':True,
    # whether sdl is included as an option
    'config_sdl': True, # not implemented yet
    'has_sdl2': False,
    'use_sdl2_mixer': False,
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
    raise Exception(
        'At least one of config_avfilter and config_swscale must be enabled.')

# if c_options['config_avfilter'] and ((not c_options['config_postproc']) or \
#     not c_options['config_swscale']):
#     raise Exception(
#         'config_avfilter requires the postproc and swscale binaries.')
c_options['config_avutil'] = c_options['config_avutil'] = True
c_options['config_avformat'] = c_options['config_swresample'] = True


class FFBuildExt(build_ext, object):
    
    def __new__(cls, *a, **kw):
        # Note how this class is declared as a subclass of distutils
        # build_ext as the Cython version may not be available in the
        # environment it is initially started in. However, if Cython
        # can be used, setuptools will bring Cython into the environment
        # thus its version of build_ext will become available.
        # The reason why this is done as a __new__ rather than through a
        # factory function is because there are distutils functions that check
        # the values provided by cmdclass with issublcass, and so it would
        # result in an exception.
        # The following essentially supply a dynamically generated subclass
        # that mix in the cython version of build_ext so that the
        # functionality provided will also be executed.
        if can_use_cython:
            from Cython.Distutils import build_ext as cython_build_ext
            build_ext_cls = type(
                'FFBuildExt', (FFBuildExt, cython_build_ext), {})
            return super(FFBuildExt, cls).__new__(build_ext_cls)
        else:
            return super(FFBuildExt, cls).__new__(cls)

    def finalize_options(self):
        retval = super(FFBuildExt, self).finalize_options()
        global build_path
        if (self.build_lib is not None and exists(self.build_lib) and
                not self.inplace):
            build_path = self.build_lib
        return retval

    def build_extensions(self):
        compiler = self.compiler.compiler_type
        if compiler == 'msvc':
            args = []
        else:
            args = ["-O3", '-fno-strict-aliasing', '-Wno-error']
        for ext in self.extensions:
            ext.extra_compile_args = args
        super(FFBuildExt, self).build_extensions()


cmdclass = {'build_ext': FFBuildExt}


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


def get_paths(name):
    root = environ.get('{}_ROOT'.format(name))
    if root is not None and not isdir(root):
        root = None

    if root is not None:
        include = environ.get('{}_INCLUDE_DIR'.format(name), join(root, 'include'))
        lib = environ.get('{}_LIB_DIR'.format(name), join(root, 'lib'))
    else:
        include = environ.get('{}_INCLUDE_DIR'.format(name))
        lib = environ.get('{}_LIB_DIR'.format(name))

    if include is not None and not isdir(include):
        include = None
    if lib is not None and not isdir(lib):
        lib = None
    return lib, include

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
    # enable python-for-android/py4a compilation

    # ffmpeg:
    ffmpeg_lib, ffmpeg_include = get_paths('FFMPEG')
    libraries.extend([
        'avcodec', 'avdevice', 'avfilter', 'avformat',
        'avutil', 'swscale', 'swresample', 'postproc', 'm'
    ])
    library_dirs.append(ffmpeg_lib)
    include_dirs.append(ffmpeg_include)

    # sdl:
    sdl_lib, sdl_include = get_paths('SDL')
    if sdl_lib and sdl_include:
        sdl = 'SDL2'
        libraries.append(sdl)
        library_dirs.append(sdl_lib)
        include_dirs.append(sdl_include)
    else:  # old toolchain
        sdl = 'sdl'
        libraries.append(sdl)
        if sdl_lib: library_dirs.append(sdl_lib)
        if sdl_include: include_dirs.append(sdl_include)

    # sdl2 mixer:
    c_options['use_sdl2_mixer'] = c_options['use_sdl2_mixer'] and sdl == 'SDL2'
    if c_options['use_sdl2_mixer']:
        _, mixer_include = get_paths('SDL2_MIXER')
        libraries.append('SDL2_mixer')
        include_dirs.append(mixer_include)

else:

    # ffmpeg
    objects = ['avcodec', 'avdevice', 'avfilter', 'avformat',
                   'avutil', 'swscale', 'swresample', 'postproc']
    for libname in objects[:]:
        for key, val in c_options.items():
            if key.endswith(libname) and not val:
                objects.remove(libname)
                break

    ffmpeg_lib, ffmpeg_include = get_paths('FFMPEG')
    flags = {'include_dirs': [], 'library_dirs': [], 'libraries': []}
    if ffmpeg_lib is None and ffmpeg_include is None:
        flags = pkgconfig(*['lib' + l for l in objects])

    library_dirs = flags.get('library_dirs', []) if ffmpeg_lib is None \
        else [ffmpeg_lib]
    include_dirs = flags.get('include_dirs', []) if ffmpeg_include is None \
        else [ffmpeg_include]
    libraries = objects[:]

    # sdl
    sdl_lib, sdl_include = get_paths('SDL')

    sdl = 'SDL2'
    flags = {}
    if sdl_lib is None and sdl_include is None:
        flags = pkgconfig('sdl2')
        if not flags:
            flags = pkgconfig('sdl')
            if flags:
                sdl = 'SDL'
    elif sdl_include is not None and not isdir(join(sdl_include, 'SDL2')):
        sdl = 'SDL'
    print('Selecting %s out of (SDL, SDL2)' % sdl)

    sdl_libs = flags.get('library_dirs', []) if sdl_lib is None \
        else [sdl_lib]
    sdl_includes = flags.get('include_dirs', []) if sdl_include is None \
        else [join(sdl_include, sdl)]

    library_dirs.extend(sdl_libs)
    include_dirs.extend(sdl_includes)
    libraries.extend(flags.get('libraries', [sdl]))

    c_options['use_sdl2_mixer'] = c_options['use_sdl2_mixer'] and sdl == 'SDL2'
    if c_options['use_sdl2_mixer']:
        flags = {}
        if sdl_lib is None and sdl_include is None:
            flags = pkgconfig('SDL2_mixer')

        library_dirs.extend(flags.get('library_dirs', []))
        include_dirs.extend(flags.get('include_dirs', []))
        libraries.extend(flags.get('libraries', ['SDL2_mixer']))


def get_wheel_data():
    data = []
    ff = environ.get('FFMPEG_ROOT')
    if ff:
        if isdir(join(ff, 'bin')):
            data.append(('share/ffpyplayer/ffmpeg/bin', [
                join(ff, 'bin', f) for f in listdir(join(ff, 'bin'))]))
        if isdir(join(ff, 'licenses')):
            data.append(('share/ffpyplayer/ffmpeg/licenses', [
                join(ff, 'licenses', f) for
                f in listdir(join(ff, 'licenses'))]))
        if exists(join(ff, 'README.txt')):
            data.append(('share/ffpyplayer/ffmpeg', [join(ff, 'README.txt')]))

    sdl = environ.get('SDL_ROOT')
    if sdl:
        if isdir(join(sdl, 'bin')):
            data.append(
                ('share/ffpyplayer/sdl/bin', [
                    join(sdl, 'bin', f) for f in listdir(join(sdl, 'bin'))]))
    return data


mods = [
    'pic', 'threading', 'tools', 'writer', 'player/clock', 'player/core',
    'player/decoder', 'player/frame_queue', 'player/player', 'player/queue']
c_options['has_sdl2'] = sdl == 'SDL2'
c_options['use_sdl2_mixer'] = c_options['use_sdl2_mixer'] and sdl == 'SDL2'


if can_use_cython:
    mod_suffix = '.pyx'
else:
    mod_suffix = '.c'

print('Generating ffconfig.h')
if not exists(join(src_path, 'ffpyplayer', 'includes')):
    mkdir(join(src_path, 'ffpyplayer', 'includes'))
with open(join(src_path, 'ffpyplayer', 'includes', 'ffconfig.h'), 'w') as f:
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
    for k, v in c_options.items():
        f.write('#define %s %d\n' % (k.upper(), int(v)))
    f.write('''
#endif
''')

print('Generating ffconfig.pxi')
with open(join(src_path, 'ffpyplayer', 'includes', 'ffconfig.pxi'), 'w') as f:
    for k, v in c_options.items():
        f.write('DEF %s = %d\n' % (k.upper(), int(v)))

include_dirs.extend(
    [join(src_path, 'ffpyplayer'),
     join(src_path, 'ffpyplayer', 'includes')])
ext_modules = [Extension(
    'ffpyplayer.' + src_file.replace('/', '.'),
    sources=[join(src_path, 'ffpyplayer', *(src_file + mod_suffix).split('/')),
             join(src_path, 'ffpyplayer', 'clib', 'misc.c')],
    libraries=libraries,
    include_dirs=include_dirs,
    library_dirs=library_dirs)
               for src_file in mods]

for e in ext_modules:
    e.cython_directives = {"embedsignature": True}

with open('README.rst') as fh:
    long_description = fh.read()
    
setup_requires = []
if declare_cython:
    setup_requires.append('cython')

setup(name='ffpyplayer',
      version=ffpyplayer.__version__,
      author='Matthew Einhorn',
      license='LGPL3',
      description='A cython implementation of an ffmpeg based player.',
      url='http://matham.github.io/ffpyplayer/',
      long_description=long_description,
      classifiers=['License :: OSI Approved :: GNU Lesser General Public License v3 (LGPLv3)',
                   'Topic :: Multimedia :: Video',
                   'Topic :: Multimedia :: Video :: Display',
                   'Topic :: Multimedia :: Sound/Audio :: Players',
                   'Topic :: Multimedia :: Sound/Audio :: Players :: MP3',
                   'Programming Language :: Python :: 3.5',
                   'Programming Language :: Python :: 3.6',
                   'Programming Language :: Python :: 3.7',
                   'Operating System :: MacOS :: MacOS X',
                   'Operating System :: Microsoft :: Windows',
                   'Operating System :: POSIX :: BSD :: FreeBSD',
                   'Operating System :: POSIX :: Linux',
                   'Intended Audience :: Developers'],
      packages=['ffpyplayer', 'ffpyplayer.player', 'ffpyplayer.tests'],
      package_data={'ffpyplayer': ['clib/misc.h']},
      data_files=get_wheel_data(),
      cmdclass=cmdclass, ext_modules=ext_modules,
      setup_requires=setup_requires)

