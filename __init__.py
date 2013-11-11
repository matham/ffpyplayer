
__all__ = ('FFPyPlayer', )


import os
import sys
# this seems to be needed for python to be able to import
pathname = os.path.dirname(__file__)
sys.path.append(pathname)
# needed for windows so dlls are found
bin_path = os.path.join(pathname, 'bins')
if bin_path not in os.pathsep.split(os.environ['PATH']):
    os.environ['PATH'] = bin_path + os.pathsep + os.environ['PATH']
import ffpyplayer
from ffpyplayer import FFPyPlayer