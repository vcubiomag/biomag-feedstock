@echo off
setlocal enabledelayedexpansion

set PETSC_DIR=%SRC_DIR%
set PETSC_ARCH=arch-conda-c-opt

:: Hypre is only available for real scalar type
set with_hypre=1
if "%scalar%"=="complex" set with_hypre=0

python configure ^
  --with-cc="win32fe cl" ^
  --with-cxx="win32fe cl" ^
  --with-fc="win32fe ifx" ^
  --with-fortran-bindings=0 ^
  --COPTFLAGS="-O2" ^
  --CXXOPTFLAGS="-O2" ^
  --FOPTFLAGS="-O2" ^
  --with-clib-autodetect=0 ^
  --with-cxxlib-autodetect=0 ^
  --with-fortranlib-autodetect=0 ^
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
  --with-hwloc=1 ^
  --with-hypre=%with_hypre% ^
  --with-metis=1 ^
  --with-ptscotch=1 ^
  --with-suitesparse=1 ^
  --with-suitesparse-dir=%LIBRARY_PREFIX% ^
  --with-hdf5=0 ^
  --with-fftw=0 ^
  --with-parmetis=0 ^
  --with-scalapack=0 ^
  --with-mumps=0 ^
  --with-superlu=0 ^
  --with-superlu_dist=0 ^
  --with-cuda=0 ^
  --with-make-exec=make ^
  --prefix=%LIBRARY_PREFIX% || (type configure.log && exit /b 1)

make MAKE_NP=%CPU_COUNT%
if errorlevel 1 exit /b 1

make install
if errorlevel 1 exit /b 1

:: Cleanup
del /q %LIBRARY_PREFIX%\lib\petsc\conf\configure-hash 2>nul

:: Remove .pyc files
for /r "%LIBRARY_PREFIX%\lib\petsc" %%f in (*.pyc) do del /q "%%f"

:: Strip non-deterministic content (timestamps, machine info) from installed files
:: to ensure reproducible package hashes across builds.
if exist "%LIBRARY_PREFIX%\include\petscmachineinfo.h" (
  echo Stripping petscmachineinfo.h
  echo static const char *petscmachineinfo = "";> "%LIBRARY_PREFIX%\include\petscmachineinfo.h"
)
if exist "%LIBRARY_PREFIX%\include\petscconfiginfo.h" (
  echo Stripping petscconfiginfo.h
  echo static const char *petscconfigureruntime = "";> "%LIBRARY_PREFIX%\include\petscconfiginfo.h"
)

:: Remove reconfigure scripts (contain build-specific paths and timestamps)
del /q %LIBRARY_PREFIX%\lib\petsc\conf\reconfigure-*.py 2>nul

:: Remove build prefix references from installed files
powershell -Command "Get-ChildItem -Path '%LIBRARY_PREFIX%\lib\petsc' -Recurse -File | ForEach-Object { $c = Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue; if ($c -and $c.Contains('%BUILD_PREFIX%')) { $c.Replace('%BUILD_PREFIX%\Library\bin\', '').Replace('%BUILD_PREFIX%', '%LIBRARY_PREFIX%') | Set-Content $_.FullName -NoNewline } }"
powershell -Command "if (Test-Path '%LIBRARY_PREFIX%\lib\pkgconfig\PETSc.pc') { (Get-Content '%LIBRARY_PREFIX%\lib\pkgconfig\PETSc.pc' -Raw).Replace('%BUILD_PREFIX%', '%LIBRARY_PREFIX%') | Set-Content '%LIBRARY_PREFIX%\lib\pkgconfig\PETSc.pc' -NoNewline }"

:: Replace absolute path to build python in headers
powershell -Command "Get-ChildItem -Path '%LIBRARY_PREFIX%\include' -Filter 'petsc*.h' -File | ForEach-Object { $c = Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue; if ($c -and $c.Contains('%BUILD_PREFIX%')) { $c.Replace('%BUILD_PREFIX%', '%LIBRARY_PREFIX%') | Set-Content $_.FullName -NoNewline } }"

:: Remove example and data files
if exist %LIBRARY_PREFIX%\share\petsc\examples\src rmdir /s /q %LIBRARY_PREFIX%\share\petsc\examples\src
if exist %LIBRARY_PREFIX%\share\petsc\datafiles rmdir /s /q %LIBRARY_PREFIX%\share\petsc\datafiles
