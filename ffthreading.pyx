
__all__ = ('MTGenerator', )

include "ff_defs_comp.pxi"


cdef struct MTCond:
    MT_lib lib
    void *cond
    int (*cond_signal)(void *) nogil
    void (*destroy_cond)(void *) nogil
    int (*cond_wait)(void *, void *) nogil
    int (*cond_wait_timeout)(void *, void *, uint32_t) nogil

cdef struct MTMutex:
    MT_lib lib
    void* mutex
    int (*lock_mutex)(void *) nogil
    int (*unlock_mutex)(void *) nogil
    void (*destroy_mutex)(void *) nogil

cdef struct MTThread:
    MT_lib lib
    void* thread
    void (*wait_thread)(void *, int *) nogil


cdef int SDL_lockmgr(void ** mtx, AVLockOp op) nogil:
    if op == AV_LOCK_CREATE:
        mtx[0] = SDL_CreateMutex()
        if mtx[0] == NULL:
            return 1
        return 0
    if op == AV_LOCK_OBTAIN:
        return not not SDL_mutexP(<SDL_mutex *>mtx[0]) # force it to 0, or 1
    if op == AV_LOCK_RELEASE:
        return not not SDL_mutexV(<SDL_mutex *>mtx[0])
    if op == AV_LOCK_DESTROY:
        SDL_DestroyMutex(<SDL_mutex *>mtx[0])
        return 0
    return 1

cdef class MTGenerator(object):

    def __cinit__(MTGenerator self, MT_lib mt_src, **kwargs):
        self.mt_src = mt_src

    cdef MTMutex* create_mutex(MTGenerator self) nogil:
        cdef MTMutex *mutex = <MTMutex *>av_malloc(sizeof(MTMutex))
        if self.mt_src == SDL_MT:
            mutex.mutex = SDL_CreateMutex()
            mutex.lock_mutex = <int (*)(void *) nogil>&SDL_mutexP # should be SDL_LockMutex
            mutex.unlock_mutex = <int (*)(void *) nogil>&SDL_mutexV # should be SDL_UnlockMutex
            mutex.destroy_mutex = <void (*)(void *) nogil>&SDL_DestroyMutex
            mutex.lib = SDL_MT
        return mutex
    
    cdef void destroy_mutex(MTGenerator self, MTMutex *mutex) nogil:
        if mutex != NULL:
            mutex.destroy_mutex(mutex.mutex)
            av_free(mutex)

    cdef MTCond* create_cond(MTGenerator self) nogil:
        cdef MTCond *cond = <MTCond *>av_malloc(sizeof(MTCond))
        if self.mt_src == SDL_MT:
            cond.cond = SDL_CreateCond()
            cond.cond_signal = <int (*)(void *) nogil>&SDL_CondSignal
            cond.destroy_cond = <void (*)(void *) nogil>&SDL_DestroyCond
            cond.cond_wait = <int (*)(void *, void *) nogil>&SDL_CondWait
            cond.cond_wait_timeout = <int (*)(void *, void *, uint32_t) nogil>&SDL_CondWaitTimeout
            cond.lib = SDL_MT
        return cond
    
    cdef void destroy_cond(MTGenerator self, MTCond *cond) nogil:
        if cond != NULL:
            cond.destroy_cond(cond.cond)
            av_free(cond)
    
    cdef MTThread* create_thread(MTGenerator self, int_void_func func, void *arg) nogil:
        cdef MTThread *thread = <MTThread *>av_malloc(sizeof(MTThread))
        if self.mt_src == SDL_MT:
            with gil:
                thread.thread = SDL_CreateThread(func, arg)
            thread.lib = SDL_MT
            thread.wait_thread = <void (*)(void *, int *) nogil>&SDL_WaitThread
        return thread
    
    cdef void destroy_thread(MTGenerator self, MTThread *thread) nogil:
        if thread != NULL:
            av_free(thread)
    
    cdef void delay(MTGenerator self, int delay) nogil:
        if self.mt_src == SDL_MT:
            SDL_Delay(delay)
    
    cdef lockmgr_func get_lockmgr(MTGenerator self) nogil:
        if self.mt_src == SDL_MT:
            return SDL_lockmgr
