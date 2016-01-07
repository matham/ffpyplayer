#cython: cdivision=True

__all__ = ('Clock', )

include '../includes/ff_consts.pxi'

cdef extern from "math.h" nogil:
    double NAN
    int isnan(double x)
    double fabs(double x)


cdef class Clock(object):

    def __cinit__(Clock self):
        pass
    cdef void cInit(Clock self, int *queue_serial) nogil:
        self.speed = 1.0
        self.paused = 0
        if queue_serial != NULL:
            self.queue_serial = queue_serial
        else:
            self.queue_serial = &self.serial
        self.set_clock(NAN, -1)

    def __dealloc__(Clock self):
        pass

    cdef double get_clock(Clock self) nogil:
        cdef double time
        if self.queue_serial[0] != self.serial:
            return NAN
        if self.paused:
            return self.pts
        else:
            time = av_gettime_relative() / 1000000.0
            return self.pts_drift + time - (time - self.last_updated) * (1.0 - self.speed)

    cdef void set_clock_at(Clock self, double pts, int serial, double time) nogil:
        self.pts = pts
        self.last_updated = time
        self.pts_drift = self.pts - time
        self.serial = serial

    cdef void set_clock(Clock self, double pts, int serial) nogil:
        cdef double time = av_gettime_relative() / 1000000.0
        self.set_clock_at(pts, serial, time)

    cdef void set_clock_speed(Clock self, double speed) nogil:
        self.set_clock(self.get_clock(), self.serial)
        self.speed = speed

    cdef void sync_clock_to_slave(Clock self, Clock slave) nogil:
        cdef double clock = self.get_clock()
        cdef double slave_clock = slave.get_clock()
        if (not isnan(slave_clock)) and (isnan(clock) or fabs(clock - slave_clock) > AV_NOSYNC_THRESHOLD):
            self.set_clock(slave_clock, slave.serial)
