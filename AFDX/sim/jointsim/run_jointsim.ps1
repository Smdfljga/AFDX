param(
    [string]$ModelSimBin = '',
    [string]$BuildDir = ''
)
# Joint simulation runner for sim/jointsim.
# DUT is AFDX_top (and afdx_net_rx for the dual-net case); MAC/PLL IPs are not compiled.
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$projectRoot = Split-Path -Parent (Split-Path -Parent $here)
if ($ModelSimBin -eq '') {
    $vsim = Get-Command vsim.exe -ErrorAction SilentlyContinue
    if (!$vsim) { throw 'Pass -ModelSimBin with the ModelSim win64 directory.' }
    $ModelSimBin = Split-Path -Parent $vsim.Source
}
foreach ($exe in @('vlib.exe','vlog.exe','vsim.exe')) {
    if (!(Test-Path -LiteralPath (Join-Path $ModelSimBin $exe))) { throw ('Missing ' + $exe) }
}
if ($BuildDir -eq '') { $BuildDir = Join-Path $here '_build' }
$BuildDir = [IO.Path]::GetFullPath($BuildDir)
New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null
$previousLocation = Get-Location
try {
    Set-Location -LiteralPath $BuildDir
    if (!(Test-Path -LiteralPath 'work\_info')) {
        & (Join-Path $ModelSimBin 'vlib.exe') work | Out-Null
    }
    $files = @((Join-Path $projectRoot 'sim\ip_sim_models.v'))
    # Module-level regression needs our RTL only; top.v is the board wrapper (has vendor MAC/PLL IPs).
    $files += @(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'elinx\rtl') -Filter '*.v' |
                Where-Object { $_.Name -ne 'top.v' } | Sort-Object Name | ForEach-Object { $_.FullName })
    $testFiles = @(Get-ChildItem -LiteralPath $here -Filter 'tb*.v' | Sort-Object Name)
    $files += @($testFiles | ForEach-Object { $_.FullName })
    $compileOutput = & (Join-Path $ModelSimBin 'vlog.exe') -work work $files 2>&1
    $compileOutput | Out-File -LiteralPath 'compile.log' -Encoding UTF8
    if ($LASTEXITCODE -ne 0) { throw ('vlog failed. See ' + (Join-Path $BuildDir 'compile.log')) }
    $results = @()
    foreach ($test in $testFiles) {
        $name = $test.BaseName
        $logPath = Join-Path $BuildDir ($name + '.log')
        & (Join-Path $ModelSimBin 'vsim.exe') -c -onfinish exit -l $logPath ('work.' + $name) -do 'run 30 ms; quit -code 3' | Out-Null
        $log = [IO.File]::ReadAllText($logPath)
        $ok = ($log -match '(?m)^# PASS:') -and -not ($log -match '\[FAIL\]') -and ($log -match '\$finish')
        $results += [pscustomobject]@{ test = $name; result = $(if ($ok) { 'PASS' } else { 'FAIL' }) }
        Write-Output ($name + ': ' + $results[-1].result)
    }
    $failed = @($results | Where-Object { $_.result -ne 'PASS' })
    Write-Output ('total=' + $results.Count + ' failed=' + $failed.Count)
    if ($failed.Count -gt 0) { exit 1 }
}
finally { Set-Location -LiteralPath $previousLocation }
