@echo off
setlocal EnableExtensions DisableDelayedExpansion

rem ----------------------------------------------------------------
rem init
rem ----------------------------------------------------------------
for %%I in ("%~dp0..") do set "ROOT=%%~fI"

set "TB_NAME=tb_core"
set "TB_PATH=%ROOT%\tb\%TB_NAME%"
set "TB_FILES=%TB_PATH%\%TB_NAME%.f"
set "PATH_LOG=%ROOT%\build\sim\%TB_NAME%"
set "SCRIPT_NAME=%~nx0"
set "CONFIG_GUI=0"
set "SKIP_DELAY=1"
set "OUTPUT_FRAC_BITS=10"
set "EXIT_CODE=0"
set "PATH_PUSHED=0"
set "COMPILE_FLAGS="
set "ELAB_TARGETS=%TB_NAME%"
set "DEBUG_FLAGS="
set "NETLIST="
set "PYTHON_CMD="

if "%TB_CORE_POST_SYNTHESIS%"=="1" (
    set "PATH_LOG=%ROOT%\build\sim\tb_core_synthesis"
    set "SCRIPT_NAME=synthesis.bat --sim"
    set "COMPILE_FLAGS=-d TB_CORE_POST_SYNTHESIS"
    set "ELAB_TARGETS=tb_core glbl -L unisims_ver"
)

:options
if "%~1"=="" goto environment
if /i "%~1"=="--skip-delay" goto option_skip_delay
if /i "%~1"=="--output-frac-bits" goto option_output_frac_bits
if /i "%~1"=="--gui" (
    set "CONFIG_GUI=1"
) else if /i not "%~1"=="%TB_NAME%" (
    goto error_args
)
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
if "%TB_CORE_POST_SYNTHESIS%"=="1" (
    set "NETLIST=%ROOT%\build\synth\tb_core\frac_%OUTPUT_FRAC_BITS%\core_funcsim.v"
)
if defined NETLIST (
    if not exist "%NETLIST%" goto error_netlist
    for %%F in ("%NETLIST%") do if %%~zF equ 0 goto error_netlist
)
if defined INPUT_GAP (
    set INPUT_GAP | findstr /r /x /c:"INPUT_GAP=[0-9][0-9]*" >nul
    if errorlevel 1 goto error_input_gap
)
for %%T in (xvlog.bat xelab.bat xsim.bat) do (
    where /q %%T
    if errorlevel 1 (
        echo [ ERROR ] %%T not found. Add Vivado bin to PATH. 1>&2
        exit /b 1
    )
)
if not exist "%TB_FILES%" goto error_sources

if defined PYTHON set "PYTHON_CMD=%PYTHON%"
for %%P in (python3 python python3.14) do (
    if not defined PYTHON_CMD (
        "%%P" -c "import sys; sys.exit(sys.version_info < (3, 10))" >nul 2>&1
        if not errorlevel 1 set "PYTHON_CMD=%%P"
    )
)
if not defined PYTHON_CMD goto error_python

if not exist "%PATH_LOG%" mkdir "%PATH_LOG%"
pushd "%TB_PATH%"
if errorlevel 1 goto error_sources
set "PATH_PUSHED=1"

type nul > "%PATH_LOG%\sources.prj"
if errorlevel 1 goto error_sources
rem The functional netlist already includes glbl.
if defined NETLIST >> "%PATH_LOG%\sources.prj" echo verilog work "%NETLIST:\=/%"
for /f "usebackq eol=# tokens=*" %%F in ("%TB_FILES%") do (
    call :add_source "%%F"
    if errorlevel 1 goto error_sources
)

popd
set "PATH_PUSHED=0"
pushd "%PATH_LOG%"
if errorlevel 1 goto error_sources
set "PATH_PUSHED=1"
type nul > simulate.log

"%PYTHON_CMD%" "%ROOT%\verification\core\golden_ref\generate_resnet20_core.py" --out vectors
if errorlevel 1 goto error_vectors

rem ----------------------------------------------------------------
rem compile and elaborate
rem ----------------------------------------------------------------
echo ----------------------------------------------------------------
echo [1/3] Compiling HDL...
echo ----------------------------------------------------------------

call xvlog.bat -prj sources.prj -i "%TB_PATH:\=/%/include" %COMPILE_FLAGS% -log compile.log
if errorlevel 1 goto error_compile

