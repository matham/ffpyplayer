
include "ff_defs.pxi"


cdef enum MT_lib:
    SDL_MT,
    Py_MT

cdef class MTMutex(object):
    cdef MT_lib lib
    cdef void* mutex

    cdef int lock(MTMutex self) nogil
    cdef int unlock(MTMutex self) nogil

cdef class MTCond(object):
    cdef MT_lib lib
    cdef MTMutex mutex
    cdef void *cond
    
    cdef int lock(MTCond self) nogil
    cdef int unlock(MTCond self) nogil
    cdef int cond_signal(MTCond self) nogil
    cdef int cond_wait(MTCond self) nogil
    cdef int cond_wait_timeout(MTCond self, uint32_t val) nogil

cdef class MTThread(object):
    cdef MT_lib lib
    cdef void* thread
    
    cdef void create_thread(MTThread self, int_void_func func, void *arg) nogil
    cdef void wait_thread(MTThread self, int *status) nogil
    
    
cdef class MTGenerator(object):
    cdef MT_lib mt_src

    cdef void delay(MTGenerator self, int delay) nogil
    cdef lockmgr_func get_lockmgr(MTGenerator self) nogil
