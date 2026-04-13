setlocal enabledelayedexpansion

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

"!CYGWIN_DIR!\bin\bash.exe" --norc --noprofile "%RECIPE_DIR%\build_petsc_win.sh"
if errorlevel 1 exit /b 1
