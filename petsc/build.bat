@echo off
setlocal enabledelayedexpansion

set PETSC_DIR=%SRC_DIR%
set PETSC_ARCH=arch-conda-c-opt

:: Hypre is only available for real scalar type
set with_hypre=1
if "%scalar%"=="complex" set with_hypre=0

python configure ^
  CC="cl" ^
  CXX="cl" ^
  --COPTFLAGS="-O2" ^
  --CXXOPTFLAGS="-O2" ^
  --with-clib-autodetect=0 ^
  --with-cxxlib-autodetect=0 ^
  --with-fortranlib-autodetect=0 ^
  --with-fortran-bindings=0 ^
  --with-64-bit-indices=0 ^
  --with-debugging=0 ^
  --with-shared-libraries=1 ^
  --with-ssl=0 ^
  --with-x=0 ^
  --with-scalar-type=%scalar% ^
  --with-mpi=1 ^
  --with-openmp=1 ^
  --with-blaslapack-dir=%LIBRARY_PREFIX% ^
  --with-mkl_pardiso=1 ^
  --with-yaml=1 ^
  --with-hdf5=1 ^
  --with-fftw=1 ^
  --with-hwloc=1 ^
  --with-hypre=%with_hypre% ^
  --with-metis=1 ^
  --with-parmetis=1 ^
  --with-ptscotch=1 ^
  --with-scalapack=1 ^
  --with-mumps=1 ^
  --with-superlu=1 ^
  --with-superlu_dist=1 ^
  --with-superlu_dist-include=%LIBRARY_PREFIX%\include\superlu-dist ^
  --with-superlu_dist-lib=-lsuperlu_dist ^
  --with-suitesparse=1 ^
  --with-suitesparse-dir=%LIBRARY_PREFIX% ^
  --with-cuda=0 ^
  --prefix=%LIBRARY_PREFIX% || (type configure.log && exit /b 1)

nmake MAKE_NP=%CPU_COUNT%
if errorlevel 1 exit /b 1

nmake install
if errorlevel 1 exit /b 1

:: Cleanup
del /q %LIBRARY_PREFIX%\lib\petsc\conf\configure-hash 2>nul

:: Remove example and data files
if exist %LIBRARY_PREFIX%\share\petsc\examples\src rmdir /s /q %LIBRARY_PREFIX%\share\petsc\examples\src
if exist %LIBRARY_PREFIX%\share\petsc\datafiles rmdir /s /q %LIBRARY_PREFIX%\share\petsc\datafiles
