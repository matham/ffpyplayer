.. _install:

************
Installation
************

Requirements
------------

Before installing ffpyplayer you need the following software:

    * A recent version of cython.
    * A c compiler e.g. MinGW, or visual studio.
    * SDL1.2 or SDL2. There must be a directory containing
      a lib and include directory. The lib directory contains the .a files, while
      the include directory contains a folder called either SDL or SDL2 which in turn
      contains the SDL headers. We identify whether SDL or SDL2 is available based
      on the name of this directory in include.
      Finally, the main directory also contains a bin directory which is used at runtime
      (if it's defined) to search for the shared libraries (e.g. .dll on Windows)
      if they are not already on the path.

      Finally in the environment, a variable called SDL_ROOT must point to the
      top level directory.
    * A recent compiled shared FFmpeg. ffpyplayer defines a variable called
      _ffmpeg_git which is the version of ffmpeg git that it has been tested with.
      A version of FFmpeg that is newer than Nov 2013 is likely required.

      Similar to SDL, there must be a directory containing a lib and include directory
      and bin directory if the shared libraries are not on the system path.
      The lib directory contains the .a files while the include directory contains the
      FFmpeg public API header files (e.g. libavcodec/avcodec.h).

      Finally in the environment, a variable called FFMPEG_ROOT must point to the
      top level directory.

      Autodetection is currently not available.

Installation
------------

After setting up the requirements download ffpyplayer from github and run
python setup.py build_ext --inplace. Before running, you have the option to
select which FFmpeg libraries are to be used by defining values for CONFIG variables
in the environment. For example, CONFIG_AVFILTER=0 will not use the FFmpeg
avfilter libraries. See setup.py for all the available flags.

To test, there's a file in the top level called test.py. To use it,
you need to pass as the first command line argument the path to a media file
that will be played.
