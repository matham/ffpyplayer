'''
FFmpeg based image storage and conversion tools
===============================================

FFmpeg based classes to store and convert images from / to many different pixel
formats. See :class:`Image` and :class:`SWScale` for details.

Create an image in rgb24 format:

.. code-block:: python

    >>> w, h = 500, 100
    >>> size = w * h * 3
    >>> buf = bytearray([int(x * 255 / size) for x in range(size)])
    >>> img = Image(plane_buffers=[buf], pix_fmt='rgb24', size=(w, h))

Convert the image to a different size:

.. code-block:: python

    >>> sws = SWScale(w, h, img.get_pixel_format(), ow=w/2, oh=h/3)
    >>> img2 = sws.scale(img)
    >>> img2.get_size()
    (250, 33)

Convert the image to YUV420P and get the resulting plane buffers as bytearrays:

.. code-block:: python

    >>> sws = SWScale(w, h, img.get_pixel_format(), ofmt='yuv420p')
    >>> img2 = sws.scale(img)
    >>> img2.get_pixel_format()
    'yuv420p'
    >>> planes = img2.to_bytearray()
    >>> map(len, planes)
    [50000, 12500, 12500, 0]

Create an Image using default FFmpeg buffers:

.. code-block:: python

    >>> img = Image(pix_fmt='rgb24', size=(w, h))

Copy the image:

.. code-block:: python

    >>> import copy
    >>> # copy reference without actually copying the buffers
    >>> img2 = copy.copy(img)
    >>> # do deep copy
    >>> img2 = copy.deepcopy(img)
'''

__all__ = ('Image', 'SWScale', 'get_image_size', 'ImageLoader')

include "includes/inline_funcs.pxi"

from cpython.ref cimport PyObject
from cython cimport view as cyview

cdef extern from "string.h" nogil:
    void *memset(void *, int, size_t)
    void *memcpy(void *, const void *, size_t)

cdef extern from "Python.h":
    PyObject* PyString_FromStringAndSize(const char *, Py_ssize_t)
    void Py_DECREF(PyObject *)

import ffpyplayer.tools  # for initialization purposes

def get_image_size(pix_fmt, width, height):
    '''Returns the size in bytes of the buffers of each plane of an image with a
    given pixel format, width, and height.

    :Parameters:

        `pix_fmt`: str
            The pixel format in which the image is represented. Can be one of
            :attr:`~ffpyplayer.tools.pix_fmts`.
        `width`: int
            The width of the image.
        `height`: int
            The height of the image.

    :returns:

        `4-tuple of ints`:
            A tuple of buffer sizes in bytes for each plane of this pixel format
            required to store the image. Unused planes are zero.

    :

    .. code-block:: python

        >>> print get_image_size('rgb24', 100, 100)
        (30000, 0, 0, 0)
        >>> print get_image_size('yuv420p', 100, 100)
        (10000, 2500, 2500, 0)
        >>> print get_image_size('gray', 100, 100)
        (10000, 1024, 0, 0)
    '''
    cdef AVPixelFormat fmt
    cdef int res, w = width, h = height
    cdef int size[4]
    cdef int ls[4]
    cdef int req[4]
    cdef char msg[256]
    cdef bytes fmtb

    if not pix_fmt or not width or not height:
        return 0

    fmtb = pix_fmt.encode('utf8')
    fmt = av_get_pix_fmt(fmtb)
    if fmt == AV_PIX_FMT_NONE:
        raise Exception('Pixel format %s not found.' % pix_fmt)
    res = av_image_fill_linesizes(ls, fmt, w)
    if res < 0:
        raise Exception('Failed to initialize linesizes: ' + tcode(emsg(res, msg, sizeof(msg))))

    res = get_plane_sizes(size, req, fmt, h, ls)
    if res < 0:
        raise Exception('Failed to get planesizes: ' + tcode(emsg(res, msg, sizeof(msg))))
    return (size[0], size[1], size[2], size[3])


