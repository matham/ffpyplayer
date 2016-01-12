
__all__ = ('get_media', )

from os import environ
from os.path import join, abspath, dirname, exists

from ffpyplayer.tools import set_loglevel, set_log_callback
import logging

set_log_callback(logger=logging, default_only=True)
set_loglevel('trace')

def get_media(fname):
    if exists(fname):
        return abspath(fname)

    root = dirname(__file__)
    if exists(join(root, fname)):
        return join(root, fname)

    ex = abspath(join(root, '../../examples', fname))
    if exists(ex):
        return ex

    if 'FFPYPLAYER_TEST_DIRS' in environ:
        for d in environ['FFPYPLAYER_TEST_DIRS'].split(';'):
            d = d.strip()
            if not d:
                continue

            if exists(join(d, fname)):
                return join(d, fname)

    raise IOError("{} doesn't exist".format(fname))
