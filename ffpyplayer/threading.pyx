
__all__ = ('MTGenerator', )

include "includes/ff_consts.pxi"
include "includes/inline_funcs.pxi"

from cpython.ref cimport PyObject

cdef extern from "Python.h":
    void Py_INCREF(PyObject *)
    void Py_XINCREF(PyObject *)
    void Py_DECREF(PyObject *)

ctypedef int (*int_cls_method)(void *) nogil

import traceback

cdef int sdl_initialized = 0
def initialize_sdl():
    '''Initializes sdl. Must be called before anything can be used.
    It is automatically called by the modules that use SDL.
    '''
    global sdl_initialized
    if sdl_initialized:
        return
    if SDL_Init(0):
        raise ValueError('Could not initialize SDL - %s' % SDL_GetError())
    sdl_initialized = 1
initialize_sdl()


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

    cdef int lock(MTMutex self) nogil except 2:
        if self.lib == SDL_MT:
            return SDL_mutexP(<SDL_mutex *>self.mutex)
        elif self.lib == Py_MT:
            return self._lock_py()

    cdef int _lock_py(MTMutex self) nogil except 2:
        with gil:
            return not (<object>self.mutex).acquire()

    cdef int unlock(MTMutex self) nogil except 2:
        if self.lib == SDL_MT:
            return SDL_mutexV(<SDL_mutex *>self.mutex)
        elif self.lib == Py_MT:
            return self._unlock_py()

    cdef int _unlock_py(MTMutex self) nogil except 2:
        with gil:
            (<object>self.mutex).release()
        return 0

cdef class MTCond(object):

    def __cinit__(MTCond self, MT_lib lib):
        self.lib = lib
        self.mutex = MTMutex.__new__(MTMutex, lib)
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

    cdef int lock(MTCond self) nogil except 2:
        self.mutex.lock()

    cdef int unlock(MTCond self) nogil except 2:
        self.mutex.unlock()

    cdef int cond_signal(MTCond self) nogil except 2:
        if self.lib == SDL_MT:
            return SDL_CondSignal(<SDL_cond *>self.cond)
        elif self.lib == Py_MT:
            return self._cond_signal_py()

    cdef int _cond_signal_py(MTCond self) nogil except 2:
        with gil:
            (<object>self.cond).notify()
        return 0

    cdef int cond_wait(MTCond self) nogil except 2:
        if self.lib == SDL_MT:
            return SDL_CondWait(<SDL_cond *>self.cond, <SDL_mutex *>self.mutex.mutex)
        elif self.lib == Py_MT:
            return self._cond_wait_py()

    cdef int _cond_wait_py(MTCond self) nogil except 2:
        with gil:
            (<object>self.cond).wait()
        return 0

    cdef int cond_wait_timeout(MTCond self, uint32_t val) nogil except 2:
        if self.lib == SDL_MT:
            return SDL_CondWaitTimeout(<SDL_cond *>self.cond, <SDL_mutex *>self.mutex.mutex, val)
        elif self.lib == Py_MT:
            return self._cond_wait_timeout_py(val)

    cdef int _cond_wait_timeout_py(MTCond self, uint32_t val) nogil except 2:
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

    cdef int create_thread(MTThread self, int_void_func func, const char *thread_name, void *arg) nogil except 2:
        if self.lib == SDL_MT:
            with gil:
                self.thread = SDL_CreateThread(func, thread_name, arg)
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
        return 0

    cdef int wait_thread(MTThread self, int *status) nogil except 2:
        if self.lib == SDL_MT:
            if self.thread != NULL:
                SDL_WaitThread(<SDL_Thread *>self.thread, status)
        elif self.lib == Py_MT:
            with gil:
                (<object>self.thread).join()
                if status != NULL:
                    status[0] = 0
        return 0


cdef int_cls_method mutex_lock = <int_cls_method>MTMutex.lock
cdef int_cls_method mutex_release = <int_cls_method>MTMutex.unlock

cdef int _SDL_lockmgr_py(void ** mtx, int op) with gil:
    cdef bytes msg
    cdef int res = 1
    cdef MTMutex mutex

    try:
        if op == FF_LOCK_CREATE:
            mutex = MTMutex.__new__(MTMutex, SDL_MT)
            Py_INCREF(<PyObject *>mutex)
            mtx[0] = <PyObject *>mutex
            res = 0
        elif op == FF_LOCK_DESTROY:
            if mtx[0] != NULL:
                Py_DECREF(<PyObject *>mtx[0])
            res = 0
    except:
        msg = traceback.format_exc().encode('utf8')
        av_log(NULL, AV_LOG_ERROR, '%s', msg)
    return res

cdef int SDL_lockmgr(void ** mtx, int op) nogil:
    if op == FF_LOCK_OBTAIN:
        return not not mutex_lock(mtx[0])
    elif op == FF_LOCK_RELEASE:
        return not not mutex_release(mtx[0])
    else:
        return _SDL_lockmgr_py(mtx, op)

cdef int Py_lockmgr(void ** mtx, int op) with gil:
    cdef int res = 1
    cdef bytes msg
    cdef MTMutex mutex

    try:
        if op == FF_LOCK_CREATE:
            mutex = MTMutex.__new__(MTMutex, Py_MT)
            Py_INCREF(<PyObject *>mutex)
            mtx[0] = <PyObject *>mutex
            res = 0
        elif op == FF_LOCK_OBTAIN:
            mutex = <MTMutex>mtx[0]
            res = not not mutex.lock() # force it to 0, or 1
        elif op == FF_LOCK_RELEASE:
            mutex = <MTMutex>mtx[0]
            res = not not mutex.unlock()
        elif op == FF_LOCK_DESTROY:
            if mtx[0] != NULL:
                Py_DECREF(<PyObject *>mtx[0])
            res = 0
    except:
        msg = traceback.format_exc().encode('utf8')
        av_log(NULL, AV_LOG_ERROR, '%s', msg)
        res = 1
    return res


cdef lockmgr_func get_lib_lockmgr(MT_lib lib) nogil:
    if lib == SDL_MT:
        return SDL_lockmgr
    elif lib == Py_MT:
        return Py_lockmgr


cdef class MTGenerator(object):

    def __cinit__(MTGenerator self, MT_lib mt_src, **kwargs):
        self.mt_src = mt_src

    cdef int delay(MTGenerator self, int delay) nogil except 2:
        if self.mt_src == SDL_MT:
            SDL_Delay(delay)
        elif self.mt_src == Py_MT:
            with gil:
                import time
                time.sleep(delay / 1000.)
        return 0

    cdef lockmgr_func get_lockmgr(MTGenerator self) nogil:
        return get_lib_lockmgr(self.mt_src)