echo ----------------------------------------------------------------
echo [2/3] Elaborating %TB_NAME%...
echo ----------------------------------------------------------------

> elaborate_args.f echo -generic_top "SKIP_DELAY_CYCLES=%SKIP_DELAY%"
>> elaborate_args.f echo -generic_top "OUTPUT_FRAC_BITS=%OUTPUT_FRAC_BITS%"
if "%CONFIG_GUI%"=="1" set "DEBUG_FLAGS=-debug typical"
call xelab.bat %ELAB_TARGETS% -s behav_tb -f elaborate_args.f %DEBUG_FLAGS% -log elaborate.log
if errorlevel 1 goto error_elaborate

rem ----------------------------------------------------------------
rem simulate
rem ----------------------------------------------------------------
echo ----------------------------------------------------------------
echo [3/3] Running ResNet-20 core verification...
echo ----------------------------------------------------------------

set "STREAM_FLAGS="
type nul > stream_args.f
if defined INPUT_GAP (
    > stream_args.f echo -testplusarg "input_gap=%INPUT_GAP%"
    set "STREAM_FLAGS=-f stream_args.f"
)
if "%CONFIG_GUI%"=="1" (
    > gui_run.tcl echo add_wave /tb_core/clk /tb_core/nrst
    >> gui_run.tcl echo add_wave /tb_core/in_enable /tb_core/in_data /tb_core/kernel_data /tb_core/bias_data
    >> gui_run.tcl echo add_wave /tb_core/out_enable /tb_core/out_data
    >> gui_run.tcl echo run all
    call xsim.bat behav_tb -log simulate.log %STREAM_FLAGS% -gui -onfinish stop -tclbatch gui_run.tcl
) else (
    call xsim.bat behav_tb -log simulate.log %STREAM_FLAGS% -runall
)
if errorlevel 1 goto error_simulate

findstr /l /c:"Fatal:" simulate.log >nul
if not errorlevel 1 goto error_simulate
findstr /l /c:"[ PASS ] ALL TESTS PASSED" simulate.log >nul
if errorlevel 1 goto error_simulate
goto finish

rem ----------------------------------------------------------------
rem source manifest
rem ----------------------------------------------------------------
:add_source
set "SOURCE=%~1"
if "%SOURCE:~0,1%"=="#" exit /b 0
if defined NETLIST if /i "%SOURCE%"=="dummy/core.v" exit /b 0
if not exist "%SOURCE%" (
    echo [ ERROR ] Source not found: "%SOURCE%". 1>&2
    exit /b 1
)
set "SOURCE_PATH=%~f1"
>> "%PATH_LOG%\sources.prj" echo sv work "%SOURCE_PATH:\=/%"
exit /b %ERRORLEVEL%

rem ----------------------------------------------------------------
rem error
rem ----------------------------------------------------------------
:error_args
echo Usage: %SCRIPT_NAME% [tb_core] [--skip-delay N] [--output-frac-bits N] [--gui] 1>&2
exit /b 2

:error_input_gap
echo [ ERROR ] INPUT_GAP must be nonnegative. 1>&2
exit /b 2

:error_python
echo [ ERROR ] Set PYTHON to a Python 3.10+ executable. 1>&2
exit /b 1

:error_netlist
echo [ ERROR ] Functional netlist missing or empty: "%NETLIST%". 1>&2
echo [ INFO ] Generate it with: "%~dp0synthesis.bat" %TB_NAME% --output-frac-bits %OUTPUT_FRAC_BITS% 1>&2
set "EXIT_CODE=1"
goto finish

:error_sources
echo [ ERROR ] Could not prepare sources from "%TB_FILES%" in "%PATH_LOG%". 1>&2
set "EXIT_CODE=1"
goto finish

:error_vectors
echo [ ERROR ] Failed to generate ResNet-20 reference vectors. 1>&2
set "EXIT_CODE=1"
goto finish

:error_compile
echo [ ERROR ] Compilation failed. See "%PATH_LOG%\compile.log". 1>&2
set "EXIT_CODE=1"
goto finish

:error_elaborate
echo [ ERROR ] Elaboration failed. See "%PATH_LOG%\elaborate.log". 1>&2
set "EXIT_CODE=1"
goto finish

:error_simulate
echo [ ERROR ] Simulation failed. See "%PATH_LOG%\simulate.log". 1>&2
set "EXIT_CODE=1"

:finish
if "%PATH_PUSHED%"=="1" popd
exit /b %EXIT_CODE%
