
import unittest


class PicTestCase(unittest.TestCase):

    def test_play(self):
        from .common import get_media
        from ffpyplayer.player import MediaPlayer
        import time

        error = [None, ]
        def callback(selector, value):
            if selector.endswith('error'):
                error[0] = selector, value

        # only video
        ff_opts={'an':True, 'sync':'video'}
        player = MediaPlayer(get_media('dw11222.mp4'), callback=callback,
                             ff_opts=ff_opts)

        while not error[0]:
            frame, val = player.get_frame()
            if val == 'eof':
                break
            elif frame is None:
                time.sleep(0.01)
            else:
                img, t = frame

        if error[0]:
            raise Exception('{}: {}'.format(*error[0]))
