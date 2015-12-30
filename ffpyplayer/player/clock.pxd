
include '../includes/ffmpeg.pxi'


cdef class Clock(object):
    cdef:
        double pts           # clock base
        double pts_drift     # clock base minus time at which we updated the clock
        double last_updated
        double speed
        int serial           # clock is based on a packet with this serial
        int paused
        int *queue_serial    # pointer to the current packet queue serial, used for obsolete clock detection

    cdef void cInit(Clock self, int *queue_serial) nogil
    cdef double get_clock(Clock self) nogil
    cdef void set_clock_at(Clock self, double pts, int serial, double time) nogil
    cdef void set_clock(Clock self, double pts, int serial) nogil
    cdef void set_clock_speed(Clock self, double speed) nogil
    cdef void sync_clock_to_slave(Clock self, Clock slave) nogil
