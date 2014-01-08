'''
FFmpeg based image storage and conversion tools
===============================================

FFmpeg based classes to store and convert images from / to many different pixel
formats. See :class:`Image` and :class:`SWScale` for details.

Create an image in rgb24 format::

    >>> w, h = 500, 100
    >>> size = w * h * 3
    >>> buf = [int(x * 255 / size) for x in range(size)]
    >>> buf = ''.join(map(chr, buf))
    >>> img = Image(plane_buffers=[buf], pix_fmt='rgb24', size=(w, h))

Convert the image to a different size::

    >>> sws = SWScale(w, h, img.get_pixel_format(), ow=w/2, oh=h/3)
    >>> img2 = sws.scale(img)
    >>> img2.get_size()
    (250, 33)

Convert the image to YUV420P and get the resulting plane buffers as bytearrays::

    >>> sws = SWScale(w, h, img.get_pixel_format(), ofmt='yuv420p')
    >>> img2 = sws.scale(img)
    >>> img2.get_pixel_format()
    'yuv420p'
    >>> planes = img2.to_bytearray()
    >>> map(len, planes)
    [50000, 12500, 12500, 0]

Create an Image using default FFmpeg buffers::

    >>> img = Image(pix_fmt='rgb24', size=(w, h))

Copy the image::

    >>> import copy
    >>> # copy reference without actually copying the buffers
    >>> img2 = copy.copy(img)
    >>> # do deep copy
    >>> img2 = copy.deepcopy(img)
'''

__all__ = ('Image', 'SWScale', 'get_image_size')


include "inline_funcs.pxi"

from cpython.ref cimport PyObject

cdef extern from "string.h" nogil:
    void *memset(void *, int, size_t)
    void *memcpy(void *, const void *, size_t)

cdef extern from "Python.h":
    PyObject* PyString_FromStringAndSize(const char *, Py_ssize_t)
    void Py_DECREF(PyObject *)


def get_image_size(pix_fmt, width, height):
    '''
    Returns the size in bytes of the buffers of each plane of an image with a
    given pixel format, width, and height.

    **Args**:
        *pix_fmt* (str): The pixel format in which the image is represented.
        Can be one of :attr:`ffpyplayer.tools.pix_fmts`.

        *width, height* (int): The width and height of the image.

    **Returns**:
        (4-tuple): A list of buffer sizes in bytes for each plane of this pixel
        format, required to store the image.

    ::

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
    cdef char msg[256]

    fmt = av_get_pix_fmt(pix_fmt)
    if fmt == AV_PIX_FMT_NONE:
        raise Exception('Pixel format %s not found.' % pix_fmt)
    res = av_image_fill_linesizes(ls, fmt, w)
    if res < 0:
        raise Exception('Failed to initialize linesizes: ' + emsg(res, msg, sizeof(msg)))

    res = get_plane_sizes(size, fmt, h, ls)
    if res < 0:
        raise Exception('Failed to get planesizes: ' + emsg(res, msg, sizeof(msg)))
    return (size[0], size[1], size[2], size[3])


cdef class SWScale(object):
    '''
    Converts Images from one format and size to another format and size.

    The class accepts an Image of a given pixel format and size and converts it
    to another Image with a different pixel format and size. Each SWScale instance
    converts only images with parameters specified when creating the instance.

    **Args**:
        *iw, ih* (int): The width and height of the source image.

        *ifmt* (str): The pixel format of the source image. Can be one of
        :attr:`ffpyplayer.tools.pix_fmts`.

        *ow, oh* (int): The width and height of the output image after
        converting from the source image. A value of 0 will set that parameter
        to the source height/width. A value of -1 for one of the parameters,
        will result in a value of that parameter that maintains the original
        aspect ratio. Defaults to -1.

        *ofmt* (str): The pixel format of the output image. Can be one of
        :attr:`ffpyplayer.tools.pix_fmts`. If empty, the source pixel format
        will be used. Defaults to empty string.

    ::

        >>> w, h = 500, 100
        >>> size = w * h * 3
        >>> buf = [int(x * 255 / size) for x in range(size)]
        >>> buf = ''.join(map(chr, buf))
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

        self.sws_ctx = NULL
        src_pix_fmt = av_get_pix_fmt(ifmt)
        if src_pix_fmt == AV_PIX_FMT_NONE:
            raise Exception('Pixel format %s not found.' % ifmt)
        dst_pix_fmt = src_pix_fmt
        self.dst_pix_fmt = ifmt
        if ofmt:
            self.dst_pix_fmt = ofmt
            dst_pix_fmt = av_get_pix_fmt(ofmt)
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

    def __init__(self, int iw, int ih, ifmt, int ow=-1, int oh=-1, ofmt='', **kargs):
        pass

    def __dealloc__(self):
        if self.sws_ctx != NULL:
            sws_freeContext(self.sws_ctx)

    def scale(self, Image src, Image dst=None):
        '''
        Scales a image into another image format and/or size as specified by the
        instance initialization parameters.

        **Args**:
            *src* (:class:`Image`): A image instance with values matching the source
            image specification of this instance. An exception is raised if the
            Image doesn't match. It will be used as the source image.

            *dst* (:class:`Image` or None): A image instance with values matching
            the output image specification of this instance. An exception is raised
            if the Image doesn't match. If specified, the output image will be
            converted directly into this Image. If not specified, a new Image
            will be created and returned.

        **Returns**:
            (:class:`Image`): The output image. If *dst* was not None *dst* will
            be returned, otherwise a new image containing the converted image
            will be returned.
        '''
        if (<AVPixelFormat>src.frame.format != self.src_pix_fmt or
            self.src_w != src.frame.width or self.src_h != src.frame.height):
            raise Exception("Source image doesn't match the specified input parameters.")
        if not dst:
            dst = Image(pix_fmt=self.dst_pix_fmt, size=(self.dst_w, self.dst_h))
        with nogil:
            sws_scale(self.sws_ctx, <const uint8_t *const *>src.frame.data, src.frame.linesize,
                          0, src.frame.height, dst.frame.data, dst.frame.linesize)
        return dst


