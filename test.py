'''
To run, please provide a filename on the command line when running the file.
'''


import kivy
from kivy.base import EventLoop
EventLoop.ensure_window()
from ffpyplayer.player import MediaPlayer
from ffpyplayer.tools import set_log_callback, loglevels
from kivy.clock import Clock
from kivy.graphics.texture import Texture
from kivy.app import App
from kivy.core.window import Window
from kivy.lang import Builder
from kivy.uix.relativelayout import RelativeLayout
from kivy.weakmethod import WeakMethod
import sys
import logging
logging.root.setLevel(logging.DEBUG)


Builder.load_string('''
<Root>:
    id: rt
    image: img
    volume: volume
    seek: seek
    Image:
        id: img
        size_hint: 0.95, 0.95
        pos: 0.05 * rt.width, 0.05 * rt.height
        allow_stretch: False
        on_size: app.resize()
    ProgressBar:
        id: seek
        size_hint: 0.95, 0.05
        pos: 0.05 * rt.width, 0
        on_touch_down: app.touch_down(args[1])
        value: 0
    Slider:
        id: volume
        orientation: 'vertical'
        size_hint: 0.05, 1.
        pos: 0.0, 0.0
        step: 0.01
        value: 1.
        range: 0., 1.
        on_value: app.ffplayer and app.ffplayer.set_volume(self.value)
''')

class Root(RelativeLayout):
    pass

log_level = 'debug'
logger_func = {'quiet': logging.critical, 'panic': logging.critical,
               'fatal': logging.critical, 'error': logging.error,
               'warning': logging.warning, 'info': logging.info,
               'verbose': logging.debug, 'debug': logging.debug}


def log_callback(message, level):
    message = message.strip()
    if message:
        logger_func[level]('ffpyplayer: {}'.format(message))


