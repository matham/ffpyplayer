
include "ff_defs.pxi"


cdef enum MT_lib:
    SDL_MT,
    Py_MT
    
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
    
    
cdef class MTGenerator(object):
    cdef MT_lib mt_src

    cdef MTMutex* create_mutex(MTGenerator self) nogil
    cdef void destroy_mutex(MTGenerator self, MTMutex *mutex) nogil
    cdef MTCond* create_cond(MTGenerator self) nogil
    cdef void destroy_cond(MTGenerator self, MTCond *cond) nogil
    cdef MTThread* create_thread(MTGenerator self, int_void_func func, void *arg) nogil
    cdef void destroy_thread(MTGenerator self, MTThread *thread) nogil
    cdef void delay(MTGenerator self, int delay) nogil
    cdef lockmgr_func get_lockmgr(MTGenerator self) nogil
