.. _examples:

********
Examples
********


Converting Image formats
------------------------

::

    from ffpyplayer.pic import Image, SWScale
    w, h = 500, 100
    size = w * h * 3
    buf = [int(x * 255 / size) for x in range(size)]
    buf = ''.join(map(chr, buf))

    img = Image(plane_buffers=[buf], pix_fmt='rgb24', size=(w, h))
    sws = SWScale(w, h, img.get_pixel_format(), ofmt='yuv420p')

    img2 = sws.scale(img)
    img2.get_pixel_format()
    'yuv420p'
    planes = img2.to_bytearray()
    map(len, planes)
    [50000, 12500, 12500, 0]

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
    # wait for size to be initialized (add timeout and check for callback quitting)
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

::

    from ffpyplayer.player import MediaPlayer
    from ffpyplayer.tools import free_frame_ref
    from ffpyplayer.writer import MediaWriter
    import time, weakref

    def callback(selector, value):
        if selector == 'quit':
            print 'quitting'

    # only video, output yuv420p frames
    ff_opts={'an':True, 'sync':'video', 'out_fmt':'yuv420p'}
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
            img, t = frame
            writer.write_frame(img=img, pts=t, stream=0)

Compressing video to h264
-------------------------

::

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
    buf = [int(x * 255 / size) for x in range(size)]
    buf = ''.join(map(chr, buf))
    img = Image(plane_buffers=[buf], pix_fmt='rgb24', size=(w, h))

    buf = [int((size - x) * 255 / size) for x in range(size)]
    buf = ''.join(map(chr, buf))
    img2 = Image(plane_buffers=[buf], pix_fmt='rgb24', size=(w, h))

    for i in range(20):
        writer.write_frame(img=img, pts=i / 5., stream=0)  # stream 1
        writer.write_frame(img=img2, pts=i / 5., stream=1)  # stream 2
