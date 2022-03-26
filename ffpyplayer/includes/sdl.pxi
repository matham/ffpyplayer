from libc.stdint cimport int64_t, uint64_t, int32_t, uint32_t, uint16_t,\
int16_t, uint8_t, int8_t, uintptr_t

cdef extern from "SDL.h" nogil:
    int SDL_INIT_VIDEO
    int SDL_INIT_AUDIO
    int SDL_INIT_TIMER
    int SDL_INIT_EVENTTHREAD

    void SDL_Delay(int)

    void SDL_WaitThread(SDL_Thread *, int *)
    struct SDL_mutex:
        pass
    struct SDL_Thread:
        pass
    struct SDL_cond:
        pass

    char *SDL_GetError()

    SDL_cond *SDL_CreateCond()
    void SDL_DestroyCond(SDL_cond *)
    int SDL_CondSignal(SDL_cond *)
    int SDL_CondWait(SDL_cond *, SDL_mutex *)

    void SDL_Quit()
    int SDL_Init(uint32_t) with gil
    int SDL_InitSubSystem(uint32_t) with gil

    struct SDL_AudioSpec:
        int freq
        uint16_t format
        uint8_t channels
        uint8_t silence
        uint16_t samples
        uint16_t padding
        uint32_t size
        void (*callback)(void *, uint8_t *, int)
        void *userdata


cdef extern from "SDL_thread.h" nogil:
    SDL_Thread *SDL_CreateThread(int_void_func, const char *, void *) with gil

IF USE_SDL2_MIXER:
    cdef extern from "SDL_mixer.h" nogil:
        struct Mix_Chunk:
            int allocated
            uint8_t *abuf
            uint32_t alen
            uint8_t volume

        int Mix_OpenAudio(int, uint16_t, int, int)
        int Mix_QuerySpec(int *, uint16_t *, int *)
        void Mix_CloseAudio()

        Mix_Chunk *Mix_QuickLoad_RAW(uint8_t *, uint32_t)
        void Mix_FreeChunk(Mix_Chunk *)

        int Mix_AllocateChannels(int)
        int Mix_PlayChannel(int, Mix_Chunk *, int)
        int Mix_Volume(int, int)
        int Mix_RegisterEffect(int, void (*)(int, void *, int, void *), void (*)(int, void *), void *)
        int Mix_UnregisterEffect(int, void (*)(int, void *, int, void *))
        void Mix_Pause(int)
        void Mix_Resume(int)
        int Mix_HaltChannel(int)


cdef extern from * nogil:
    uint32_t SDL_HWACCEL
    uint32_t SDL_ASYNCBLIT
    uint32_t SDL_HWSURFACE
    uint32_t SDL_FULLSCREEN
    uint32_t SDL_RESIZABLE
    uint32_t SDL_YV12_OVERLAY
    uint8_t SDL_MIX_MAXVOLUME

    uint16_t AUDIO_S16SYS
    int SDL_OpenAudio(SDL_AudioSpec *, SDL_AudioSpec *)
    int SDL_AUDIO_ALLOW_ANY_CHANGE
    ctypedef uint32_t SDL_AudioDeviceID
    SDL_AudioDeviceID SDL_OpenAudioDevice(
        const char*, int, const SDL_AudioSpec*, SDL_AudioSpec*, int)
    void SDL_PauseAudioDevice(SDL_AudioDeviceID, int)
    void SDL_CloseAudioDevice(SDL_AudioDeviceID)
    void SDL_MixAudioFormat(
        uint8_t*, const uint8_t*, uint16_t, uint32_t, int)

    void SDL_PauseAudio(int)
    void SDL_CloseAudio()
    void SDL_MixAudio(uint8_t *, const uint8_t *, uint32_t, int)

    SDL_mutex *SDL_CreateMutex()
    void SDL_DestroyMutex(SDL_mutex *)
    int SDL_mutexP(SDL_mutex *) # SDL_LockMutex
    int SDL_mutexV(SDL_mutex *) # SDL_UnlockMutex
    int SDL_CondWaitTimeout(SDL_cond *, SDL_mutex *, uint32_t)

    void SDL_UpdateRect(SDL_Surface *, int32_t, int32_t, uint32_t, uint32_t)
    int SDL_FillRect(SDL_Surface *, SDL_Rect *, uint32_t)
    int SDL_LockYUVOverlay(SDL_Overlay *)
    void SDL_UnlockYUVOverlay(SDL_Overlay *)
    int SDL_DisplayYUVOverlay(SDL_Overlay *, SDL_Rect *)
    void SDL_FreeYUVOverlay(SDL_Overlay *)
    uint32_t SDL_MapRGB(const SDL_PixelFormat * const, const uint8_t,
                        const uint8_t, const uint8_t)
    SDL_Overlay * SDL_CreateYUVOverlay(int, int, uint32_t, SDL_Surface *)

    void SDL_WM_SetCaption(const char *, const char *)
    int SDL_setenv(const char *, const char *, int)
    char * SDL_getenv(const char *)

    SDL_Surface *SDL_SetVideoMode(int, int, int, uint32_t)
    const SDL_VideoInfo *SDL_GetVideoInfo()
    uint8_t SDL_EventState(uint8_t, int)
    void SDL_PumpEvents()

    int SDL_IGNORE
    uint8_t SDL_ACTIVEEVENT
    uint8_t SDL_SYSWMEVENT
    enum:
        SDL_VIDEOEXPOSE,
        SDL_USEREVENT,
        SDL_QUIT,
        SDL_VIDEORESIZE,
    uint32_t SDL_ALLEVENTS

    struct SDL_VideoInfo:
        int current_w
        int current_h
    struct SDL_Overlay:
        int w, h                  #/**< Read-only */
        uint16_t *pitches         #/**< Read-only */
        uint8_t **pixels          #/**< Read-write */
    struct SDL_PixelFormat:
        pass
    struct SDL_Rect:
        int16_t x, y
        uint16_t w, h
    struct SDL_Surface:
        SDL_PixelFormat *format
        int w, h


    struct SDL_UserEvent:
        uint8_t type
        int code
        void *data1
        void *data2
    struct SDL_ResizeEvent:
        uint8_t type
        int w
        int h
    union SDL_Event:
        uint8_t type
        SDL_UserEvent user
        SDL_ResizeEvent resize
    enum SDL_eventaction:
        SDL_ADDEVENT,
        SDL_PEEKEVENT,
        SDL_GETEVENT,
    int SDL_PushEvent(SDL_Event *event)
    int SDL_PeepEvents(SDL_Event *, int, SDL_eventaction, uint32_t)

    int SDL_ShowCursor(int)
