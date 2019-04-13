.. _install:

************
Installation
************

Using binary wheels
-------------------

On windows 7+ (64 or 32 bit) and linux (64 bit), ffpyplayer wheels can be installed for
python 3.5+ using::

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
    * A c compiler e.g. gcc or MSVC.
    * SDL2 or SDL1.2 (SDL1.2 is not recommended). See :ref:`compille` for how to get it.
    * SDL2_mixer If wanting to play multiple audio files simultaneously (``USE_SDL2_MIXER`` must be set). See :ref:`compille` for how to get it.
    * A recent (2.x+, has been tested with 2.8) FFmpeg compiled with ``--enable-shared``.
      See :ref:`compille` for how to get it.

Compiling ffpyplayer
====================

* Download or compile FFMpeg and SDL2 as shown below and set the appropriate environment variables as needed.
* Install Cython with e.g.::

      pip install --upgrade cython

* You can select the FFmpeg libraries to be used by defining values for CONFIG_XXX.
  For example, CONFIG_AVFILTER=0 will disable inclusion of the FFmpeg avfilter libraries.
  See setup.py for all the available flags.
* To use SDL2_mixer, which is required when multiple audio files are to be played
  simultaneously (or even when they are open at the same time) environment variable ``USE_SDL2_MIXER``
  must be set to 1 when compiling. SDL2_mixer binaries and headers must also be available.
* Finally, run::

      pip install ffpyplayer

  Or to install master, do::

      pip install https://github.com/matham/ffpyplayer/archive/master.zip

  If you have a local directory with the ffpyplayer source code. To compile, you can run within that directory
  * ``make`` on linux, or
  * ``python setup.py build_ext --inplace``, or
  * ``pip install -e .`` to also properly install it.

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

* If there's a root directory containing a ``include`` and ``lib`` directory, each containing the header
  and compiled binaries, respectively, then ``FFMPEG_ROOT`` and ``SDL_ROOT`` can be set to these
  root directories for ffmpeg and sdl, respectively. Otherwise,
* ``SDL_LIB_DIR`` and ``FFMPEG_LIB_DIR`` should point to a folder which contains the
  SDL and FFmpeg compiled shared libraries (*.dll), respectively.
* ``FFMPEG_INCLUDE_DIR`` should point to a directory which contains the FFmpeg header files.
* ``SDL_INCLUDE_DIR`` should point to a directory containg the SDL headers. For SDL2,
  this directory contains a SDL2 named directory with all the headers.

In addition, directories containing the SDL and FFmpeg shared libraries (*.dll) need to be added to the PATH.

OSX
===

You can get both FFmpeg and SDL2 using brew. You can install them using::

    brew update
    brew install sdl2 sdl2_mixer ffmpeg

Otherwise, follow the Linux instructions.

Linux
======

Ubuntu 18.04
~~~~~~~~~~~~

On Ubuntu 18.04, the following command will install the python, ffmpeg, and sdl2 dependencies::

    sudo apt install ffmpeg libavcodec-dev libavdevice-dev libavfilter-dev libavformat-dev \
    libavutil-dev libswscale-dev libswresample-dev libpostproc-dev libsdl2-dev libsdl2-2.0-0 \
    libsdl2-mixer-2.0-0 libsdl2-mixer-dev python3-dev

Other Linux platforms
~~~~~~~~~~~~~~~~~~~~~~

FFMpeg
^^^^^^^

Follow the instructions at https://trac.ffmpeg.org/wiki/CompilationGuide/Ubuntu to compile FFMpeg.
However, those instructions detail how to build the static version. We need the shared
version. This means that ``--enable-shared`` and ``--extra-cflags="-fPIC"`` need to be added
when compiling FFmpeg **AND** its dependencies. And if present, ``--disable-shared`` or
``--enable-static`` must be removed.

Following that guide, ``export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$HOME/ffmpeg_build/lib`` also needs
to be executed for the compiled binaries to be found.

SDL2
^^^^^

SDL2 can usually be gotten from the package manager, e.g. in Ubuntu 16.04 you can do the following::

    sudo apt-get update
    sudo apt-get -y install libsdl2-dev libsdl2-mixer-dev

Python Headers
^^^^^^^^^^^^^^^

The Python headers are required for compilation, on Ubuntu you can get it with::

    sudo apt-get install python3-dev

For either ffmpeg or sdl2 if manually compiled, ``PKG_CONFIG_PATH`` will need to be set to the path
containing the generated `*.pc` files and ``pkg-config`` will need to be available. *Otherwise,* if
installed to a non-standard location, the paths to the compiled shared libraries and headers will need to be set with

* If there's a root directory containing a ``include`` and ``lib`` directory, each containing the header
  and compiled binaries, respectively, then ``FFMPEG_ROOT`` and ``SDL_ROOT`` can be set to these
  root directories for ffmpeg and sdl, respectively. Otherwise,
* ``SDL_LIB_DIR`` and ``FFMPEG_LIB_DIR`` should point to a folder which contains the
  SDL and FFmpeg compiled shared libraries (*.so), respectively.
* ``FFMPEG_INCLUDE_DIR`` should point to a directory which contains the FFmpeg header files.
* ``SDL_INCLUDE_DIR`` should point to a directory containg the SDL headers. For SDL2,
  this directory contains a SDL2 named directory with all the headers.

In addition, directories containing the SDL and FFmpeg shared libraries (*.so) need to be added to the PATH.

You can find a complete minimal example of compiling ffpyplayer on Ubuntu
`here <https://github.com/matham/ffpyplayer/blob/master/.travis.yml#L20>`_.
A more complete example used to build the wheels is
`here <https://github.com/matham/ffpyplayer/blob/master/.travis/build-wheels.sh>`_.

