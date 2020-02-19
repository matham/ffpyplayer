
include "includes/ffmpeg.pxi"


cdef enum MT_lib:
    SDL_MT,
    Py_MT

cdef class MTMutex(object):
    cdef MT_lib lib
    cdef void* mutex

    cdef int lock(MTMutex self) nogil except 2
    cdef int _lock_py(MTMutex self) nogil except 2
    cdef int unlock(MTMutex self) nogil except 2
    cdef int _unlock_py(MTMutex self) nogil except 2

cdef class MTCond(object):
    cdef MT_lib lib
    cdef MTMutex mutex
    cdef void *cond

    cdef int lock(MTCond self) nogil except 2
    cdef int unlock(MTCond self) nogil except 2
    cdef int cond_signal(MTCond self) nogil except 2
    cdef int _cond_signal_py(MTCond self) nogil except 2
    cdef int cond_wait(MTCond self) nogil except 2
    cdef int _cond_wait_py(MTCond self) nogil except 2
    cdef int cond_wait_timeout(MTCond self, uint32_t val) nogil except 2
    cdef int _cond_wait_timeout_py(MTCond self, uint32_t val) nogil except 2

cdef class MTThread(object):
    cdef MT_lib lib
    cdef void* thread

    cdef int create_thread(MTThread self, int_void_func func, const char *thread_name, void *arg) nogil except 2
    cdef int wait_thread(MTThread self, int *status) nogil except 2


cdef class MTGenerator(object):
    cdef MT_lib mt_src

    cdef int delay(MTGenerator self, int delay) nogil except 2
    cdef lockmgr_func get_lockmgr(MTGenerator self) nogil

cdef lockmgr_func get_lib_lockmgr(MT_lib lib) nogil
