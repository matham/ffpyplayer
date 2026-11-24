.. _tools-api:

*****
Tools
*****

:mod:`ffpyplayer.tools`
=============================

.. automodule:: ffpyplayer.tools
   :members:
   :undoc-members:
   :show-inheritance:

.. autoattribute:: ffpyplayer.tools.loglevels

    A dictionary with all the available ffmpeg log levels. The keys are the loglevels
    and the values are their ffmpeg values. The lower the value, the more important
    the log. Note, this is ooposite python where the higher the level the more important
    the log.

.. autoattribute:: ffpyplayer.tools.codecs_enc

    A list of all the codecs available for encoding video.

.. autoattribute:: ffpyplayer.tools.codecs_dec

    A list of all the codecs available for decoding video and audio.

.. autoattribute:: ffpyplayer.tools.pix_fmts

    A list of all the pixel formats available to ffmpeg.

.. autoattribute:: ffpyplayer.tools.formats_in

    A list of all the formats (e.g. file formats) available for reading.

.. autoattribute:: ffpyplayer.tools.formats_out

    A list of all the formats (e.g. file formats) available for writing.