cdef class Image(object):
    '''
    Stores a image buffer in a given pixel format.

    An Image can be represented by many different pixel formats, which determines
    how the buffer representing it is stored. We store the buffers as one to
    four arrays of bytes representing the one to four planes. For example,
    RGB23 has all the data in the first plane in the form of RGBRGB... while
    YUV420P uses the first three planes.

    The Image can be initialized with a list of the plane buffers, a reference
    to an FFmpeg frame, or internal buffers can be created when none are provided.
    Depending on how it's initialized one or more params need to be specified.

    **Args**:
        *plane_buffers* (list): A list of bytes or bytearray type objects representing the
        planes. The number of planes is determined by *pix_fmt* (e.g. 1 for RGB24,
        3 for yuv). The length of the bytes object in each plane is a function
        of *size*, and if provided, also *linesize*. See *linesize* for details.
        The buffers are used directly without making any copies therefore, the
        bytes objects are kept alive internally as long as this instance is alive.

        *plane_ptrs* (list): A list of python ints, representing c pointers to the
        planes. The number of planes is determined by *pix_fmt* (e.g. 1 for RGB24,
        3 for yuv). The length of the array in each plane is a function of *size*,
        and if provided, also *linesize*. See *linesize* for details. The arrays
        are used directly without making any copies, therefore, they must remain
        valid for as long as this instance is alive. The ints should be size_t
        in c and represent uint8_t pointers. This should really only be used
        from within Cython.

        *frame* (python int): A reference to an FFmpeg internal frame. This should
        only be used in Cython. It's a pointer to a AVFrame which has been cast
        to a size_t. The frame should be a fully initialized frame. None of the
        other params need to be specified. The frame is cloned and buffers are
        copied if the originals are not reference counted to ensure they remain
        valid.

        *pix_fmt* (str): The pixel format of the image. Can be one of
        :attr:`ffpyplayer.tools.pix_fmts`. Must be provided when using
        *plane_buffers* or *plane_ptrs*.

        *size* (2-tuple): The size of the frame in the form of (width, height).
        Must be provided when using *plane_buffers* or *plane_ptrs*.

        *linesize* (list): The linesize of each provided plane. In addition to
        the width of the frame, a linesize can be provided. The *linesize* represent
        the actual number of bytes in each line, and may be padded at the end
        to satisfy some alignment requirement. For example, a RGB24 frame of size
        (100, 10) will have 3 * 100 = 300 bytes in each line and will be 3000 bytes
        large. But, when 32 bit alignment is required, the buffer will have to
        padded at the end so that each line is 320 bytes, and the total buffer
        length is 3200 bytes. If *linesize* is provided, it must be provided for
        every valid plane. If it's not provided, an alignment of 1 (i.e. no
        alignment) is assumed. See :meth:`get_buffer_size` for more details.

    **Copying**

    FFmpeg has an internal ref counting system where when used, it frees buffers
    it allocated only when there's no reference to it remaining thereby allowing
    multiple images to use the same buffer without making copies. When the
    Image class allocates the image buffers, e.g. when no image is provided,
    such reference buffers are created. As a consequence, when copying the Image
    object, the buffers may not have to be copied.

    Using the python copy module you can do a **shallow** or a **deep** copy of
    the object. When doing a *shallow* copy new buffers will be created if the
    original buffers were not FFmpeg created and referenced, e.g. if provided
    using *plane_buffers* or *plane_ptrs*. This is to ensure the buffers won't
    go out of memory while in use. After the copy, the buffers will be referenced
    and additional copies will create more references without copying the buffers.
    A *deep* copy, however, will always create a new referenced buffer.
    The function :meth:`is_ref` indicates whether the image buffer is such a
    FFmpeg referenced buffer.

    ::

        >>> w, h = 640, 480
        >>> size = w * h * 3
        >>> buf = [int(x * 255 / size) for x in range(size)]
        >>> buf = ''.join(map(chr, buf))
        >>> img = Image(plane_buffers=[buf], pix_fmt='rgb24', size=(w, h))
        >>> img2 = Image(pix_fmt='rgb24', size=(w, h))
    '''

    def __cinit__(self, plane_buffers=[], plane_ptrs=[], frame=0, pix_fmt='',
                  size=(), linesize=[], **kargs):
        cdef int i, w, h, res
        cdef object plane = None
        cdef char msg[256]
        cdef AVFrame *avframe
        cdef int buff_size[4]
        cdef int ls[4]

        self.frame = NULL
        self.byte_planes = None

        if frame:
            avframe = <AVFrame *><size_t>frame
            with nogil:
                self.frame = av_frame_clone(avframe)
            if self.frame == NULL:
                raise MemoryError()
            self.pix_fmt = <AVPixelFormat>self.frame.format
            return

        self.pix_fmt = av_get_pix_fmt(pix_fmt)
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
                raise Exception('Failed to initialize linesizes: ' + emsg(res, msg, sizeof(msg)))
        av_image_fill_linesizes(ls, self.pix_fmt, w)
        for i in range(4):
            if ls[i] and not self.frame.linesize[i]:
                raise Exception('Incorrect linesize provided.')

        if plane_buffers:
            self.byte_planes = []
            res = get_plane_sizes(buff_size, self.pix_fmt, self.frame.height, self.frame.linesize)
            if res < 0:
                raise Exception('Failed to get plane sizes: ' + emsg(res, msg, sizeof(msg)))
            for i in range(4):
                if len(plane_buffers) == i:
                    if buff_size[i]:
                        raise Exception('Not enough planes provided for %s' % pix_fmt)
                    break
                plane = plane_buffers[i]
                if len(plane) < buff_size[i]:
                    raise Exception('Buffer for plane %d is too small, required buffer size is %d.'\
                                    % (i, buff_size[i]))
                self.byte_planes.append(plane)
                self.frame.data[i] = plane
        elif plane_ptrs:
            for i in range(len(plane_ptrs)):
                self.frame.data[i] = <uint8_t *><size_t>plane_ptrs[i]
        else:
            with nogil:
                res = av_frame_get_buffer(self.frame, 32)
            if res < 0:
                raise Exception('Could not allocate avframe buffer of size %dx%d: %s'\
                                % (w, h, emsg(res, msg, sizeof(msg))))

    def __init__(self, plane_buffers=[], plane_ptrs=[], frame=0, pix_fmt='',
                  size=(), linesize=[], **kargs):
        pass

    def __dealloc__(self):
        av_frame_free(&self.frame)

    def __copy__(self):
        cdef AVFrame *frame = av_frame_clone(self.frame)
        if frame == NULL:
            raise MemoryError()
        return Image(frame=<size_t>frame)

    def __deepcopy__(self, memo):
        cdef AVFrame *frame = av_frame_alloc()
        if frame == NULL:
            raise MemoryError()

        frame.format = self.frame.format
        frame.width = self.frame.width
        frame.height = self.frame.height
        if av_frame_copy_props(frame, self.frame) < 0:
            raise Exception('Cannot copy frame properties.')
        if av_frame_get_buffer(frame, 32) < 0:
            raise Exception('Cannot allocate frame buffers.')
        with nogil:
            av_image_copy(frame.data, frame.linesize, <const uint8_t **>self.frame.data,
                          self.frame.linesize, <AVPixelFormat>frame.format,
                          frame.width, frame.height)
        return Image(frame=<size_t>frame)

    def is_ref(self):
        '''
        Returns whether the image buffer is FFmpeg referenced. This can only be
        True when the buffers were allocated internally or by FFmpeg, see
        :class:`Image` for details. After a copy, it will always returns True.

        **Returns**:
            (bool): True if the buffer is FFmpeg referenced.

        For example::

            >>> w, h = 640, 480
            >>> img = Image(plane_buffers=[bytes(' ') * (w * h * 3)], pix_fmt='rgb24', size=(w, h))
            >>> img.is_ref()
            False
            >>> import copy
            >>> img2 = copy.copy(img)
            >>> img2.is_ref()
            True

        Or if directly allocated internally::

            >>> img = Image(pix_fmt='rgb24', size=(w, h))
            >>> img.is_ref()
            True
        '''
        return self.frame.buf[0] != NULL

    def get_linesizes(Image self, keep_align=False):
        '''
        Returns the linesize of each plane.

        The linesize is the actual number of bytes in each line for a given plane,
        which may be padded at the end to satisfy some alignment requirement.
        For example, a RGB24 frame of size (100, 10) will have 3 * 100 = 300
        bytes in each line and will be 3000 bytes large. But, when 32 bit
        alignment is required, the buffer will have to padded at the end so
        that each line is 320 bytes, and the total buffer length is 3200 bytes.

        **Args**:
            *keep_align* (bool): If True, the linesize alignments of the image
            will be returned for every plane. If False, linesize with an alignment
            of 1 (i.e. no alignment) will be used, returning the minimal
            linesize required to for the image. Defaults to False.

        **Returns**:
            (list): The linesizes of each plane.

        By defaults there's no alignment::

            >>> w, h = 100, 10
            >>> img = Image(plane_buffers=[bytes(' ') * (w * h * 3)],
            ... pix_fmt='rgb24', size=(w, h))
            >>> img.get_linesizes(keep_align=True)
            (300, 0, 0, 0)

        You can force alignment e.g. 32 bits alignment::

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

        The linesizes of an unaligned and 32 bit aligned yuv420p image::

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

    def get_size(Image self):
        '''
        Returns the size of the frame.

        **Returns**:
            (2-tuple): The size of the frame as (width, height).

        ::

            >>> img.get_size()
            (640, 480)
        '''
        return (self.frame.width, self.frame.height)

    def get_pixel_format(Image self):
        '''
        Returns the pixel format of the image. Can be one of
        :attr:`ffpyplayer.tools.pix_fmts`.

        **Returns**:
            (str): The pixel format of the image

        ::

            >>> img.get_pixel_format()
            'rgb24'
        '''
        return av_get_pix_fmt_name(self.pix_fmt)

    def get_buffer_size(Image self, keep_align=False):
        '''
        Returns the size of the buffers of each plane.

        **Args**:
            *keep_align* (bool): If True, the linesize alignments of the image
            will be used to calculate the buffer size for each plane. If False,
            an alignment of 1 (i.e. no alignment) will be used, returning the
            minimal buffer size required to store the image. Defaults to False.

        **Returns**:
            (4-tuple): A list of buffer sizes for each plane of this pixel format.

        A (unaligned) yuv420p image has 3 planes::

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
        cdef char msg[256]

        if keep_align:
            memcpy(ls, self.frame.linesize, sizeof(ls))
        else:
            res = av_image_fill_linesizes(ls, self.pix_fmt, self.frame.width)
            if res < 0:
                raise Exception('Failed to initialize linesizes: ' + emsg(res, msg, sizeof(msg)))

        res = get_plane_sizes(size, <AVPixelFormat>self.frame.format, self.frame.height, ls)
        if res < 0:
            raise Exception('Failed to get planesizes: ' + emsg(res, msg, sizeof(msg)))
        return (size[0], size[1], size[2], size[3])

    def to_bytearray(Image self, keep_align=False):
        '''
        Returns a copy of the plane buffers as bytearrays.

        **Args**:
            *keep_align* (bool): If True, the buffer will be padded after each
            horizontal line to match the linesize of this plane. If False, an
            alignment of 1 (i.e. no alignment) will be used, returning the
            maximially packed buffer of this plane. Defaults to False.

        **Returns**:
            (4-element list): A list of bytearray buffers for each plane of this
            pixel format.

        Get the buffer of an RGB image::

            >>> w, h = 100, 10
            >>> img = Image(pix_fmt='rgb24', size=(w, h))
            >>> img.get_linesizes(keep_align=True)
            (300, 0, 0, 0)
            >>> map(len, img.to_bytearray())
            [3000, 0, 0, 0]

        Get the buffers of a YUV420P image::

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
        cdef char msg[256]
        memset(data, 0, sizeof(data))

        if keep_align:
            memcpy(ls, self.frame.linesize, sizeof(ls))
        else:
            res = av_image_fill_linesizes(ls, self.pix_fmt, self.frame.width)
            if res < 0:
                raise Exception('Failed to initialize linesizes: ' + emsg(res, msg, sizeof(msg)))

        res = get_plane_sizes(size, <AVPixelFormat>self.frame.format, self.frame.height, ls)
        if res < 0:
            raise Exception('Failed to get plane sizes: ' + emsg(res, msg, sizeof(msg)))
        for i in range(4):
            planes[i] = bytearray('\0') * size[i]
            if size[i]:
                data[i] = planes[i]
        with nogil:
            av_image_copy(data, ls, <const uint8_t **>self.frame.data, self.frame.linesize,
                          <AVPixelFormat>self.frame.format, self.frame.width, self.frame.height)
        return planes
