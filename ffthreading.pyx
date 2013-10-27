
__all__ = ('MTGenerator', )

include "ff_defs_comp.pxi"

from cpython.ref cimport PyObject

cdef extern from "Python.h":
    void Py_INCREF(PyObject *)
    void Py_XINCREF(PyObject *)
    void Py_DECREF(PyObject *)


cdef class MTMutex(object):

    def __cinit__(MTMutex self, MT_lib lib):
        self.lib = lib
        self.mutex = NULL
        if lib == SDL_MT:
            self.mutex = SDL_CreateMutex()
            if self.mutex == NULL:
                raise Exception('Cannot create mutex.')
        elif lib == Py_MT:
            import threading
            mutex = threading.Lock()
            self.mutex = <PyObject *>mutex
            Py_INCREF(<PyObject *>self.mutex)
    
    def __dealloc__(MTMutex self):
        if self.lib == SDL_MT:
            if self.mutex != NULL:
                SDL_DestroyMutex(<SDL_mutex *>self.mutex)
        elif self.lib == Py_MT:
            Py_DECREF(<PyObject *>self.mutex)
    
    cdef int lock(MTMutex self) nogil:
        if self.lib == SDL_MT:
            return SDL_mutexP(<SDL_mutex *>self.mutex)
        elif self.lib == Py_MT:
            with gil:
                return not (<object>self.mutex).acquire()
    cdef int unlock(MTMutex self) nogil:
        if self.lib == SDL_MT:
            return SDL_mutexV(<SDL_mutex *>self.mutex)
        elif self.lib == Py_MT:
            with gil:
                (<object>self.mutex).release()
            return 0

cdef class MTCond(object):

    def __cinit__(MTCond self, MT_lib lib):
        self.lib = lib
        self.mutex = MTMutex(lib)
        self.cond = NULL
        if self.lib == SDL_MT:
            self.cond = SDL_CreateCond()
            if self.cond == NULL:
                raise Exception('Cannot create condition.')
        elif self.lib == Py_MT:
            import threading
            cond = threading.Condition(<object>self.mutex.mutex)
            self.cond = <PyObject *>cond
            Py_INCREF(<PyObject *>self.cond)
    
    def __dealloc__(MTCond self):
        if self.lib == SDL_MT:
            if self.cond != NULL:
                SDL_DestroyCond(<SDL_cond *>self.cond)
        elif self.lib == Py_MT:
            Py_DECREF(<PyObject *>self.cond)

    cdef int lock(MTCond self) nogil:
        self.mutex.lock()
        
    cdef int unlock(MTCond self) nogil:
        self.mutex.unlock()
        
    cdef int cond_signal(MTCond self) nogil:
        if self.lib == SDL_MT:
            return SDL_CondSignal(<SDL_cond *>self.cond)
        elif self.lib == Py_MT:
            with gil:
                (<object>self.cond).notify()
            return 0

    cdef int cond_wait(MTCond self) nogil:
        if self.lib == SDL_MT:
            return SDL_CondWait(<SDL_cond *>self.cond, <SDL_mutex *>self.mutex.mutex)
        elif self.lib == Py_MT:
            with gil:
                (<object>self.cond).wait()
            return 0
        
    cdef int cond_wait_timeout(MTCond self, uint32_t val) nogil:
        if self.lib == SDL_MT:
            return SDL_CondWaitTimeout(<SDL_cond *>self.cond, <SDL_mutex *>self.mutex.mutex, val)
        elif self.lib == Py_MT:
            with gil:
                (<object>self.cond).wait(val / 1000.)
            return 0

def enterance_func(target_func, target_arg):
    return (<int_void_func><uintptr_t>target_func)(<void *><uintptr_t>target_arg)

cdef class MTThread(object):

    def __cinit__(MTThread self, MT_lib lib):
        self.lib = lib
        self.thread = NULL
    
    def __dealloc__(MTThread self):
        if self.lib == Py_MT and self.thread != NULL:
            Py_DECREF(<PyObject *>self.thread)
    
    cdef void create_thread(MTThread self, int_void_func func, void *arg) nogil:
        if self.lib == SDL_MT:
            with gil:
                self.thread = SDL_CreateThread(func, arg)
                if self.thread == NULL:
                    raise Exception('Cannot create thread.')
        elif self.lib == Py_MT:
            with gil:
                import threading
                thread = threading.Thread(group=None, target=enterance_func,
                                          name=None, args=(<uintptr_t>func, <uintptr_t>arg), kwargs={})
                self.thread = <PyObject *>thread
                Py_INCREF(<PyObject *>self.thread)
                thread.start()

    cdef void wait_thread(MTThread self, int *status) nogil:
        if self.lib == SDL_MT:
            if self.thread == NULL:
                SDL_WaitThread(<SDL_Thread *>self.thread, status)
        elif self.lib == Py_MT:
            with gil:
                (<object>self.thread).join()
                status[0] = 0


cdef int lockmgr(void ** mtx, AVLockOp op, MT_lib lib) with gil:
    cdef MTMutex mutex
    if op == AV_LOCK_CREATE:
        try:
            mutex = MTMutex(lib)
        except:
            return 1
        Py_INCREF(<PyObject *>mutex)
        mtx[0] = <PyObject *>mutex
        return 0
    if op == AV_LOCK_OBTAIN:
        mutex = <MTMutex>mtx[0]
        return not not mutex.lock() # force it to 0, or 1
    if op == AV_LOCK_RELEASE:
        mutex = <MTMutex>mtx[0]
        return not not mutex.unlock()
    if op == AV_LOCK_DESTROY:
        if mtx[0] != NULL:
            Py_DECREF(<PyObject *>mtx[0])
        return 0
    return 1

cdef int SDL_lockmgr(void ** mtx, AVLockOp op) nogil:
    return lockmgr(mtx, op, SDL_MT)

cdef int Py_lockmgr(void ** mtx, AVLockOp op) nogil:
    return lockmgr(mtx, op, Py_MT)


cdef class MTGenerator(object):

    def __cinit__(MTGenerator self, MT_lib mt_src, **kwargs):
        self.mt_src = mt_src

    cdef void delay(MTGenerator self, int delay) nogil:
        if self.mt_src == SDL_MT:
            SDL_Delay(delay)
        elif self.mt_src == Py_MT:
            with gil:
                import time
                time.sleep(delay / 1000.)
    
    cdef lockmgr_func get_lockmgr(MTGenerator self) nogil:
        if self.mt_src == SDL_MT:
            return SDL_lockmgr
        elif self.mt_src == Py_MT:
            return Py_lockmgr
