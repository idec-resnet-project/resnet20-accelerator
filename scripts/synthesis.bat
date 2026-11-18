@echo off
setlocal EnableExtensions DisableDelayedExpansion

rem ----------------------------------------------------------------
rem init
rem ----------------------------------------------------------------
for %%I in ("%~dp0..") do set "ROOT=%%~fI"

set "CONFIG_SIM=0"
set "TB_NAME="
set "GUI_LIVE_FLAG="
set "GUI_STATIC_FLAG="
set "NO_WDB_FLAG="
set "SKIP_COMPILE_FLAG="
set "PYTHON_CMD="

:options
if "%~1"=="" goto environment
if /i "%~1"=="--sim" goto option_sim
if /i "%~1"=="--gui-live" goto option_gui_live
if /i "%~1"=="--gui" goto option_gui
if /i "%~1"=="--no-wdb" goto option_no_wdb
if /i "%~1"=="--skip-compile" goto option_skip_compile
if defined TB_NAME goto error_args
set "TB_NAME=%~1"
set TB_NAME | findstr /r /x /c:"TB_NAME=[A-Za-z_][A-Za-z_0-9]*" >nul
if errorlevel 1 goto error_args
shift /1
goto options

:option_sim
set "CONFIG_SIM=1"
shift /1
goto options

:option_gui_live
set "GUI_LIVE_FLAG=--gui-live"
shift /1
goto options

:option_gui
set "GUI_STATIC_FLAG=--gui"
shift /1
goto options

:option_no_wdb
set "NO_WDB_FLAG=--no-wdb"
shift /1
goto options

:option_skip_compile
set "SKIP_COMPILE_FLAG=--skip-compile"
shift /1
goto options

rem ----------------------------------------------------------------
rem check environment
rem ----------------------------------------------------------------
:environment
if not defined TB_NAME set "TB_NAME=tb_core"
if "%CONFIG_SIM%"=="1" goto simulate
if defined NO_WDB_FLAG goto error_args
if defined SKIP_COMPILE_FLAG goto error_args
if defined GUI_STATIC_FLAG goto error_args
if defined GUI_LIVE_FLAG goto error_args

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
"%PYTHON_CMD%" "%ROOT%\scripts\synthesis.py" %TB_NAME%
exit /b %ERRORLEVEL%

rem ----------------------------------------------------------------
rem simulate the existing netlist
rem ----------------------------------------------------------------
:simulate
call "%~dp0synthesis_sim.bat" %TB_NAME% %SKIP_COMPILE_FLAG% %NO_WDB_FLAG% %GUI_LIVE_FLAG% %GUI_STATIC_FLAG%
exit /b %ERRORLEVEL%

rem ----------------------------------------------------------------
rem error
rem ----------------------------------------------------------------
:error_args
echo Usage: %~nx0 [testbench] [--sim [--skip-compile] [--no-wdb] [--gui-live ^| --gui]] 1>&2
exit /b 2

:error_python
echo [ ERROR ] Set PYTHON to a Python 3.10+ executable. 1>&2
exit /b 1
