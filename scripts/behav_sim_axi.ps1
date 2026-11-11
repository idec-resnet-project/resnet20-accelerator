[CmdletBinding()]
param(
    [ValidateSet('all', 'model_unit_test', 'model_fault_test',
        'model_regression_test', 'model_inference_test')]
    [string]$Test = 'all',
    [ValidateRange(1, 2147483647)]
    [int]$Seed = 1
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$tb = (Join-Path $root 'tb/tb_axi_bottleneck').Replace('\', '/')
$build = Join-Path $root 'build/sim/tb_axi_bottleneck'
$sources = Get-Content -LiteralPath (Join-Path $tb 'tb_axi_bottleneck.f') |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -and -not $_.StartsWith('#') } |
    ForEach-Object { "$tb/$_" }
$dpiSources = @('resnet20/resnet20_compute.c') | ForEach-Object { "$tb/$_" }

function Invoke-VivadoTool {
    param([string]$Tool, [string[]]$Arguments)
    & $Tool @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Tool failed with exit code $LASTEXITCODE"
    }
}

foreach ($tool in 'xsc', 'xvlog', 'xelab', 'xsim') {
    Get-Command $tool -ErrorAction Stop | Out-Null
}
New-Item -ItemType Directory -Path $build -Force | Out-Null
Push-Location -LiteralPath $build
try {
    # XSim 2022.2 embeds DPI declaration paths in generated C strings.
    Invoke-VivadoTool xsc @($dpiSources)
    Invoke-VivadoTool xvlog (@('-sv', '-L', 'uvm', '-i', $tb, '-log', 'compile.log') + $sources)
    Invoke-VivadoTool xelab @('-L', 'uvm', '-timescale', '1ns/1ps',
        '-sv_root', 'xsim.dir/work/xsc', '-sv_lib', 'dpi',
        'tb_axi_bottleneck', '-s', 'axi_tb', '-log', 'elaborate.log')

    $tests = @($Test)
    if ($Test -eq 'all') {
        $tests = @('model_unit_test', 'model_fault_test', 'model_regression_test', 'model_inference_test')
    }
    $failures = @()
    foreach ($name in $tests) {
        Write-Host "Running $name with seed $Seed"
        $log = "$name.log"
        @(
            "-testplusarg `"UVM_TESTNAME=$name`""
            '-testplusarg "TB_DIR=../../../tb/tb_axi_bottleneck"'
        ) | Set-Content -LiteralPath 'sim_args.f' -Encoding ascii
        try {
            Invoke-VivadoTool xsim @('axi_tb', '-f', 'sim_args.f', '-sv_seed', $Seed,
                '-runall', '-log', $log)
            $result = Get-Content -LiteralPath $log -Raw
            if ($result -notmatch '(?m)UVM_ERROR\s*:\s*0\s*$' -or
                $result -notmatch '(?m)UVM_FATAL\s*:\s*0\s*$' -or
                $result -notmatch '\[COUNTS\]' -or
                $result -match '(?m)^\s*(Fatal:|ERROR:)') {
                throw "Review $log"
            }
        } catch {
            $failures += "$name ($($_.Exception.Message))"
        }
    }
    if ($failures.Count -ne 0) { throw "Simulation failures: $($failures -join ', ')" }
} finally {
    Pop-Location
}