cdef class SWScale(object):
    '''Converts Images from one format and size to another format and size.

    The class accepts an Image of a given pixel format and size and converts it
    to another Image with a different pixel format and size. Each SWScale instance
    converts only images with parameters specified when creating the instance.

    :Parameters:

        `iw, ih`: int
            The width and height of the source image.
        `ifmt`: str
            The pixel format of the source image. Can be one of
            :attr:`ffpyplayer.tools.pix_fmts`.
        `ow, oh`: int
            The width and height of the output image after converting from the
            source image. A value of 0 will set that parameter to the source
            height/width. A value of -1 for one of the parameters, will result in
            a value of that parameter that maintains the original aspect ratio.
            Defaults to -1.
        `ofmt`: str
            The pixel format of the output image. Can be one of
            :attr:`ffpyplayer.tools.pix_fmts`. If empty, the source pixel format
            will be used. Defaults to empty string.

    :

    .. code-block:: python

        >>> w, h = 500, 100
        >>> size = w * h * 3
        >>> buf = bytearray([int(x * 255 / size) for x in range(size)])
        >>> img = Image(plane_buffers=[buf], pix_fmt='rgb24', size=(w, h))

        >>> # specify output w,h
        >>> sws = SWScale(w, h, img.get_pixel_format(), ow=w/2, oh=h/3)
        >>> img2 = sws.scale(img)
        >>> img2.get_size()
        (250, 33)

        >>> # use input height
        >>> sws = SWScale(w, h, img.get_pixel_format(), ow=w/2, oh=0)
        >>> img2 = sws.scale(img)
        >>> img2.get_size()
        (250, 100)

        >>> # keep aspect ratio
        >>> sws = SWScale(w, h, img.get_pixel_format(), ow=w/2)
        >>> img2 = sws.scale(img)
        >>> img2.get_size()
        (250, 50)

        >>> # convert rgb24 to yuv420p
        >>> sws = SWScale(w, h, img.get_pixel_format(), ofmt='yuv420p')
        >>> img2 = sws.scale(img)
        >>> img2.get_pixel_format()
        'yuv420p'

        >>> # convert into a previously allocated and aligned image
        >>> import math
        >>> align = lambda x: int(math.ceil(x / 32.) * 32)
        >>> img2 = Image(pix_fmt=img.get_pixel_format(), size=(w/2, h/2))
        >>> img2.get_linesizes(keep_align=True)
        (750, 0, 0, 0)
        >>> linesize = map(align, img2.get_linesizes())
        >>> linesize
        [768, 0, 0, 0]
        >>> img2 = Image(pix_fmt=img2.get_pixel_format(), size=img2.get_size(), linesize=linesize)
        >>> img2.get_linesizes(keep_align=True)
        (768, 0, 0, 0)
        >>> sws.scale(img, dst=img2)
        <ffpyplayer.pic.Image object at 0x02B44440>
        >>> img2
        <ffpyplayer.pic.Image object at 0x02B44440>

    '''

    def __cinit__(self, int iw, int ih, ifmt, int ow=-1, int oh=-1, ofmt='', **kargs):
        cdef AVPixelFormat src_pix_fmt, dst_pix_fmt
        self.dst_pix_fmt = ifmt.encode('utf8')
        self.dst_pix_fmt_s = ifmt

        self.sws_ctx = NULL
        src_pix_fmt = av_get_pix_fmt(self.dst_pix_fmt)
        if src_pix_fmt == AV_PIX_FMT_NONE:
            raise Exception('Pixel format %s not found.' % ifmt)
        dst_pix_fmt = src_pix_fmt
        if ofmt:
            self.dst_pix_fmt = ofmt.encode('utf8')
            self.dst_pix_fmt_s = ofmt
            dst_pix_fmt = av_get_pix_fmt(self.dst_pix_fmt)
            if dst_pix_fmt == AV_PIX_FMT_NONE:
                raise Exception('Pixel format %s not found.' % ofmt)
        if ow == -1 and oh == -1:
            ow = oh = 0
        if not oh:
            oh = ih
        if not ow:
            ow = iw
        if ow == -1:
            ow = <int>(oh / <double>ih * iw)
        if oh == -1:
            oh = <int>(ow / <double>iw * ih)
        self.dst_w = ow
        self.dst_h = oh
        self.src_pix_fmt = src_pix_fmt
        self.src_w = iw
        self.src_h = ih

        self.sws_ctx = sws_getCachedContext(NULL, iw, ih, src_pix_fmt, ow, oh,
                                            dst_pix_fmt, SWS_BICUBIC, NULL, NULL, NULL)
        if self.sws_ctx == NULL:
            raise Exception('Cannot initialize the conversion context.')

    def __dealloc__(self):
        if self.sws_ctx != NULL:
            sws_freeContext(self.sws_ctx)

    def scale(self, Image src, Image dst=None, int _flip=False):
        '''Scales a image into another image format and/or size as specified by the
        instance initialization parameters.

        :Parameters:

            `src`: :class:`Image`
                A image instance with values matching the source image specification
                of this instance. An exception is raised if the Image doesn't match.
                It will be used as the source image.
            `dst`: :class:`Image` or None
                A image instance with values matching the output image specification
                of this instance. An exception is raised if the Image doesn't match.
                If specified, the output image will be converted directly into this Image.
                If not specified, a new Image will be created and returned.
            `_flip`: bool, defaults to False
                Whether the image will be flipped before scaling. This only works
                for pixel formats whose color planes are the same size (e.g. rgb), so
                use with caution.

        :returns:

            :class:`Image`:
                The output image. If ``dst`` was not None ``dst`` will be returned,
                otherwise a new image containing the converted image will be returned.
        '''
        if (<AVPixelFormat>src.frame.format != self.src_pix_fmt or
            self.src_w != src.frame.width or self.src_h != src.frame.height):
            raise Exception("Source image doesn't match the specified input parameters.")
        if not dst:
            dst = Image.__new__(Image, pix_fmt=self.dst_pix_fmt_s,
                                size=(self.dst_w, self.dst_h))
        with nogil:
            if _flip:
                for i in range(4):
                    (<uint8_t * *>src.frame.data)[i] += src.frame.linesize[i] * (src.frame.height - 1)
                    src.frame.linesize[i] = -src.frame.linesize[i]
            sws_scale(self.sws_ctx, <const uint8_t *const *>src.frame.data, src.frame.linesize,
                          0, src.frame.height, dst.frame.data, dst.frame.linesize)
            if _flip:
                for i in range(4):
                    src.frame.linesize[i] = -src.frame.linesize[i]
                    (<uint8_t * *>src.frame.data)[i] -= src.frame.linesize[i] * (src.frame.height - 1)
        return dst


