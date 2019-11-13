
def test_play():
    from .common import get_media
    from ffpyplayer.player import MediaPlayer
    import time

    error = [None, ]

    def callback(selector, value):
        if selector.endswith('error'):
            error[0] = selector, value

    # only video
    ff_opts = {'an': True, 'sync': 'video'}
    player = MediaPlayer(
        get_media('dw11222.mp4'), callback=callback, ff_opts=ff_opts)

    i = 0
    while not error[0]:
        frame, val = player.get_frame()
        if val == 'eof':
            break
        elif frame is None:
            time.sleep(0.001)
        else:
            img, t = frame
            i += 1

    player.close_player()
    if error[0]:
        raise Exception('{}: {}'.format(*error[0]))

    assert i == 6077
