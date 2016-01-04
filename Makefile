PYTHON = python

.PHONY: build force test

build:
	$(PYTHON) setup.py build_ext --inplace

force:
	$(PYTHON) setup.py build_ext --inplace -f

test:
	$(PYTHON) -m nose.core ffpyplayer/tests