import kivy
from kivy.base import EventLoop
EventLoop.ensure_window()
import ffpyplayer
from ffpyplayer import FFPyPlayer, set_log_callback
from kivy.clock import Clock
from kivy.graphics.texture import Texture
from kivy.uix.image import Image
from kivy.app import App
from kivy.core.window import Window
from kivy.lang import Builder
from kivy.uix.relativelayout import RelativeLayout
from kivy.weakmethod import WeakMethod


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

def log_callback(message, level):
    print '%s: %s' %(level, message.strip())


class PlayerApp(App):

    def __init__(self, **kwargs):
        super(PlayerApp, self).__init__(**kwargs)
        self.texture = None
        self.size = (0, 0)
        self.buffer = None

    def build(self):
        self.root = Root()
        return self.root

    def on_start(self):
        self.callback_ref = WeakMethod(self.callback)
        # Download the test video from here:
        #http://www.auby.no/files/video_tests/h264_720p_hp_5.1_3mbps_vorbis_styled_and_unstyled_subs_suzumiya.mkv
        filename = r'C:\FFmpeg\h264_720p_hp_5.1_3mbps_vorbis_styled_and_unstyled_subs_suzumiya.mkv'
        # this displays the subtitles using the subtitles video filter. FFmpeg escaping rules apply.
        # other video filters e.g. = ff_opts = {'vf':'edgedetect'} http://ffmpeg.org/ffmpeg-filters.html
        ff_opts = {'vf':r'subtitles=C\\:\\\\FFmpeg\\\\h264_720p_hp_5.1_3mbps_vorbis_styled_and_unstyled_subs_suzumiya.mkv'}
        self.ffplayer = FFPyPlayer(filename, vid_sink=self.callback_ref,
                                   loglevel='debug', ff_opts=ff_opts)
        self.callback('refresh', 0.)
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

    def on_keyboard_down(self, keyboard, keycode, text, modifiers):
        if not self.ffplayer:
            return False
        if keycode[1] == 'p' or keycode[1] == 'spacebar':
            self.ffplayer.toggle_pause()
        elif keycode[1] == 's':
            self.ffplayer.step_frame()
        elif keycode[1] == 'v':
            self.ffplayer.cycle_channel('video')
        elif keycode[1] == 'a':
            self.ffplayer.cycle_channel('audio')
        elif keycode[1] == 't':
            self.ffplayer.cycle_channel('subtitle')
        elif keycode[1] == 'right':
            self.ffplayer.seek(10.)
        elif keycode[1] == 'left':
            self.ffplayer.seek(-10.)
        elif keycode[1] == 'up':
            self.ffplayer.seek(60.)
        elif keycode[1] == 'down':
            self.ffplayer.seek(-60.)
        return True

    def touch_down(self, touch):
        if self.root.seek.collide_point(*touch.pos) and self.ffplayer:
            self.ffplayer.seek((touch.pos[0] - self.root.volume.width) / \
                               self.root.seek.width * self.ffplayer.get_metadata()['duration'],
                               relative=False)
            return True
        return False

    def callback(self, selector, value):
        if self.ffplayer is None:
            return
        if selector == 'quit':
            def close(*args):
                Clock.unschedule(self.ffplayer.refresh)
                self.ffplayer = None
            Clock.schedule_once(close, 0)
        elif selector == 'display': # this is called from thread that calls refresh
            self.redraw(*value)
            self.root.seek.max = self.ffplayer.get_metadata()['duration'] # do only once
        elif selector == 'display_sub': # called from internal thread, it typically reads forward
            self.display_subtitle(*value)
        elif selector == 'refresh':
            # XXX: is Clock thread safe?
            Clock.unschedule(self.ffplayer.refresh)
            Clock.schedule_once(self.ffplayer.refresh, value)
        elif selector == 'eof':
            pass

    def redraw(self, buffer, size, pts):
        if size != self.size or self.texture is None:
            self.root.image.canvas.remove_group(str(self)+'_display')
            self.texture = Texture.create(size=size, colorfmt='rgb')
            # by adding 'vf':'vflip' to the player initialization ffmpeg will do the flipping
            self.texture.flip_vertical()
            self.texture.add_reload_observer(self.reload_buffer)
            self.size = size
        self.buffer = buffer
        self.texture.blit_buffer(buffer)
        self.root.image.texture = None
        self.root.image.texture = self.texture
        self.root.seek.value = pts

    def display_subtitle(self, text, fmt, pts, t_start, t_end):
        # this pattern is needed to parse ass subtitles
        #pattern = re.compile('([\w ]*?):([\w= ]*?,)([\d: \.]+?,)([\d: \.]+?,)'+\
        #'([^,]+?,)?([.+?,)?([\d]+?,)?([\d]+?,)?([\d]+?,)?(.+?,)?(.+)')
        return
        # why is ffmpeg sometimes outputing off spec subtitles?
        if fmt == 'ass':
            m = pattern.match(text)
            text = m.groups()[-1]
        text = text.strip().replace('\N', '\n')

    def reload_buffer(self, *args):
        self.texture.blit_buffer(self.buffer, colorfmt='rgb', bufferfmt='ubyte')

if __name__ == '__main__':
    set_log_callback(log_callback)
    a = PlayerApp()
    a.run()
    if a.ffplayer is not None:
        Clock.unschedule(a.ffplayer.refresh)
    # why do we need to set this to None in order to call dealloc on ffplayer?
    # shouldn't it automatically be deallocated?
    a.ffplayer = None
    set_log_callback(None)
