
include "includes/ffmpeg.pxi"


cdef enum MT_lib:
    SDL_MT,
    Py_MT

cdef class MTMutex(object):
    cdef MT_lib lib
    cdef void* mutex

    cdef int lock(MTMutex self) except 2 nogil
    cdef int _lock_py(MTMutex self) except 2 nogil
    cdef int unlock(MTMutex self) except 2 nogil
    cdef int _unlock_py(MTMutex self) except 2 nogil

cdef class MTCond(object):
    cdef MT_lib lib
    cdef MTMutex mutex
    cdef void *cond

    cdef int lock(MTCond self) except 2 nogil
    cdef int unlock(MTCond self) except 2 nogil
    cdef int cond_signal(MTCond self) except 2 nogil
    cdef int _cond_signal_py(MTCond self) except 2 nogil
    cdef int cond_wait(MTCond self) except 2 nogil
    cdef int _cond_wait_py(MTCond self) except 2 nogil
    cdef int cond_wait_timeout(MTCond self, uint32_t val) except 2 nogil
    cdef int _cond_wait_timeout_py(MTCond self, uint32_t val) except 2 nogil

cdef class MTThread(object):
    cdef MT_lib lib
    cdef void* thread

    cdef int create_thread(MTThread self, int_void_func func, const char *thread_name, void *arg) except 2 nogil
    cdef int wait_thread(MTThread self, int *status) except 2 nogil


cdef class MTGenerator(object):
    cdef MT_lib mt_src

    cdef int delay(MTGenerator self, int delay) except 2 nogil
    cdef lockmgr_func get_lockmgr(MTGenerator self) nogil

cdef lockmgr_func get_lib_lockmgr(MT_lib lib) nogil
