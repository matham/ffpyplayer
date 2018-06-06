.. _examples:

********
Examples
********


Converting Image formats
------------------------

:

.. code-block:: python

    from ffpyplayer.pic import Image, SWScale
    w, h = 500, 100
    size = w * h * 3
    buf = bytearray([int(x * 255 / size) for x in range(size)])

    img = Image(plane_buffers=[buf], pix_fmt='rgb24', size=(w, h))
    sws = SWScale(w, h, img.get_pixel_format(), ofmt='yuv420p')

    img2 = sws.scale(img)
    img2.get_pixel_format()
    'yuv420p'
    planes = img2.to_bytearray()
    map(len, planes)
    [50000, 12500, 12500, 0]

.. _dshow-example:

Playing a webcam with DirectShow on windows
-------------------------------------------

One can use :meth:`~ffpyplayer.tools.list_dshow_devices` to get a list of the
devices and their option for playing. For example:

.. code-block:: python

    # see http://ffmpeg.org/ffmpeg-formats.html#Format-Options for rtbufsize
    # lets use the yuv420p, 320x240, 30fps
    # 27648000 = 320*240*3 at 30fps, for 4 seconds.
    # see http://ffmpeg.org/ffmpeg-devices.html#dshow for video_size, and framerate
    lib_opts = {'framerate':'30', 'video_size':'320x240',
    'pixel_format': 'yuv420p', 'rtbufsize':'27648000'}
    ff_opts = {'f':'dshow'}
    player = MediaPlayer('video=Logitech HD Webcam C525:audio=Microphone (HD Webcam C525)',
                         ff_opts=ff_opts, lib_opts=lib_opts)

    while 1:
        frame, val = player.get_frame()
        if val == 'eof':
            break
        elif frame is None:
            time.sleep(0.01)
        else:
            img, t = frame
            print val, t, img.get_pixel_format(), img.get_buffer_size()
            time.sleep(val)
    0.0 264107.429 rgb24 (230400, 0, 0, 0)
    0.0 264108.364 rgb24 (230400, 0, 0, 0)
    0.0790016651154 264108.628 rgb24 (230400, 0, 0, 0)
    0.135997533798 264108.764 rgb24 (230400, 0, 0, 0)
    0.274529457092 264108.897 rgb24 (230400, 0, 0, 0)
    0.272421836853 264109.028 rgb24 (230400, 0, 0, 0)
    0.132406949997 264109.164 rgb24 (230400, 0, 0, 0)
    ...

    # NOTE, by default the output was rgb24. To keep the output format the
    # same as the input, do ff_opts['out_fmt'] = 'yuv420p'

Simple transcoding example
--------------------------

:

.. code-block:: python

    from ffpyplayer.player import MediaPlayer
    from ffpyplayer.writer import MediaWriter
    import time, weakref

    # only video
    ff_opts={'an':True, 'sync':'video'}
    player = MediaPlayer(filename, ff_opts=ff_opts)
    # wait for size to be initialized (todo: add timeout and check for quitting)
    while player.get_metadata()['src_vid_size'] == (0, 0):
        time.sleep(0.01)

    frame_size = player.get_metadata()['src_vid_size']
    # use the same size as the inputs
    out_opts = {'pix_fmt_in':'rgb24', 'width_in':frame_size[0],
                'height_in':frame_size[1], 'codec':'rawvideo',
                'frame_rate':(30, 1)}

    writer = MediaWriter(filename_out, [out_opts])
    while 1:
        frame, val = player.get_frame()
        if val == 'eof':
            break
        elif frame is None:
            time.sleep(0.01)
        else:
            img, t = frame
            writer.write_frame(img=img, pts=t, stream=0)

More complex transcoding example
--------------------------------

:

.. code-block:: python

    from ffpyplayer.player import MediaPlayer
    from ffpyplayer.tools import free_frame_ref
    from ffpyplayer.writer import MediaWriter
    import time, weakref

    # only video, output yuv420p frames
    ff_opts={'an':True, 'sync':'video', 'out_fmt':'yuv420p'}
    player = MediaPlayer(filename, ff_opts=ff_opts)
    # wait for size to be initialized
    while player.get_metadata()['src_vid_size'] == (0, 0):
        time.sleep(0.01)

    frame_size = player.get_metadata()['src_vid_size']
    # use the half the size for the output as the input
    out_opts = {'pix_fmt_in':'yuv420p', 'width_in':frame_size[0],
                'height_in':frame_size[1], 'codec':'rawvideo',
                'frame_rate':(30, 1), 'width_out':frame_size[0] / 2,
                'height_out':frame_size[1] / 2}

    writer = MediaWriter(filename_out, [out_opts])
    while 1:
        frame, val = player.get_frame()
        if val == 'eof':
            break
        elif frame is None:
            time.sleep(0.01)
        else:
            img, t = frame
            writer.write_frame(img=img, pts=t, stream=0)

.. _write-simple:

Writing video to file
---------------------

:

.. code-block:: python

    from ffpyplayer.writer import MediaWriter
    from ffpyplayer.pic import Image

    w, h = 640, 480
    # write at 5 fps.
    out_opts = {'pix_fmt_in':'rgb24', 'width_in':w, 'height_in':h, 'codec':'rawvideo',
                'frame_rate':(5, 1)}
    # write using rgb24 frames into a two stream rawvideo file where the output
    # is half the input size for both streams. Avi format will be used.
    writer = MediaWriter('output.avi', [out_opts] * 2, width_out=w/2,
                         height_out=h/2)

    # Construct images
    size = w * h * 3
    buf = bytearray([int(x * 255 / size) for x in range(size)])
    img = Image(plane_buffers=[buf], pix_fmt='rgb24', size=(w, h))

    buf = bytearray([int((size - x) * 255 / size) for x in range(size)])
    img2 = Image(plane_buffers=[buf], pix_fmt='rgb24', size=(w, h))

    for i in range(20):
        writer.write_frame(img=img, pts=i / 5., stream=0)  # stream 1
        writer.write_frame(img=img2, pts=i / 5., stream=1)  # stream 2

Or force an output format of avi, even though the filename is .mp4.:

.. code-block:: python

    writer = MediaWriter('output.mp4', [out_opts] * 2, fmt='avi',
                          width_out=w/2, height_out=h/2)

.. _write-h264:

Compressing video to h264
-------------------------

Or writing compressed h264 files (notice the file is now only 5KB, while
the above results in a 10MB file):

.. code-block:: python

    from ffpyplayer.writer import MediaWriter
    from ffpyplayer.tools import get_supported_pixfmts, get_supported_framerates
    from ffpyplayer.pic import Image

    # make sure the pixel format and rate are supported.
    print get_supported_pixfmts('libx264', 'rgb24')
    #['yuv420p', 'yuvj420p', 'yuv422p', 'yuvj422p', 'yuv444p', 'yuvj444p', 'nv12', 'nv16']
    print get_supported_framerates('libx264', (5, 1))
    #[]
    w, h = 640, 480
    out_opts = {'pix_fmt_in':'rgb24', 'width_in':w, 'height_in':h, 'codec':'libx264',
                'frame_rate':(5, 1)}

    # use the following libx264 compression options
    lib_opts = {'preset':'slow', 'crf':'22'}
    # set the following metadata (ffmpeg doesn't always support writing metadata)
    metadata = {'title':'Singing in the sun', 'author':'Rat', 'genre':'Animal sounds'}

    # write using yuv420p frames into a two stream h264 codec, mp4 file where the output
    # is half the input size for both streams.
    writer = MediaWriter('output.avi', [out_opts] * 2, fmt='mp4',
                         width_out=w/2, height_out=h/2, pix_fmt_out='yuv420p',
                         lib_opts=lib_opts, metadata=metadata)

    # Construct images
    size = w * h * 3
    buf = bytearray([int(x * 255 / size) for x in range(size)])
    img = Image(plane_buffers=[buf], pix_fmt='rgb24', size=(w, h))

    buf = bytearray([int((size - x) * 255 / size) for x in range(size)])
    img2 = Image(plane_buffers=[buf], pix_fmt='rgb24', size=(w, h))

    for i in range(20):
        writer.write_frame(img=img, pts=i / 5., stream=0)  # stream 1
        writer.write_frame(img=img2, pts=i / 5., stream=1)  # stream 2