cdef int raise_exec(object ecls) nogil except 1:
    with gil:
        raise ecls()


cdef class Image(object):
    '''Stores a image using a specified pixel format.

    An Image can be represented by many different pixel formats, which determines
    how the buffer representing it is stored. We store the buffers as one to
    four arrays of bytes representing the one to four planes. For example,
    RGB23 has all the data in the first plane in the form of RGBRGB... while
    YUV420P uses the first three planes.

    The Image can be initialized with a list of the plane buffers, or internal
    buffers can be created when none are provided. Depending on how it's initialized
    one or more params need to be specified.

    :Paramters:

        `plane_buffers`: list
            A list of bytes or bytearray type objects representing the 1-4 planes.
            The number of planes is determined by ``pix_fmt`` (e.g. 1 for RGB24,
            3 for yuv). The length of the bytes object in each plane is a function
            of ``size``, and if provided, also ``linesize``. See ``linesize`` for details.
            The buffers are used directly without making any copies therefore, the
            bytes objects are kept alive internally as long as this instance is alive.

            If empty, internal buffers for the image will be created for the image.
        `pix_fmt`: str
            The pixel format of the image. Can be one of :attr:`ffpyplayer.tools.pix_fmts`.
            Must be provided when using ``plane_buffers``.
        `size`: 2-tuple of ints
            The size of the frame in the form of (width, height).
            Must be provided when using ``plane_buffers``.
        `linesize`: list of ints
            The linesize of each provided plane. In addition to the width of the frame,
            a linesize can be provided. The ``linesize`` represent the actual number of
            bytes in each line, and may be padded at the end to satisfy some alignment
            requirement. For example, a RGB24 frame of size ``(100, 10)`` will have
            ``3 * 100 = 300`` bytes in each horizontal line and will be 3000 bytes large.
            But, when 32 bit alignment is required, the buffer will have to padded at the
            end so that each line is 320 bytes, and the total buffer length is 3200 bytes.
            If ``linesize`` is provided, it must be provided for every valid plane.
            If it's not provided, an alignment of 1 (i.e. no alignment) is assumed.
            See :meth:`get_buffer_size` for more details.
        `no_create`: bool
            A optional argument, which if provided with True will just create the instance
            and not initialize anything. All other parameters are ignored when True.
            This is useful when instantiating later from cython with the ``cython_init`` method.

    **Copying**

    FFmpeg has an internal ref counting system where when used, it frees buffers
    it allocated only when there's no reference to it remaining thereby allowing
    multiple images to use the same buffer without making copies. When the
    Image class allocates the image buffers, e.g. when ``plane_buffers`` is empty
    such reference buffers are created. As a consequence, when copying the Image
    object, the buffers will not have to be copied.

    Using the python copy module you can do a **shallow** or a **deep** copy of
    the object. When doing a **shallow** copy, new buffers will be created if the
    original buffers were not FFmpeg created and referenced, e.g. if provided
    using ``plane_buffers``. This is to ensure the buffers won't
    go out of memory while in use.

    After the copy, the buffers will be "referenced" and additional copies will
    create more references without copying the buffers.
    A **deep** copy, however, will always create a new referenced buffer.
    The function :meth:`is_ref` indicates whether the image buffer is such a
    FFmpeg referenced buffer.

    :

    .. code-block:: python

        >>> w, h = 640, 480
        >>> size = w * h * 3
        >>> buf = bytearray([int(x * 255 / size) for x in range(size)])
        >>> img = Image(plane_buffers=[buf], pix_fmt='rgb24', size=(w, h))
        >>> img2 = Image(pix_fmt='rgb24', size=(w, h))
    '''

    def __cinit__(self, plane_buffers=[], pix_fmt='', size=(), linesize=[], **kwargs):
        cdef int i, w, h, res
        cdef object plane = None
        cdef char msg[256]
        cdef AVFrame *avframe
        cdef int buff_size[4]
        cdef int ls[4]
        cdef int req[4]
        cdef bytes fmt_b

        self.frame = NULL
        self.byte_planes = None

        if kwargs.get('no_create', False):
            return

        fmt_b = pix_fmt.encode('utf8')
        self.pix_fmt = av_get_pix_fmt(fmt_b)
        if self.pix_fmt == AV_PIX_FMT_NONE:
            raise Exception('Pixel format %s not found.' % pix_fmt)
        w, h = size
        self.frame = av_frame_alloc()
        if self.frame == NULL:
            raise MemoryError()

        self.frame.format = self.pix_fmt
        self.frame.width = w
        self.frame.height = h
        if linesize:
            for i in range(min(len(linesize), 4)):
                self.frame.linesize[i] = linesize[i]
        else:
            res = av_image_fill_linesizes(self.frame.linesize, self.pix_fmt, w)
            if res < 0:
                raise Exception('Failed to initialize linesizes: ' + tcode(emsg(res, msg, sizeof(msg))))
        av_image_fill_linesizes(ls, self.pix_fmt, w)
        for i in range(4):
            if ls[i] and not self.frame.linesize[i]:
                raise Exception('Incorrect linesize provided.')

        if plane_buffers:
            self.byte_planes = []
            res = get_plane_sizes(buff_size, req, self.pix_fmt, self.frame.height, self.frame.linesize)
            if res < 0:
                raise Exception('Failed to get plane sizes: ' + tcode(emsg(res, msg, sizeof(msg))))
            for i in range(4):
                if req[i] and buff_size[i] and (len(plane_buffers) <= i or not plane_buffers[i]):
                    raise Exception('Required plane %d not provided for %s' % (i, pix_fmt))
                if len(plane_buffers) > i and plane_buffers[i] and not buff_size[i]:
                    raise Exception('Unused plane %d provided for %s' % (i, pix_fmt))
            for i in range(4):
                if len(plane_buffers) == i:
                    break
                if not plane_buffers[i]:
                    continue
                plane = plane_buffers[i]
                if len(plane) < buff_size[i]:
                    raise Exception('Buffer for plane %d is too small, required buffer size is %d.'\
                                    % (i, buff_size[i]))
                self.byte_planes.append(plane)
                self.frame.data[i] = plane
        else:
            with nogil:
                res = av_frame_get_buffer(self.frame, 32)
            if res < 0:
                raise Exception('Could not allocate avframe buffer of size %dx%d: %s'\
                                % (w, h, tcode(emsg(res, msg, sizeof(msg)))))

    def __dealloc__(self):
        av_frame_free(&self.frame)

    cdef int cython_init(self, AVFrame *frame) nogil except 1:
        '''Can be called only once after object creation and it creates a internal
        reference to ``frame``.
        '''
        self.frame = av_frame_clone(frame)
        if self.frame == NULL:
            raise_exec(MemoryError)
        self.pix_fmt = <AVPixelFormat>self.frame.format
        return 0

    def __copy__(self):
        cdef Image img = Image.__new__(Image, no_create=True)
        with nogil:
            img.cython_init(self.frame)
        return img

    def __deepcopy__(self, memo):
        cdef AVFrame *frame = av_frame_alloc()
        cdef Image img
        if frame == NULL:
            raise MemoryError()

        frame.format = self.frame.format
        frame.width = self.frame.width
        frame.height = self.frame.height
        if av_frame_copy_props(frame, self.frame) < 0:
            av_frame_free(&frame)
            raise Exception('Cannot copy frame properties.')
        if av_frame_get_buffer(frame, 32) < 0:
            av_frame_free(&frame)
            raise Exception('Cannot allocate frame buffers.')

        img = Image.__new__(Image, no_create=True)
        with nogil:
            av_image_copy(frame.data, frame.linesize, <const uint8_t **>self.frame.data,
                          self.frame.linesize, <AVPixelFormat>frame.format,
                          frame.width, frame.height)
            img.cython_init(frame)
            av_frame_free(&frame)
        return img

    cpdef is_ref(Image self):
        '''Returns whether the image buffer is FFmpeg referenced. This can only be
        True when the buffers were allocated internally or by FFmpeg bit not when
        ``plane_buffers`` is provided. See :class:`Image` for details. After a copy,
        it will always returns True.

        :returns:

            bool: True if the buffer is FFmpeg referenced.

        For example:

        .. code-block:: python

            >>> w, h = 640, 480
            >>> img = Image(plane_buffers=[bytes(' ') * (w * h * 3)], pix_fmt='rgb24', size=(w, h))
            >>> img.is_ref()
            False
            >>> import copy
            >>> img2 = copy.copy(img)
            >>> img2.is_ref()
            True

        Or if directly allocated internally:

        .. code-block:: python

            >>> img = Image(pix_fmt='rgb24', size=(w, h))
            >>> img.is_ref()
            True
        '''
        return self.frame.buf[0] != NULL

    cpdef is_key_frame(Image self):
        '''Returns whether the image is a key frame.

        :returns:

            bool: True if the image was a key frame.
        '''
        return self.frame.key_frame == 1

    cpdef get_linesizes(Image self, keep_align=False):
        '''Returns the linesize of each plane.

        The linesize is the actual number of bytes in each horizontal line for a given plane,
        which may be padded at the end to satisfy some alignment requirement.
        For example, a RGB24 frame of size ``(100, 10)`` will have ``3 * 100 = 300``
        bytes in each line and will be 3000 bytes large. But, when 32 bit
        alignment is required, the buffer will have to padded at the end so
        that each line is 320 bytes, and the total buffer length is 3200 bytes.

        :Parameters:

            `keep_align`: bool
                If True, the original linesize alignments of the image will be returned for
                every plane. If False, linesize with an alignment of 1 (i.e. no alignment)
                will be used, returning the minimal linesize required to for the image.
                Defaults to False.

        :returns:

            4-tuple of ints:
                A 4 tuple with the linesizes of each plane. If the plane isn't used
                it'll be 0.

        By defaults there's no alignment:

        .. code-block:: python

            >>> w, h = 100, 10
            >>> img = Image(plane_buffers=[bytes(' ') * (w * h * 3)],
            ... pix_fmt='rgb24', size=(w, h))
            >>> img.get_linesizes(keep_align=True)
            (300, 0, 0, 0)

        You can force alignment e.g. 32 bits alignment:

        .. code-block:: python

            >>> import math
            >>> linesize = [int(math.ceil(w * 3 / 32.) * 32)]
            >>> linesize
            [320]
            >>> img = Image(plane_buffers=[bytes(' ') * (h * linesize[0])],
            ... pix_fmt='rgb24', size=(w, h), linesize=linesize)
            >>> img.get_linesizes(keep_align=True)
            (320, 0, 0, 0)
            >>> img.get_size()
            (100, 10)

        The linesizes of an unaligned and 32 bit aligned yuv420p image:

        .. code-block:: python

            >>> img = Image(pix_fmt='yuv420p', size=(w, h))
            >>> img.get_linesizes(keep_align=True)
            (100, 50, 50, 0)
            >>> img.get_size()
            (100, 10)

            >>> # now try align to 32 bit
            >>> linesize = img.get_linesizes(keep_align=True)
            >>> align = lambda x: int(math.ceil(x / 32.) * 32)
            >>> linesize = map(align, linesize)
            >>> linesize
            [128, 64, 64, 0]
            >>> img = Image(pix_fmt='yuv420p', size=(w, h), linesize=linesize)
            >>> img.get_linesizes(keep_align=True)
            (128, 64, 64, 0)
            >>> img.get_linesizes()
            (100, 50, 50, 0)
            >>> img.get_size()
            (100, 10)
        '''
        cdef int lsl[4]
        cdef int *ls = self.frame.linesize

        if not keep_align:
            av_image_fill_linesizes(lsl, self.pix_fmt, self.frame.width)
            ls = lsl
        return (ls[0], ls[1], ls[2], ls[3])

    cpdef get_size(Image self):
        '''Returns the size of the frame.

        :returns:

            2-tuple of ints: The size of the frame as ``(width, height)``.

        ::

            >>> img.get_size()
            (640, 480)
        '''
        return (self.frame.width, self.frame.height)

    cpdef get_pixel_format(Image self):
        '''Returns the pixel format of the image. Can be one of
        :attr:`ffpyplayer.tools.pix_fmts`.

        :returns:

            str: The pixel format of the image.

        ::

            >>> img.get_pixel_format()
            'rgb24'
        '''
        return tcode(av_get_pix_fmt_name(self.pix_fmt))

    cpdef get_buffer_size(Image self, keep_align=False):
        '''Returns the size of the buffers of each plane.

        :Parameters:

            `keep_align`: bool
                If True, the linesize alignments of the actual image will be used to
                calculate the buffer size for each plane. If False, an alignment of 1
                (i.e. no alignment) will be used, returning the minimal buffer size
                required to store the image. Defaults to False.

        :returns:

            4-tuple of ints:
                A list of buffer sizes for each plane of this pixel format.

        A (unaligned) yuv420p image has 3 planes:

        .. code-block:: python

            >>> w, h = 100, 10
            >>> img = Image(pix_fmt='yuv420p', size=(w, h))
            >>> img.get_linesizes(keep_align=True)
            (100, 50, 50, 0)
            >>> img.get_buffer_size()
            (1000, 250, 250, 0)

            >>> # align to 32 bits
            >>> linesize = img.get_linesizes(keep_align=True)
            >>> align = lambda x: int(math.ceil(x / 32.) * 32)
            >>> linesize = map(align, linesize)
            >>> linesize
            [128, 64, 64, 0]
            >>> img = Image(pix_fmt='yuv420p', size=(w, h), linesize=linesize)
            >>> img.get_linesizes(keep_align=True)
            (128, 64, 64, 0)
            >>> img.get_buffer_size(keep_align=True)
            (1280, 320, 320, 0)
            >>> img.get_buffer_size()
            (1000, 250, 250, 0)
        '''
        cdef int res
        cdef int size[4]
        cdef int ls[4]
        cdef int req[4]
        cdef char msg[256]

        if keep_align:
            memcpy(ls, self.frame.linesize, sizeof(ls))
        else:
            res = av_image_fill_linesizes(ls, self.pix_fmt, self.frame.width)
            if res < 0:
                raise Exception('Failed to initialize linesizes: ' + tcode(emsg(res, msg, sizeof(msg))))

        res = get_plane_sizes(size, req, <AVPixelFormat>self.frame.format, self.frame.height, ls)
        if res < 0:
            raise Exception('Failed to get planesizes: ' + tcode(emsg(res, msg, sizeof(msg))))
        return (size[0], size[1], size[2], size[3])

    cpdef get_required_buffers(Image self):
        '''Returns a 4 tuple of booleans indicating which of the 4 planes are required
        (i.e. even if get_buffer_size is non-zero for that plane it may still be
        optional).
        '''
        cdef int res
        cdef int size[4]
        cdef int ls[4]
        cdef int req[4]
        cdef char msg[256]

        memcpy(ls, self.frame.linesize, sizeof(ls))
        res = get_plane_sizes(size, req, <AVPixelFormat>self.frame.format, self.frame.height, ls)
        if res < 0:
            raise Exception('Failed to get planesizes: ' + tcode(emsg(res, msg, sizeof(msg))))
        return (req[0], req[1], req[2], req[3])

    cpdef to_bytearray(Image self, keep_align=False):
        '''Returns a copy of the plane buffers as bytearrays.

        :Parameters:

            `keep_align`: bool
                If True, the buffer for each plane will be padded after each horizontal
                line to match the linesize of its plane in this image. If False, an
                alignment of 1 (i.e. no alignment) will be used, returning the
                maximially packed buffer of this plane. Defaults to False.

        :returns:

            4-element list: A list of bytearray buffers for each plane of this
            pixel format. An empty bytearray is returned for unused planes.

        Get the buffer of an RGB image:

        .. code-block:: python

            >>> w, h = 100, 10
            >>> img = Image(pix_fmt='rgb24', size=(w, h))
            >>> img.get_linesizes(keep_align=True)
            (300, 0, 0, 0)
            >>> map(len, img.to_bytearray())
            [3000, 0, 0, 0]

        Get the buffers of a YUV420P image:

        .. code-block:: python

            >>> img = Image(pix_fmt='yuv420p', size=(w, h))
            >>> linesize = img.get_linesizes(keep_align=True)
            >>> linesize
            (100, 50, 50, 0)
            >>> align = lambda x: int(math.ceil(x / 32.) * 32)
            >>> linesize = map(align, linesize)
            >>> linesize
            [128, 64, 64, 0]

            >>> img = Image(pix_fmt='yuv420p', size=(w, h), linesize=linesize)
            >>> map(len, img.to_bytearray())
            [1000, 250, 250, 0]
            >>> map(len, img.to_bytearray(keep_align=True))
            [1280, 320, 320, 0]

            >>> # now initialize a new Image with it
            >>> img2 = Image(plane_buffers=img.to_bytearray(),
            ... pix_fmt=img.get_pixel_format(), size=img.get_size())
            >>> img2.get_buffer_size(keep_align=True)
            (1000, 250, 250, 0)

            >>> # keep alignment
            >>> img2 = Image(plane_buffers=img.to_bytearray(keep_align=True),
            ... pix_fmt=img.get_pixel_format(), size=img.get_size(),
            ... linesize=img.get_linesizes(keep_align=True))
            >>> img2.get_buffer_size(keep_align=True)
            (1280, 320, 320, 0)

        '''
        cdef list planes = [None, None, None, None]
        cdef int i, res
        cdef uint8_t *data[4]
        cdef int size[4]
        cdef int ls[4]
        cdef int req[4]
        cdef char msg[256]
        memset(data, 0, sizeof(data))

        if keep_align:
            memcpy(ls, self.frame.linesize, sizeof(ls))
        else:
            res = av_image_fill_linesizes(ls, self.pix_fmt, self.frame.width)
            if res < 0:
                raise Exception('Failed to initialize linesizes: ' + tcode(emsg(res, msg, sizeof(msg))))

        res = get_plane_sizes(size, req, <AVPixelFormat>self.frame.format, self.frame.height, ls)
        if res < 0:
            raise Exception('Failed to get plane sizes: ' + tcode(emsg(res, msg, sizeof(msg))))
        for i in range(4):
            planes[i] = bytearray(b'\0') * size[i]
            if size[i]:
                data[i] = planes[i]
        with nogil:
            av_image_copy(data, ls, <const uint8_t **>self.frame.data, self.frame.linesize,
                          <AVPixelFormat>self.frame.format, self.frame.width, self.frame.height)
        return planes

    cpdef to_memoryview(Image self, keep_align=False):
        '''Returns a memoryviews of the buffers of the image.

        :Parameters:

            `keep_align`: bool
                If True, the buffers of the original image will be returned
                without making any additional copies. If False, then if the
                image alignment is already 1, the original buffers will be
                returned, otherwise, new buffers will be created with an
                alignment of 1 and the buffers will be copied into them
                and returned. See :meth:`to_bytearray`.

        :Returns:

            4-element list:
                A list of cython arrays for each plane of this
                image's pixel format. If the data didn't have to be copied, the
                arrays point directly to the original image data. The arrays
                can be used where memoryviews are accepted, since cython arrays
                implement the memoryview interface.

                Unused planes are set to None.

        .. warning::
            If the data points to the original image data, you must ensure
            that this :class:`Image` instance does not go out of memory
            while the returned memoryviews of the arrays are in use. Otherwise when
            the :class:`Image` goes out of memory, the original data will become
            invalid and usage of the returned memoryviews of them will crash python.

        Get the buffer of an RGB image:

        .. code-block:: python

            >>> w, h = 100, 10
            >>> img = Image(pix_fmt='rgb24', size=(w, h))
            >>> img.get_linesizes(keep_align=True)
            (300, 0, 0, 0)
            >>> img.to_memoryview()
            [<ffpyplayer.pic.array object at 0x055DCE58>, None, None, None]
            >>> arr = img.to_memoryview()[0]
            >>> # memview is the only attribute of cython arrays
            >>> arr.memview
            <MemoryView of 'array' at 0x55d1468>
            >>> arr.memview.size
            3000
        '''
        cdef list planes = [None, None, None, None]
        cdef cyview.array cyarr
        cdef int i, res
        cdef int size[4]
        cdef char *data[4]
        cdef int ls[4]
        cdef int req[4]
        cdef int *cls = self.frame.linesize
        cdef char msg[256]
        memset(data, 0, sizeof(data))

        res = av_image_fill_linesizes(ls, self.pix_fmt, self.frame.width)
        if res < 0:
            raise Exception('Failed to initialize linesizes: ' +
                            tcode(emsg(res, msg, sizeof(msg))))

        if keep_align or (cls[0] == ls[0] and cls[1] == ls[1] and
                          cls[2] == ls[2] and cls[3] == ls[3]):
            res = get_plane_sizes(size, req, <AVPixelFormat>self.frame.format,
                                  self.frame.height, self.frame.linesize)
            if res < 0:
                raise Exception('Failed to get plane sizes: ' + tcode(emsg(res, msg, sizeof(msg))))

            for i in range(4):
                if not size[i]:
                    continue
                planes[i] = cyarr = cyview.array(shape=(size[i], ), itemsize=sizeof(char),
                format="B", mode="c", allocate_buffer=False)
                cyarr.data = <char *>self.frame.data[i]
            return planes

        res = get_plane_sizes(size, req, <AVPixelFormat>self.frame.format, self.frame.height, ls)
        if res < 0:
            raise Exception('Failed to get plane sizes: ' + tcode(emsg(res, msg, sizeof(msg))))
        for i in range(4):
            if not size[i]:
                continue
            planes[i] = cyarr = cyview.array(shape=(size[i], ), itemsize=sizeof(char),
            format="B", mode="c", allocate_buffer=True)
            data[i] = cyarr.data

        with nogil:
            av_image_copy(<uint8_t **>data, ls, <const uint8_t **>self.frame.data, self.frame.linesize,
                          <AVPixelFormat>self.frame.format, self.frame.width, self.frame.height)
        return planes


