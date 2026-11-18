@echo off
setlocal EnableExtensions DisableDelayedExpansion

rem ----------------------------------------------------------------
rem init
rem ----------------------------------------------------------------
for %%I in ("%~dp0..") do set "ROOT=%%~fI"

set "TB_NAME="
set "SCRIPT_NAME=%~nx0"
set "GUI_STATIC="
set "GUI_LIVE="
set "NO_WDB="
set "SKIP_COMPILE="
set "EXIT_CODE=0"
set "PATH_PUSHED=0"
set "COMPILE_FLAGS=%TB_SIM_COMPILE_FLAGS%"
set "NETLIST=%TB_SIM_NETLIST%"
set "C_SOURCES="
set "UVM_FLAGS=-L uvm"
set "DPI_FLAGS="


:options
if "%~1"=="" goto configure
if /i "%~1"=="--gui" goto option_gui
if /i "%~1"=="--gui-live" goto option_gui_live
if /i "%~1"=="--no-wdb" goto option_no_wdb
if /i "%~1"=="--skip-compile" goto option_skip_compile
if defined TB_NAME goto error_args
set "TB_NAME=%~1"
set TB_NAME | findstr /r /x /c:"TB_NAME=[A-Za-z_][A-Za-z_0-9]*" >nul
if errorlevel 1 goto error_args
shift /1
goto options

:option_gui
set "GUI_STATIC=1"
shift /1
goto options

:option_gui_live
set "GUI_LIVE=1"
shift /1
goto options

:option_no_wdb
set "NO_WDB=1"
shift /1
goto options

:option_skip_compile
set "SKIP_COMPILE=1"
shift /1
goto options

rem ----------------------------------------------------------------
rem check environment
rem ----------------------------------------------------------------
:configure
if defined NO_WDB set "GUI_STATIC="
if defined GUI_STATIC if defined GUI_LIVE goto error_args
if not defined TB_NAME set "TB_NAME=tb_core"
set "TB_PATH=%ROOT%\tb\%TB_NAME%"
set "TB_FILES=%TB_PATH%\%TB_NAME%.f"
set "WAVE_CONFIG="
if exist "%TB_PATH%\%TB_NAME%.wcfg" set "WAVE_CONFIG=%TB_PATH%\%TB_NAME%.wcfg"
set "PATH_LOG=%ROOT%\.log\sim\%TB_NAME%"
if defined NETLIST set "PATH_LOG=%PATH_LOG%_synthesis"
set "WAVE_DIR=%PATH_LOG%"
set "WDB_PATH=%WAVE_DIR%\behav_tb.wdb"
set "ELAB_TARGETS=%TB_NAME% %TB_SIM_ELAB_TARGETS%"
set "WAVE_SETUP=%ROOT%\scripts\wave_setup.tcl"
if defined INPUT_GAP (
    set INPUT_GAP | findstr /r /x /c:"INPUT_GAP=[0-9][0-9]*" >nul
    if errorlevel 1 goto error_input_gap
)
if defined SKIP_COMPILE goto reuse_snapshot

if defined NETLIST (
    if not exist "%NETLIST%" goto error_netlist
    for %%F in ("%NETLIST%") do if %%~zF equ 0 goto error_netlist
)
for %%T in (xvlog.bat xelab.bat xsim.bat) do (
    where /q %%T
    if errorlevel 1 (
        echo [ ERROR ] %%T not found. Add Vivado bin to PATH. 1>&2
        exit /b 1
    )
)
if not exist "%TB_FILES%" goto error_sources

if not exist "%PATH_LOG%" mkdir "%PATH_LOG%"
pushd "%TB_PATH%"
if errorlevel 1 goto error_sources
set "PATH_PUSHED=1"

type nul > "%PATH_LOG%\compile_args.f"
>> "%PATH_LOG%\compile_args.f" echo -i "%TB_PATH:\=/%"
if exist "%TB_PATH%\include\" >> "%PATH_LOG%\compile_args.f" echo -i "%TB_PATH:\=/%/include"
if exist "%ROOT%\tb\libs\" >> "%PATH_LOG%\compile_args.f" echo -i "%ROOT:\=/%/tb/libs"
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

