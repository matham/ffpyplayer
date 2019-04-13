
import unittest
from os.path import join, abspath, dirname
from os import remove

fname = join(dirname(__file__), 'test_video.avi')


class PicTestCase(unittest.TestCase):

    def test_play(self):
        from ffpyplayer.writer import MediaWriter
        from ffpyplayer.tools import get_supported_pixfmts, get_supported_framerates
        from ffpyplayer.pic import Image
        from ffpyplayer.tools import get_codecs

        lib_opts = {}
        codec = 'rawvideo'
        if 'libx264' in get_codecs(encode=True, video=True):
            codec = 'libx264'
            lib_opts = {'preset':'slow', 'crf':'22'}

        w, h = 640, 480
        out_opts = {
            'pix_fmt_in': 'rgb24', 'width_in': w, 'height_in': h,
            'codec': codec, 'frame_rate': (5, 1)}

        metadata = {'title':'Singing in the sun', 'author':'Rat', 'genre':'Animal sounds'}
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

    def tearDown(self, *largs, **kw):
        super(PicTestCase, self).tearDown(*largs, **kw)
        remove(fname)