cdef class ImageLoader(object):
    '''Class that reads one or more images from a file and returns them.

    :Parameters:

        `filename`: string type
            The full path to the image file. The string will first be encoded
            using utf8 before passing to FFmpeg.

    For example, reading a simple png using the iterator syntax:

    .. code-block:: python

        >>> img = ImageLoader('file.png')
        >>> images = [m for m in img]
        >>> images
        [(<ffpyplayer.pic.Image object at 0x02B5F5D0>, 0.0)]

    Or reading it directly:

    .. code-block:: python

        >>> img = ImageLoader('file.png')
        >>> img.next_frame()
        (<ffpyplayer.pic.Image object at 0x02B74850>, 0.0)
        >>> img.next_frame()
        (None, 0)
        >>> img.next_frame()
        (None, 0)

    Or reading a gif using the iterator syntax:

    .. code-block:: python

        >>> img = ImageLoader('sapo11.gif')
        >>> images = [m for m in img]
        >>> images
        [(<ffpyplayer.pic.Image object at 0x02B749B8>, 0.0),
        (<ffpyplayer.pic.Image object at 0x02B74918>, 0.08),
        (<ffpyplayer.pic.Image object at 0x02B74990>, 0.22),
        (<ffpyplayer.pic.Image object at 0x02B749E0>, 0.36),
        (<ffpyplayer.pic.Image object at 0x02B74A08>, 0.41000000000000003),
        (<ffpyplayer.pic.Image object at 0x02B74A30>, 0.46),
        (<ffpyplayer.pic.Image object at 0x02B74A58>, 0.51)]

    Or reading it directly:

    .. code-block:: python

        >>> img = ImageLoader('sapo11.gif')
        >>> img.next_frame()
        (<ffpyplayer.pic.Image object at 0x02B74B70>, 0.0)
        >>> img.next_frame()
        (<ffpyplayer.pic.Image object at 0x02B74C60>, 0.08)
        ...
        >>> img.next_frame()
        (<ffpyplayer.pic.Image object at 0x02B74B70>, 0.51)
        >>> img.next_frame()
        (None, 0)
        >>> img.next_frame()
        (None, 0)
    '''

    def __cinit__(self, filename, **kwargs):

        cdef AVDictionary *opts = NULL
        cdef const AVDictionaryEntry *t = NULL
        cdef int ret = 0
        cdef char *fname

        fname = self.filename = filename.encode('utf8')
        self.format_ctx = NULL
        self.codec = NULL
        self.codec_ctx = avcodec_alloc_context3(NULL)
        if self.codec_ctx == NULL:
            raise MemoryError()

        self.frame = NULL
        self.eof = 0
        av_init_packet(&self.pkt)

        with nogil:
            ret = avformat_open_input(&self.format_ctx, fname, NULL, NULL)
        if ret < 0:
            raise Exception("Failed to open input file {}: {}".format(filename,
                            tcode(emsg(ret, self.msg, sizeof(self.msg)))))

        ret = avcodec_parameters_to_context(self.codec_ctx, self.format_ctx.streams[0].codecpar)
        if ret < 0:
            raise Exception("Failed to open input file {}: {}".format(filename,
                            tcode(emsg(ret, self.msg, sizeof(self.msg)))))

        self.codec = avcodec_find_decoder(self.codec_ctx.codec_id)
        if self.codec is NULL:
            raise Exception("Failed to find supported codec for file {}"
                            .format(filename))

        with nogil:
            ret = avcodec_open2(self.codec_ctx, self.codec, &opts)
        if ret < 0:
            raise Exception("Failed to open codec for {}: {}".format(filename,
                            tcode(emsg(ret, self.msg, sizeof(self.msg)))))
        t = av_dict_get(opts, "", NULL, AV_DICT_IGNORE_SUFFIX)
        if t != NULL:
            raise Exception("Option {} not found.".format(t.key))

    def __dealloc__(self):
        with nogil:
            av_packet_unref(&self.pkt)
            av_frame_free(&self.frame)
            avformat_close_input(&self.format_ctx)
            if self.codec_ctx != NULL:
                avcodec_free_context(&self.codec_ctx)

    def __iter__(self):
        while True:
            res = self.next_frame()
            if res == (None, 0):
                break
            yield res

    cpdef next_frame(self):
        ''' Returns the next available frame, or `(None, 0)` if there are no
        more frames available.

        :returns:
            a 2-tuple of `(:class:`Image`, pts)`:
            Where the first element is the next image to be displayed and `pts`
            is the time, relative to the first frame, when to display it e.g. in
            the case of a gif.

            If we reached the eof of the file and there are no more frames
            to be returned, it returns `(None, 0)`.

        .. warning::

            Both :meth:`next_frame` and the iterator syntax read the frames
            identically. Consequently, calling one, will also advance the frame
            for the other.
        '''

        cdef int frame_decoded, ret = 0
        cdef Image image
        cdef double t = 0

        if self.eof:
            return self.eof_frame()

        with nogil:
            ret = av_read_frame(self.format_ctx, &self.pkt)
        if ret < 0:
            if ret == AVERROR_EOF:
                self.eof = 1
                self.pkt.data = NULL
                return self.eof_frame()
            raise Exception("Failed to read frame: {}",
                            tcode(emsg(ret, self.msg, sizeof(self.msg))))

        with nogil:
            self.frame = av_frame_alloc()
        if self.frame is NULL:
            raise MemoryError("Failed to alloc frame")

        with nogil:
            ret = avcodec_send_packet(self.codec_ctx, &self.pkt)
            if ret >= 0:
                ret = avcodec_receive_frame(self.codec_ctx, self.frame)
        if ret < 0:
            if ret == AVERROR_EOF:
                self.eof = 1
                self.pkt.data = NULL
                return self.eof_frame()
            raise Exception("Failed to decode image from file")

        self.frame.pts = self.frame.best_effort_timestamp
        if self.frame.pts == AV_NOPTS_VALUE:
            t = 0.
        else:
            t = av_q2d(self.format_ctx.streams[0].time_base) * self.frame.pts

        image = Image(no_create=True)
        image.cython_init(self.frame)

        av_packet_unref(&self.pkt)
        av_frame_free(&self.frame)
        return image, t

    cdef inline object eof_frame(self):
        '''Used to flush the remaining frames until no more cached.
        '''
        cdef int ret = 0
        cdef Image image
        cdef double t = 0
        if self.eof == 2:
            return None, 0

        with nogil:
            self.frame = av_frame_alloc()
        if self.frame is NULL:
            raise MemoryError("Failed to alloc frame")

        with nogil:
            ret = avcodec_send_packet(self.codec_ctx, &self.pkt)
            if ret >= 0:
                ret = avcodec_receive_frame(self.codec_ctx, self.frame)
        if ret < 0:
            self.eof = 2
            av_frame_free(&self.frame)
            return None, 0

        self.frame.pts = self.frame.best_effort_timestamp
        if self.frame.pts == AV_NOPTS_VALUE:
            t = 0.
        else:
            t = av_q2d(self.format_ctx.streams[0].time_base) * self.frame.pts
        image = Image(no_create=True)
        image.cython_init(self.frame)
        av_frame_free(&self.frame)
        return image, t
