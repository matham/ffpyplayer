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
    player = MediaPlayer(r'C:\FFmpeg\suz.mkv', vid_sink=weakref.ref(callback),
                         ff_opts=ff_opts)
    # wait for size to be initialized
    while player.get_metadata()['src_vid_size'] == (0, 0):
        time.sleep(0.01)

    frame_size = player.get_metadata()['src_vid_size']
    # use the same size as the inputs
    out_opts = {'pix_fmt_in':'rgb24', 'width_in':frame_size[0],
                'height_in':frame_size[1], 'codec':'rawvideo',
                'frame_rate':(30, 1)}

    writer = MediaWriter(r'C:\FFmpeg\output.avi', [out_opts])
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
    player = MediaPlayer(r'C:\FFmpeg\suz.mkv', vid_sink=weakref.ref(callback),
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

    writer = MediaWriter(r'C:\FFmpeg\output.avi', [out_opts])
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
