
import unittest


class PicTestCase(unittest.TestCase):

    def create_image(self, size):
        from ffpyplayer.pic import Image, SWScale

        w, h = size
        size = w * h * 3
        buf = bytearray([int(x * 255 / size) for x in range(size)])
        return Image(plane_buffers=[buf], pix_fmt='rgb24', size=(w, h))

    def test_pic(self):
        from ffpyplayer.pic import Image, SWScale

        size = w, h = 500, 100
        img = self.create_image(size)

        self.assertFalse(img.is_ref())
        self.assertEqual(img.get_size(), (w, h))

        sws = SWScale(w, h, img.get_pixel_format(), ofmt='yuv420p')

        img2 = sws.scale(img)
        self.assertEqual(img2.get_pixel_format(), 'yuv420p')
        planes = img2.to_bytearray()
        self.assertEqual(list(map(len, planes)), [w * h, w * h / 4, w * h / 4, 0])