rem ----------------------------------------------------------------
rem compile and elaborate
rem ----------------------------------------------------------------
echo ----------------------------------------------------------------
echo [1/3] Compiling HDL...
echo ----------------------------------------------------------------

call xvlog.bat -prj sources.prj -f compile_args.f %UVM_FLAGS% %COMPILE_FLAGS% -log compile.log
if errorlevel 1 goto error_compile

echo ----------------------------------------------------------------
echo [2/3] Elaborating %TB_NAME%...
echo ----------------------------------------------------------------

set "DEBUG_FLAGS=-debug all"
if defined NO_WDB (
    set "DEBUG_FLAGS="
    if defined GUI_LIVE set "DEBUG_FLAGS=-debug typical"
)
if defined C_SOURCES (
    where /q xsc.bat
    if errorlevel 1 goto error_elaborate
    call xsc.bat %C_SOURCES%
    if errorlevel 1 goto error_elaborate
    set "DPI_FLAGS=-sv_lib dpi"
)
call xelab.bat %ELAB_TARGETS% %UVM_FLAGS% %DPI_FLAGS% -s behav_tb %DEBUG_FLAGS% -timescale 1ns/1ps -log elaborate.log
if errorlevel 1 goto error_elaborate
goto simulate

rem ----------------------------------------------------------------
rem reuse the existing snapshot
rem ----------------------------------------------------------------
:reuse_snapshot
where /q xsim.bat
if errorlevel 1 (
    echo [ ERROR ] xsim.bat not found. Add Vivado bin to PATH. 1>&2
    exit /b 1
)
pushd "%PATH_LOG%"
if errorlevel 1 goto error_snapshot
set "PATH_PUSHED=1"
for %%F in (xsimk.exe xsim.mem) do (
    if not exist "xsim.dir\behav_tb\%%F" goto error_snapshot
    for %%I in ("xsim.dir\behav_tb\%%F") do if %%~zI equ 0 goto error_snapshot
)
if not defined NO_WDB (
    findstr /i /l /c:"-debug \"all\"" /c:"-debug all" "xsim.dir\behav_tb\Compile_Options.txt" >nul 2>&1
    if errorlevel 1 goto error_snapshot_debug
) else if defined GUI_LIVE (
    findstr /i /r /c:"-debug .*typical" /c:"-debug .*wave" /c:"-debug .*all" "xsim.dir\behav_tb\Compile_Options.txt" >nul 2>&1
    if errorlevel 1 goto error_snapshot_gui_debug
)

echo [ INFO ] Reusing the %TB_NAME% simulation snapshot.

rem ----------------------------------------------------------------
rem simulate
rem ----------------------------------------------------------------
:simulate
type nul > simulate.log
if exist "uvm_test_passed" del /q "uvm_test_passed"
if not defined NO_WDB (
    if not exist "%WAVE_DIR%\" mkdir "%WAVE_DIR%"
    if not exist "%WAVE_DIR%\" goto error_wave_config
    if exist "%WDB_PATH%" del /q "%WDB_PATH%"
    if exist "%WDB_PATH%" goto error_wave_config
)

echo ----------------------------------------------------------------
echo [3/3] Running %TB_NAME%...
echo ----------------------------------------------------------------

> simulate_args.f echo -testplusarg "TB_DIR=%TB_PATH:\=/%"
if defined INPUT_GAP >> simulate_args.f echo -testplusarg "input_gap=%INPUT_GAP%"
set "SIM_FLAGS=-f simulate_args.f"
if defined GUI_LIVE (
    call :run_live_wave_view
    if errorlevel 1 goto error_simulate
) else if defined NO_WDB (
    call xsim.bat behav_tb -log simulate.log %SIM_FLAGS% -runall
    if errorlevel 1 goto error_simulate
    if exist "behav_tb.wdb" del /q "behav_tb.wdb"
) else (
    call xsim.bat behav_tb -log simulate.log %SIM_FLAGS% -wdb "%WDB_PATH:\=/%" -onfinish stop -tclbatch "%WAVE_SETUP:\=/%"
    if errorlevel 1 goto error_simulate
)
if not defined NO_WDB (
    findstr /b /l /c:"ERROR: Wave capture setup failed:" simulate.log >nul
    if not errorlevel 1 goto error_simulate
    if not exist "%WDB_PATH%" goto error_simulate
)

