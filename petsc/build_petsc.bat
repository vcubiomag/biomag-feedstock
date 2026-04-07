setlocal enabledelayedexpansion

:: Locate Cygwin installation
:: Detection order:
::   1. CYGWIN_ROOT environment variable (set by CI or user)
::   2. C:\cygwin64 (default 64-bit install)
::   3. C:\cygwin (default 32-bit install)
set "CYGWIN_DIR=%CYGWIN_ROOT%"
if "%CYGWIN_DIR%"=="" if exist "C:\cygwin64\bin\bash.exe" set "CYGWIN_DIR=C:\cygwin64"
if "%CYGWIN_DIR%"=="" if exist "C:\cygwin\bin\bash.exe" set "CYGWIN_DIR=C:\cygwin"
if "%CYGWIN_DIR%"=="" (
    echo ERROR: Cygwin not found. Set CYGWIN_ROOT or install to C:\cygwin64
    exit /b 1
)
if not exist "%CYGWIN_DIR%\bin\bash.exe" (
    echo ERROR: bash.exe not found at %CYGWIN_DIR%\bin\bash.exe
    exit /b 1
)

:: Verify compilers are available
where cl >nul 2>&1 || (echo ERROR: cl.exe not found. MSVC activation may have failed. & exit /b 1)
where ifort >nul 2>&1 || (echo ERROR: ifort not found. Intel Fortran setup may have failed. & exit /b 1)

:: Expand any literal %%PREFIX%% references that conda activation scripts
:: may have left unexpanded in LIB/INCLUDE. In cmd.exe these would expand
:: automatically, but Cygwin bash sees them as literal strings.
set "LIB=!LIB:%%PREFIX%%=%PREFIX%!"
set "LIB=!LIB:%%LIBRARY_PREFIX%%=%LIBRARY_PREFIX%!"
set "LIB=!LIB:%%BUILD_PREFIX%%=%BUILD_PREFIX%!"
set "INCLUDE=!INCLUDE:%%PREFIX%%=%PREFIX%!"
set "INCLUDE=!INCLUDE:%%LIBRARY_PREFIX%%=%LIBRARY_PREFIX%!"
set "INCLUDE=!INCLUDE:%%BUILD_PREFIX%%=%BUILD_PREFIX%!"

:: Strip CRLF from the shell script. Git on Windows may check out .sh files
:: with \r\n line endings which Cygwin bash cannot parse.
"!CYGWIN_DIR!\bin\sed.exe" -i "s/\r$//" "!RECIPE_DIR!\build_petsc_win.sh"

:: Launch the build under Cygwin bash.
:: --norc --noprofile: avoid Cygwin shell profiles that could modify PATH
:: and hide the conda build environment's tools and compilers.
"!CYGWIN_DIR!\bin\bash.exe" --norc --noprofile "!RECIPE_DIR!\build_petsc_win.sh"
if errorlevel 1 exit /b 1
