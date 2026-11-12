@echo off
setlocal EnableExtensions DisableDelayedExpansion

rem ----------------------------------------------------------------
rem init
rem ----------------------------------------------------------------
for %%I in ("%~dp0..") do set "ROOT=%%~fI"

set "OUTPUT_FRAC_BITS=10"
set "CONFIG_SIM=0"
set "SKIP_DELAY="
set "GUI_FLAG="
set "PYTHON_CMD="

:options
if "%~1"=="" goto environment
if /i "%~1"=="--output-frac-bits" goto option_output_frac_bits
if /i "%~1"=="--skip-delay" goto option_skip_delay
if /i "%~1"=="--sim" goto option_sim
if /i "%~1"=="--gui" goto option_gui
if /i not "%~1"=="tb_core" goto error_args
shift /1
goto options

:option_sim
set "CONFIG_SIM=1"
shift /1
goto options

:option_gui
set "GUI_FLAG=--gui"
shift /1
goto options

:option_skip_delay
shift /1
if "%~1"=="" goto error_args
set "SKIP_DELAY=%~1"
set SKIP_DELAY | findstr /r /x /c:"SKIP_DELAY=[1-9][0-9]*" >nul
if errorlevel 1 goto error_args
shift /1
goto options

:option_output_frac_bits
shift /1
if "%~1"=="" goto error_args
set "OUTPUT_FRAC_BITS=%~1"
set OUTPUT_FRAC_BITS | findstr /r /x /c:"OUTPUT_FRAC_BITS=[0-9]" /c:"OUTPUT_FRAC_BITS=1[0-5]" >nul
if errorlevel 1 goto error_args
shift /1
goto options

rem ----------------------------------------------------------------
rem check environment
rem ----------------------------------------------------------------
:environment
if "%CONFIG_SIM%"=="1" goto simulate
if defined SKIP_DELAY goto error_args
if defined GUI_FLAG goto error_args

if defined PYTHON set "PYTHON_CMD=%PYTHON%"
for %%P in (python3 python python3.14) do (
    if not defined PYTHON_CMD (
        "%%P" -c "import sys; sys.exit(sys.version_info < (3, 10))" >nul 2>&1
        if not errorlevel 1 set "PYTHON_CMD=%%P"
    )
)
if not defined PYTHON_CMD goto error_python

rem ----------------------------------------------------------------
rem synthesize
rem ----------------------------------------------------------------
"%PYTHON_CMD%" "%ROOT%\scripts\synthesis.py"
exit /b %ERRORLEVEL%

rem ----------------------------------------------------------------
rem simulate the existing netlist
rem ----------------------------------------------------------------
:simulate
set "TB_CORE_POST_SYNTHESIS=1"
if not defined SKIP_DELAY set "SKIP_DELAY=1"
call "%~dp0behav_sim.bat" tb_core --output-frac-bits %OUTPUT_FRAC_BITS% --skip-delay %SKIP_DELAY% %GUI_FLAG%
exit /b %ERRORLEVEL%

rem ----------------------------------------------------------------
rem error
rem ----------------------------------------------------------------
:error_args
echo Usage: %~nx0 [tb_core] [--output-frac-bits N] [--sim [--skip-delay N] [--gui]] 1>&2
exit /b 2

:error_python
echo [ ERROR ] Set PYTHON to a Python 3.10+ executable. 1>&2
exit /b 1