class PlayerApp(App):

    def __init__(self, **kwargs):
        super(PlayerApp, self).__init__(**kwargs)
        self.texture = None
        self.size = (0, 0)
        self.buffer = None
        self.next_frame = None

    def build(self):
        self.root = Root()
        return self.root

    def on_start(self):
        self.callback_ref = WeakMethod(self.callback)
        filename = sys.argv[1]
        logging.info('ffpyplayer: Playing file "{}"'.format(filename))
        # try ff_opts = {'vf':'edgedetect'} http://ffmpeg.org/ffmpeg-filters.html
        ff_opts = {}
        self.ffplayer = MediaPlayer(filename, callback=self.callback_ref,
                                    loglevel=log_level, ff_opts=ff_opts)
        Clock.schedule_once(self.redraw, 0)
        self.keyboard = Window.request_keyboard(None, self.root)
        self.keyboard.bind(on_key_down=self.on_keyboard_down)

    def resize(self):
        if self.ffplayer:
            w, h = self.ffplayer.get_metadata()['src_vid_size']
            if not h:
                return
            if self.root.image.width < self.root.image.height * w / float(h):
                self.ffplayer.set_size(-1, self.root.image.height)
            else:
                self.ffplayer.set_size(self.root.image.width, -1)
            logging.debug('ffpyplayer: Resized video.')

    def update_pts(self, *args):
        if self.ffplayer:
            self.root.seek.value = self.ffplayer.get_pts()

    def on_keyboard_down(self, keyboard, keycode, text, modifiers):
        if not self.ffplayer:
            return False
        ctrl = 'ctrl' in modifiers
        if keycode[1] == 'p' or keycode[1] == 'spacebar':
            logging.info('Toggled pause.')
            self.ffplayer.toggle_pause()
            Clock.unschedule(self.redraw)
            Clock.schedule_once(self.redraw, 0)
        elif keycode[1] == 'r':
            logging.debug('ffpyplayer: Forcing a refresh.')
            self.redraw(force_refresh=True)
        elif keycode[1] == 'v':
            logging.debug('ffpyplayer: Changing video stream.')
            self.ffplayer.request_channel('video',
                                          'close' if ctrl else 'cycle')
            Clock.unschedule(self.update_pts)
            Clock.unschedule(self.redraw)
            if ctrl:    # need to continue updating pts, since video is disabled.
                Clock.schedule_interval(self.update_pts, 0.05)
            else:
                Clock.schedule_once(self.redraw, 0)
        elif keycode[1] == 'a':
            logging.debug('ffpyplayer: Changing audio stream.')
            self.ffplayer.request_channel('audio',
                                          'close' if ctrl else 'cycle')
        elif keycode[1] == 't':
            logging.debug('ffpyplayer: Changing subtitle stream.')
            self.ffplayer.request_channel('subtitle',
                                          'close' if ctrl else 'cycle')
        elif keycode[1] == 'right':
            logging.debug('ffpyplayer: Seeking forward by 10s.')
            self.ffplayer.seek(10.)
            self.next_frame = None
            Clock.unschedule(self.redraw)
            Clock.schedule_once(self.redraw, 0)
        elif keycode[1] == 'left':
            logging.debug('ffpyplayer: Seeking back by 10s.')
            self.ffplayer.seek(-10.)
            self.next_frame = None
            Clock.unschedule(self.redraw)
            Clock.schedule_once(self.redraw, 0)
        elif keycode[1] == 'up':
            logging.debug('ffpyplayer: Increasing volume.')
            self.ffplayer.set_volume(self.ffplayer.get_volume() + 0.01)
            self.root.volume.value = self.ffplayer.get_volume()
        elif keycode[1] == 'down':
            logging.debug('ffpyplayer: Decreasing volume.')
            self.ffplayer.set_volume(self.ffplayer.get_volume() - 0.01)
            self.root.volume.value = self.ffplayer.get_volume()
        return True

    def touch_down(self, touch):
        if self.root.seek.collide_point(*touch.pos) and self.ffplayer:
            pts = ((touch.pos[0] - self.root.volume.width) /
            self.root.seek.width * self.ffplayer.get_metadata()['duration'])
            logging.debug('ffpyplayer: Seeking to {}.'.format(pts))
            self.ffplayer.seek(pts, relative=False)
            self.next_frame = None
            Clock.unschedule(self.redraw)
            Clock.schedule_once(self.redraw, 0)
            return True
        return False

    def callback(self, selector, value):
        if self.ffplayer is None:
            return
        if selector == 'quit':
            logging.debug('ffpyplayer: Quitting.')
            def close(*args):
                Clock.unschedule(self.redraw)
                self.ffplayer = None
            Clock.schedule_once(close, 0)
        # called from internal thread, it typically reads forward
        elif selector == 'display_sub':
            self.display_subtitle(*value)

    def redraw(self, dt=0, force_refresh=False):
        if not self.ffplayer:
            return
        if self.next_frame and not force_refresh:
            img, pts = self.next_frame
            self.next_frame = None
            if img.get_size() != self.size or self.texture is None:
                self.root.image.canvas.remove_group(str(self)+'_display')
                self.texture = Texture.create(size=img.get_size(),
                                              colorfmt='rgb')
                # by adding 'vf':'vflip' to the player initialization ffmpeg
                # will do the flipping
                self.texture.flip_vertical()
                self.texture.add_reload_observer(self.reload_buffer)
                self.size = img.get_size()
                logging.debug('ffpyplayer: Creating new image texture of '
                              'size: {}.'.format(self.size))
            self.buffer = bytes(img.to_bytearray()[0])
            self.texture.blit_buffer(self.buffer)
            self.root.image.texture = None
            self.root.image.texture = self.texture
            self.root.seek.value = pts
            logging.debug('ffpyplayer: Blitted new frame with time: {}.'
                          .format(pts))
        self.next_frame, val = self.ffplayer.get_frame(force_refresh=
                                                       force_refresh)
        if val == 'eof':
            logging.debug('ffpyplayer: Got eof.')
            return
        elif val == 'paused':
            logging.debug('ffpyplayer: Got paused.')
            return
        else:
            logging.debug('ffpyplayer: Next frame scheduled at {}.'
                          .format(val))
        Clock.schedule_once(self.redraw,
                            val if val or self.next_frame else 1/60.)
        if self.root.seek.value:
            self.root.seek.max = self.ffplayer.get_metadata()['duration']

    def display_subtitle(self, text, fmt, pts, t_start, t_end):
        pass # fmt is text (unformatted), or ass (formatted subs)

    def reload_buffer(self, *args):
        logging.debug('ffpyplayer: Reloading buffer.')
        self.texture.blit_buffer(self.buffer, colorfmt='rgb',
                                 bufferfmt='ubyte')

if __name__ == '__main__':
    set_log_callback(log_callback)
    a = PlayerApp()
    a.run()
    # because MediaPlayer runs non-daemon threads, when the main thread exists
    # it'll get stuck waiting for those threads to close, so we manually
    # have to delete these threads by deleting the MediaPlayer object.
    a.ffplayer = None
    set_log_callback(None)
