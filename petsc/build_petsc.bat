setlocal enabledelayedexpansion

:: =============================================================================
:: PETSc Windows Build Launcher
::
:: This script locates a Cygwin installation and delegates the actual build to
:: build_petsc_win.sh running under Cygwin bash. PETSc's configure script
:: requires a Unix environment which Cygwin provides. The compiled output is
:: native Windows (.lib/.dll) with no Cygwin dependency.
::
:: Cygwin detection order:
::   1. CYGWIN_ROOT environment variable (set by CI or user)
::   2. C:\cygwin64 (default 64-bit install)
::   3. C:\cygwin (default 32-bit install)
:: =============================================================================

:: Locate Cygwin installation
:: Use separate if statements to avoid cmd.exe issues with chained else-if blocks
set "CYGWIN_DIR=%CYGWIN_ROOT%"
if "%CYGWIN_DIR%"=="" if exist "C:\cygwin64\bin\bash.exe" set "CYGWIN_DIR=C:\cygwin64"
if "%CYGWIN_DIR%"=="" if exist "C:\cygwin\bin\bash.exe" set "CYGWIN_DIR=C:\cygwin"
if "%CYGWIN_DIR%"=="" (
    echo ERROR: Cygwin not found. Set CYGWIN_ROOT or install to C:\cygwin64
    echo Get it at https://www.cygwin.com/ ^(include the python3 package^)
    exit /b 1
)
if not exist "%CYGWIN_DIR%\bin\bash.exe" (
    echo ERROR: bash.exe not found at %CYGWIN_DIR%\bin\bash.exe
    echo CYGWIN_ROOT may be set incorrectly: %CYGWIN_DIR%
    exit /b 1
)

echo !pre!

@REM set "_ENV_FILE=!SRC_DIR!\_build_env.sh"
@REM echo export SRC_DIR='!SRC_DIR!'> "!_ENV_FILE!"
@REM echo export PREFIX='!PREFIX!'>> "!_ENV_FILE!"
@REM echo export LIBRARY_PREFIX='!LIBRARY_PREFIX!'>> "!_ENV_FILE!"
@REM echo export BUILD_PREFIX='!BUILD_PREFIX!'>> "!_ENV_FILE!"
@REM echo export RECIPE_DIR='!RECIPE_DIR!'>> "!_ENV_FILE!"
@REM echo export CPU_COUNT='!CPU_COUNT!'>> "!_ENV_FILE!"
@REM echo export scalar='!scalar!'>> "!_ENV_FILE!"
@REM echo export WIN_LIB='!LIB!'>> "!_ENV_FILE!"
@REM echo export WIN_INCLUDE='!INCLUDE!'>> "!_ENV_FILE!"
@REM echo export WIN_PATH='!PATH!'>> "!_ENV_FILE!"

:: Launch the build script under Cygwin bash.
:: --norc --noprofile: avoid loading Cygwin shell profiles that could modify PATH
:: and hide the conda build environment's tools and compilers.
"!CYGWIN_DIR!\bin\bash.exe" --norc --noprofile "!RECIPE_DIR!\build_petsc_win.sh"
if errorlevel 1 exit /b 1
