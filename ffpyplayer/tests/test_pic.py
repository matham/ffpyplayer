
def create_image(size):
    from ffpyplayer.pic import Image

    w, h = size
    size = w * h * 3
    buf = bytearray([int(x * 255 / size) for x in range(size)])
    return Image(plane_buffers=[buf], pix_fmt='rgb24', size=(w, h))


def test_pic():
    from ffpyplayer.pic import SWScale

    size = w, h = 500, 100
    img = create_image(size)

    assert not img.is_ref()
    assert img.get_size() == (w, h)

    sws = SWScale(w, h, img.get_pixel_format(), ofmt='yuv420p')

    img2 = sws.scale(img)
    assert img2.get_pixel_format() == 'yuv420p'
    planes = img2.to_bytearray()
    assert list(map(len, planes)) == [w * h, w * h / 4, w * h / 4, 0]
