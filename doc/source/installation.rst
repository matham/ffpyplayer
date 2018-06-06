.. _install:

************
Installation
************

Using binary wheels
-------------------

On windows 7+ and linux, compiled ffpyplayer binaries can be installed for python 2.7 and 3.3+,
on either a 32 or 64 bit system using::

    pip install ffpyplayer

.. warning::

    Although the ffpyplayer source code is licensed under the LGPL, the ffpyplayer wheels
    on PYPI are distributed under the GPL because the  FFmpeg binaries
    are GPL'd. For LGPL builds you can compile FFmpeg yourself using LGPL options.

For other OSs or to compile with master see below.

Compiling
---------

Requirements
============

To compile ffpyplayer we need:

    * Cython (``pip install --upgrade cython``).
    * A c compiler e.g. MinGW  (``pip install mingwpy`` on windows).
    * SDL2 or SDL1.2 (SDL1.2 is not recommended). See :ref:`compille` for how to get it.
    * SDL2_mixer If wanting to play multiple audio files simultaneously (``USE_SDL2_MIXER`` must be set). See :ref:`compille` for how to get it.
    * A recent (2.x+, has been tested with 2.8) FFmpeg compiled with ``--enable-shared``.
      See :ref:`compille` for how to get it.

Compiling ffpyplayer
====================

On linux or mac, if the SDL2/SDL2_mixer or FFmpeg package config (.pc) files are on the path exported
in ``PKG_CONFIG_PATH`` the library and header files will automatically be found.

Otherwise, or if compiling on Windows, the following environmental variables are required.

    * ``SDL_LIB_DIR`` and ``FFMPEG_LIB_DIR`` should point to a folder which contains the
      SDL and FFmpeg library files (*.a files), respectively.
    * ``FFMPEG_INCLUDE_DIR`` should point to a directory which contains the FFmpeg header files.
    * ``SDL_INCLUDE_DIR`` should point to a directory containg the SDL headers. For SDL2,
      this directory contains a SDL2 named directory with all the headers.

In addition, directories containing the SDL and FFmpeg shared libraries, *.dlls on Windows
and *.so on Linux/Mac, need to be added to the PATH.

You can also select the FFmpeg libraries to be used by defining values for CONFIG_XXX.
For example, CONFIG_AVFILTER=0 will disable inclusion of the FFmpeg avfilter libraries.
See setup.py for all the available flags.

To use SDL2_mixer, which is required when multiple audio files are to be played
simultaneously (or even when they are open at the same time) environment variable ``USE_SDL2_MIXER``
must be set to 1 when compiling. SDL2_mixer binaries and headers must also be available.

Finally, run::

    pip install ffpyplayer

Or to install master, do::

    pip install https://github.com/matham/ffpyplayer/archive/master.zip

If you have a local zip with the ffpyplayer source code you can also run ``make``
or ``python setup.py build_ext --inplace`` to compile.

You should now be able to import ffpyplayer with ``import ffpyplayer``.

.. _compille

SDL and Compiling FFmpeg
------------------------

To use ffpyplayer, the compiled FFmpeg and SDL shared libraries must be available. Following are
instructions for the various OSs.

Windows
=======

You can get pre-compiled FFmpeg libaries from http://ffmpeg.zeranoe.com/builds/. You need
both the shared (which contains the .a files and headers) and the dev (which contains the dlls)
downloads.

You can download SDL2 from https://www.libsdl.org/release/. 2.0.4 is the most recent
`version <https://www.libsdl.org/release/SDL2-devel-2.0.4-mingw.tar.gz>`_.

You can download SDL2_mixer from https://www.libsdl.org/projects/SDL_mixer/. 2.0.1 is the most recent
`version <https://www.libsdl.org/projects/SDL_mixer/release/SDL2_mixer-devel-2.0.1-mingw.tar.gz>`_.

OSX
===

You can get both FFmpeg and SDL2 using brew. You can install them using::

    brew update
    brew install sdl2
    brew install sdl2_mixer
    brew install ffmpeg --with-freetype --with-libass --with-libvorbis --with-libvpx --with-libmp3lame --with-x264 --with-libtheora

This automatically installs the package config (*.pc) files.

Ubuntu
======

Follow the instructions at https://trac.ffmpeg.org/wiki/CompilationGuide/Ubuntu to compile FFMpeg.
However, those instructions detail how to build the static version. But we need the shared
version. This means that ``--enable-shared`` and ``--extra-cflags="-fPIC"`` need to be added
when compiling FFmpeg **AND** its dependencies. And if present, ``--disable-shared`` or
``--enable-static`` must be removed.

Following that guide, ``export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$HOME/ffmpeg_build/lib`` also needs
to be executed initially for the compiled binaries to be found.

To get SDL2, do the following::

    sudo apt-get update
    sudo apt-get -y install libsdl2-dev libsdl2-mixer-dev python-dev

You can find a complete minimal example of compiling ffpyplayer on Ubuntu
`here <https://github.com/matham/ffpyplayer/blob/master/.travis.yml#L20>`_.
