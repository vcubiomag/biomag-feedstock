#!/bin/bash
set -ex

export PETSC_DIR=$PREFIX

cd src/binding/petsc4py
$PYTHON conf/cythonize.py
$PYTHON -m pip install . -vv --no-deps --no-build-isolation