if defined GUI_STATIC (
    call :open_wave_view
    if errorlevel 1 goto error_wave_view
)

powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -Command "if (Get-Module -ListAvailable -Name BurntToast) { try { Import-Module BurntToast -ErrorAction Stop; New-BurntToastNotification -Text 'Behavior Simulation complete.', 'Check your log.' -ErrorAction Stop } catch { Write-Warning $_.Exception.Message } } else { Write-Host 'Build complete. BurntToast is not installed.' }"

goto finish

rem ----------------------------------------------------------------
rem waveform viewers
rem ----------------------------------------------------------------
:run_live_wave_view
set GUI_VIEW=
if defined WAVE_CONFIG set GUI_VIEW=-view "%WAVE_CONFIG:\=/%"
set "LIVE_WDB_PATH=%WDB_PATH%"
> gui_run.tcl echo if {![llength [get_wave_configs *]]} {create_wave_config}
if defined NO_WDB (
    set "LIVE_WDB_PATH=%PATH_LOG%\live_tmp.wdb"
    >> gui_run.tcl echo run all
) else (
    >> gui_run.tcl echo set wave_live 1
    >> gui_run.tcl echo source {%WAVE_SETUP:\=/%}
)
call xsim.bat behav_tb -log simulate.log %SIM_FLAGS% -wdb "%LIVE_WDB_PATH:\=/%" -gui %GUI_VIEW% -onfinish stop -tclbatch gui_run.tcl
set "LIVE_EXIT_CODE=%ERRORLEVEL%"
if defined NO_WDB if exist "%LIVE_WDB_PATH%" del /q "%LIVE_WDB_PATH%"
exit /b %LIVE_EXIT_CODE%

:open_wave_view
set "VIEW_DIR=%ROOT%\.log\wave_viewer"
if not exist "%VIEW_DIR%\" mkdir "%VIEW_DIR%"
set "VIEW_REQUEST=%VIEW_DIR%\%RANDOM%-%RANDOM%-%RANDOM%"
mkdir "%VIEW_REQUEST%" || exit /b 1
powershell.exe -NoProfile -NonInteractive -Command ^
    "$ErrorActionPreference = 'Stop';" ^
    "$request = $env:VIEW_REQUEST;" ^
    "Copy-Item -LiteralPath $env:WDB_PATH -Destination $request;" ^
    "[IO.File]::WriteAllText((Join-Path $request 'config.txt'), [string]$env:WAVE_CONFIG);" ^
    "New-Item -ItemType File -Path (Join-Path $request 'ready') | Out-Null"
if errorlevel 1 exit /b 1

rem A fresh heartbeat identifies the Vivado window connected to this repository.
powershell.exe -NoProfile -NonInteractive -Command ^
    "$heartbeat = Get-Item -LiteralPath (Join-Path $env:VIEW_DIR 'heartbeat') -ErrorAction SilentlyContinue;" ^
    "if (!$heartbeat -or ((Get-Date) - $heartbeat.LastWriteTime).TotalSeconds -gt 5) { exit 1 }"
if errorlevel 1 (
    where /q vivado.bat || exit /b 1
    rem Keep the viewer batch file and its directory stack in a child shell.
    start "Vivado waveform viewer" /b /d "%VIEW_DIR%" "%ComSpec%" /d /c call vivado.bat -mode gui -source "%ROOT:\=/%/scripts/wave_viewer.tcl" -log wave_view.log -journal wave_view.jou
)
powershell.exe -NoProfile -NonInteractive -Command ^
    "$result = Join-Path $env:VIEW_REQUEST 'result.txt';" ^
    "$deadline = (Get-Date).AddMinutes(3);" ^
    "while (!(Test-Path -LiteralPath $result)) {" ^
    "    if ((Get-Date) -ge $deadline) { Write-Error 'Vivado did not acknowledge the waveform request.'; exit 1 };" ^
    "    Start-Sleep -Milliseconds 300" ^
    "};" ^
    "$message = Get-Content -LiteralPath $result -Raw;" ^
    "if ($message.Trim() -ne 'OK') { Write-Error $message; exit 1 }"
