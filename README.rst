FFPyPlayer is a python binding for the FFmpeg library for playing and writing
media files.

For more information: http://matham.github.io/ffpyplayer/index.html

To install: http://matham.github.io/ffpyplayer/installation.html

.. image:: https://travis-ci.org/matham/ffpyplayer.svg?branch=master
    :target: https://travis-ci.org/matham/ffpyplayer
    :alt: TravisCI status

.. image:: https://ci.appveyor.com/api/projects/status/nfl6tyiwks26ngyu/branch/master?svg=true
    :target: https://ci.appveyor.com/project/matham/ffpyplayer/branch/master
    :alt: Appveyor status

.. image:: https://img.shields.io/pypi/pyversions/ffpyplayer.svg
    :target: https://pypi.python.org/pypi/ffpyplayer/
    :alt: Supported Python versions

.. image:: https://img.shields.io/pypi/v/ffpyplayer.svg
    :target: https://pypi.python.org/pypi/ffpyplayer/
    :alt: Latest Version on PyPI

.. warning::

    Although the ffpyplayer source code is licensed under the LGPL, the ffpyplayer wheels
    for Windows and linux on PYPI are distributed under the GPL because the included FFmpeg binaries
    were compiled with GPL options.

    If you want to use it under the LGPL you need to compile FFmpeg yourself with the correct options.

    Similarly, the wheels bundle openssl for online camera support. However, releases are not made
    for every openssl release, so it is recommended that you compile ffpyplayer yourself if security
    is a issue.

Usage example
-------------

Playing a file:

.. code-block:: python

    >>> from ffpyplayer.player import MediaPlayer
    >>> import time

    >>> player = MediaPlayer(filename)
    >>> val = ''
    >>> while val != 'eof':
    ...     frame, val = player.get_frame()
    ...     if val != 'eof' and frame is not None:
    ...         img, t = frame
    ...         # display img

Writing a video file:

.. code-block:: python

    >>> from ffpyplayer.writer import MediaWriter
    >>> from ffpyplayer.pic import Image

    >>> w, h = 640, 480
    >>> # write at 5 fps.
    >>> out_opts = {'pix_fmt_in':'rgb24', 'width_in':w, 'height_in':h,
    ...     'codec':'rawvideo', 'frame_rate':(5, 1)}
    >>> writer = MediaWriter('output.avi', [out_opts])

    >>> # Construct image
    >>> size = w * h * 3
    >>> buf = bytearray([int(x * 255 / size) for x in range(size)])
    >>> img = Image(plane_buffers=[buf], pix_fmt='rgb24', size=(w, h))

    >>> for i in range(20):
    ...     writer.write_frame(img=img, pts=i / 5., stream=0)

Converting images:

.. code-block:: python

    >>> from ffpyplayer.pic import Image, SWScale
    >>> w, h = 500, 100
    >>> size = w * h * 3
    >>> buf = bytearray([int(x * 255 / size) for x in range(size)])

    >>> img = Image(plane_buffers=[buf], pix_fmt='rgb24', size=(w, h))
    >>> sws = SWScale(w, h, img.get_pixel_format(), ofmt='yuv420p')

    >>> img2 = sws.scale(img)
    >>> img2.get_pixel_format()
    'yuv420p'
    >>> planes = img2.to_bytearray()
    >>> map(len, planes)
    [50000, 12500, 12500, 0]
