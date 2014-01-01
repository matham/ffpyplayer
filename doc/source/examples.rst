.. _examples:

********
Examples
********

Simple transcoding example
--------------------------

::

    from ffpyplayer.player import MediaPlayer
    from ffpyplayer.writer import MediaWriter
    import time, weakref

    def callback(selector, value):
        if selector == 'quit':
            print 'quitting'

    # only video
    ff_opts={'an':True, 'sync':'video'}
    player = MediaPlayer(filename, callback=weakref.ref(callback),
                         ff_opts=ff_opts)
    # wait for size to be initialized
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
            writer.write_frame(frame[3], 0, buffer=frame[0])

More complex transcoding example
--------------------------------

::

    from ffpyplayer.player import MediaPlayer
    from ffpyplayer.tools import free_frame_ref
    from ffpyplayer.writer import MediaWriter
    import time, weakref

    def callback(selector, value):
        if selector == 'quit':
            print 'quitting'

    # only video
    # output yuv420p frames, and don't copy
    ff_opts={'an':True, 'sync':'video', 'use_ref':True, 'out_fmt':'yuv420p'}
    player = MediaPlayer(filename, callback=weakref.ref(callback),
                         ff_opts=ff_opts)
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
            writer.write_frame(frame[3], 0, frame_ref=frame[0][0])
            free_frame_ref(frame[0][0])

Contrast the difference in time it takes the above examples to run and the resulting
filesizes to see how much improvement occurs when data is not copied, and a yuv
pixel format is used.

Compressing video to h264
-------------------------

::

    from ffpyplayer.writer import MediaWriter
    from ffpyplayer.tools import get_supported_pixfmts, get_supported_framerates

    # make sure the pixel format and rate are supported.
    print get_supported_pixfmts('libx264', 'rgb24')
    ['yuv420p', 'yuvj420p', 'yuv422p', 'yuvj422p', 'yuv444p', 'yuvj444p', 'nv12', 'nv16']
    print get_supported_framerates('libx264', (5, 1))
    []
    w = 640
    h = 480
    # use the half the size for the output as the input
    out_opts = {'pix_fmt_in':'rgb24', 'width_in':w, 'height_in':h, 'codec':'libx264',
                'frame_rate':(5, 1)}
    # write using yuv420p frames into a two stream h264 codec, mp4 file where the output
    # is half the input size for both streams.

    # use the following libx264 compression options
    lib_opts = {'preset':'slow', 'crf':'22'}
    # set the following metadata (ffmpeg doesn't always support writing metadata)
    metadata = {'title':'Singing in the sun', 'author':'Rat', 'genre':'Animal sounds'}

    writer = MediaWriter(filename, [out_opts] * 2, fmt='mp4',
                         width_out=w/2, height_out=h/2, pix_fmt_out='yuv420p',
                         lib_opts=lib_opts, metadata=metadata)
    size = w * h * 3
    for i in range(20):
        buf = [int(x * 255 / size) for x in range(size)]
        buf = ''.join(map(chr, buf))
        writer.write_frame(pts=i / 5., stream=0, buffer=buf)

        buf = [int((size - x) * 255 / size) for x in range(size)]
        buf = ''.join(map(chr, buf))
        writer.write_frame(pts=i / 5., stream=1, buffer=buf)
