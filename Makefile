PYTHON = python

.PHONY: build force

build:
	$(PYTHON) setup.py build_ext --inplace

force:
	$(PYTHON) setup.py build_ext --inplace -f
