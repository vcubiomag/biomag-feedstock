@echo off

set PETSC_DIR=%LIBRARY_PREFIX%

cd src\binding\petsc4py
%PYTHON% conf\cythonize.py
if errorlevel 1 exit /b 1

%PYTHON% -m pip install . --no-deps -vv
if errorlevel 1 exit /b 1