exit /b %ERRORLEVEL%

rem ----------------------------------------------------------------
rem source manifest
rem ----------------------------------------------------------------
:: Each manifest entry is a path relative to the TB directory.
:add_source
set "SOURCE=%~1"
if "%SOURCE:~0,1%"=="#" exit /b 0
if "%SOURCE:~0,2%"=="//" exit /b 0
if defined NETLIST if /i "%~dp1"=="%TB_SIM_RTL_DIR%\" exit /b 0
if not exist "%SOURCE%" (
    echo [ ERROR ] Source not found: "%SOURCE%". 1>&2
    exit /b 1
)
if exist "%SOURCE%\" (
    echo [ ERROR ] Expected a source file: "%SOURCE%". 1>&2
    exit /b 1
)
set "SOURCE_PATH=%~f1"
set "SOURCE_DIR=%~dp1"
if /i "%~x1"==".c" (
    set C_SOURCES=%C_SOURCES% "%SOURCE_PATH%"
    exit /b 0
)
if /i not "%~x1"==".v" if /i not "%~x1"==".sv" (
    echo [ ERROR ] Unsupported source extension: "%SOURCE%". 1>&2
    exit /b 1
)
>> "%PATH_LOG%\compile_args.f" echo -i "%SOURCE_DIR:\=/%"
>> "%PATH_LOG%\sources.prj" echo sv work "%SOURCE_PATH:\=/%"
exit /b %ERRORLEVEL%

rem ----------------------------------------------------------------
rem error
rem ----------------------------------------------------------------
:error_args
echo Usage: %SCRIPT_NAME% [testbench] [--skip-compile] [--no-wdb] [--gui-live ^| --gui] 1>&2
echo Default: tb_core. --no-wdb ignores --gui and allows --gui-live. 1>&2
exit /b 2

:error_input_gap
echo [ ERROR ] INPUT_GAP must be nonnegative. 1>&2
exit /b 2

:error_netlist
echo [ ERROR ] Functional netlist missing or empty: "%NETLIST%". 1>&2
echo [ INFO ] Generate it with: "%~dp0synthesis.bat" %TB_NAME% 1>&2
set "EXIT_CODE=1"
goto finish

:error_sources
echo [ ERROR ] Could not prepare sources from "%TB_FILES%" in "%PATH_LOG%". 1>&2
set "EXIT_CODE=1"
goto finish

:error_wave_config
echo [ ERROR ] Could not prepare waveform capture for %TB_NAME%. 1>&2
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

:error_snapshot
echo [ ERROR ] Simulation snapshot or required data missing in "%PATH_LOG%". 1>&2
echo [ INFO ] Run %SCRIPT_NAME% %TB_NAME% without --skip-compile to build it. 1>&2
set "EXIT_CODE=1"
goto finish

:error_snapshot_debug
echo [ ERROR ] The existing snapshot was not built with -debug all. 1>&2
echo [ INFO ] Run %SCRIPT_NAME% %TB_NAME% without --skip-compile to rebuild it. 1>&2
set "EXIT_CODE=1"
goto finish

:error_snapshot_gui_debug
echo [ ERROR ] The existing snapshot does not support the live waveform view. 1>&2
echo [ INFO ] Run %SCRIPT_NAME% %TB_NAME% --gui-live --no-wdb without --skip-compile to rebuild it. 1>&2
set "EXIT_CODE=1"
goto finish

:error_wave_view
echo [ ERROR ] Could not open the waveform in Vivado. WDB: "%WDB_PATH%". Viewer logs: "%VIEW_DIR%". 1>&2
set "EXIT_CODE=1"
goto finish

:error_simulate
echo [ ERROR ] Could not complete the XSim run. See "%PATH_LOG%\simulate.log". 1>&2
set "EXIT_CODE=1"

:finish
if "%PATH_PUSHED%"=="1" popd
exit /b %EXIT_CODE%
