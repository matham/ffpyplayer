
include "ff_defs.pxi"

cimport ffcore
from ffcore cimport VideoState

cdef void SDL_initialize(int display_disable, int audio_disable, int *fs_screen_width,
                         int *fs_screen_height) nogil
cdef void calculate_display_rect(SDL_Rect *rect, int scr_xleft, int scr_ytop,
                                 int scr_width, int scr_height, VideoPicture *vp) nogil
cdef void duplicate_right_border_pixels(SDL_Overlay *bmp) nogil
cdef void video_image_display(SDL_Surface *screen, VideoState ist) nogil
cdef void video_audio_display(SDL_Surface *screen, VideoState s, int64_t *audio_callback_time) nogil
cdef inline void fill_rectangle(SDL_Surface *screen, int x, int y, int w,
                                int h, int color, int update) nogil