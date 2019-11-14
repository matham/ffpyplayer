import time
import math
import pytest


def get_image(w, h):
    from ffpyplayer.pic import Image

    # Construct images
    size = w * h * 3
    buf = bytearray([int(x * 255 / size) for x in range(size)])
    img = Image(plane_buffers=[buf], pix_fmt='rgb24', size=(w, h))
    return img


def get_gray_image_with_val(w, h, val):
    from ffpyplayer.pic import Image

    # Construct images
    size = w * h
    buf = bytearray([int(val)] * size)
    buf2 = bytearray([0] * size)
    img = Image(plane_buffers=[buf, buf2], pix_fmt='gray', size=(w, h))
    return img


def verify_frames(filename, timestamps, frame_vals=None):
    from ffpyplayer.player import MediaPlayer
    error = [None, ]

    def callback(selector, value):
        if selector.endswith('error'):
            error[0] = selector, value

    player = MediaPlayer(filename, callback=callback)

    read_timestamps = set()
    try:
        i = -1
        while not error[0]:
            frame, val = player.get_frame()
            if val == 'eof':
                break
            if val == 'paused':
                raise ValueError('Got paused')
            elif frame is None:
                time.sleep(0.01)
            else:
                img, t = frame
                print(i, t)
                if i < 0:
                    i += 1
                    continue

                print(i, t, timestamps[i])
                read_timestamps.add(t)
                assert math.isclose(t, timestamps[i], rel_tol=.1)

                if frame_vals:
                    assert frame_vals[i] == img.to_bytearray()[0][0]

                i += 1
    finally:
        player.close_player()

    if error[0] is not None:
        raise Exception('{}: {}'.format(*error[0]))

    assert len(timestamps) - 1 == i
    assert len(read_timestamps) == i


def test_write_streams(tmp_path):
    from ffpyplayer.writer import MediaWriter
    from ffpyplayer.tools import get_supported_pixfmts, get_supported_framerates
    from ffpyplayer.pic import Image
    from ffpyplayer.tools import get_codecs
    fname = str(tmp_path / 'test_video.avi')

    lib_opts = {}
    codec = 'rawvideo'
    if 'libx264' in get_codecs(encode=True, video=True):
        codec = 'libx264'
        lib_opts = {'preset': 'slow', 'crf': '22'}

    w, h = 640, 480
    out_opts = {
        'pix_fmt_in': 'rgb24', 'width_in': w, 'height_in': h,
        'codec': codec, 'frame_rate': (5, 1)}

    metadata = {
        'title': 'Singing in the sun', 'author': 'Rat',
        'genre': 'Animal sounds'}
    writer = MediaWriter(fname, [out_opts] * 2, fmt='mp4',
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
    writer.close()


@pytest.mark.parametrize('fmt', [('mkv', 'matroska'), ('avi', 'avi')])
def test_write_correct_frame_rate(tmp_path, fmt):
    from ffpyplayer.writer import MediaWriter
    fname = str(tmp_path / 'test_frame.') + fmt[0]

    w, h = 64, 64
    out_opts = {
        'pix_fmt_in': 'gray', 'width_in': w, 'height_in': h,
        'codec': 'rawvideo', 'frame_rate': (2997, 100)}

    writer = MediaWriter(fname, [out_opts], fmt=fmt[1])

    timestamps = []
    image_vals = []
    for i in range(20):
        timestamps.append(i / 29.97)
        image_vals.append(i * 5)

        writer.write_frame(
            img=get_gray_image_with_val(w, h, i * 5), pts=i / 29.97, stream=0)
    writer.close()

    verify_frames(fname, timestamps, image_vals)


@pytest.mark.parametrize('fmt', [('mkv', 'matroska'), ('avi', 'avi')])
def test_write_larger_than_frame_rate(tmp_path, fmt):
    from ffpyplayer.writer import MediaWriter
    fname = str(tmp_path / 'test_frame.') + fmt[0]

    w, h = 64, 64
    out_opts = {
        'pix_fmt_in': 'gray', 'width_in': w, 'height_in': h,
        'codec': 'rawvideo', 'frame_rate': (15, 1)}

    writer = MediaWriter(fname, [out_opts], fmt=fmt[1])

    timestamps = []
    image_vals = []
    for i in range(20):
        timestamps.append(i)
        image_vals.append(i * 5)

        writer.write_frame(
            img=get_gray_image_with_val(w, h, i * 5), pts=i, stream=0)
    writer.close()

    verify_frames(fname, timestamps, image_vals)


@pytest.mark.parametrize('fmt', [('mkv', 'matroska'), ('avi', 'avi')])
def test_write_smaller_than_frame_rate(tmp_path, fmt):
    from ffpyplayer.writer import MediaWriter
    fname = str(tmp_path / 'test_frame.') + fmt[0]

    w, h = 64, 64
    out_opts = {
        'pix_fmt_in': 'rgb24', 'width_in': w, 'height_in': h,
        'codec': 'rawvideo', 'pix_fmt_out': 'yuv420p',
        'frame_rate': (30, 1)}

    writer = MediaWriter(fname, [out_opts], fmt=fmt[1])
    img = get_image(w, h)

    if fmt[0] == 'avi':
        with pytest.raises(Exception):
            for i in range(20):
                writer.write_frame(img=img, pts=i / 300, stream=0)
    else:
        for i in range(20):
            writer.write_frame(img=img, pts=i / 300, stream=0)
    writer.close()
