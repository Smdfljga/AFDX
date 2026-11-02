param(
    [string]$ModelSimBin = '',
    [string]$BuildDir = ''
)
# Compile RTL + every TB against the real vendor IP wrappers (elinx_lib) instead of sim/ip_sim_models.v.
# This is the "same TB, real RAM IP" check: it must give the same PASS results as run_final.ps1.
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$projectRoot = Split-Path -Parent (Split-Path -Parent $here)
if ($ModelSimBin -eq '') { $ModelSimBin = 'D:\Program Files\ModelSim\win64' }
if ($BuildDir -eq '') { $BuildDir = Join-Path $here '_build_vendor' }
$BuildDir = [IO.Path]::GetFullPath($BuildDir)
New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null
$previousLocation = Get-Location
try {
    Set-Location -LiteralPath $BuildDir
    if (!(Test-Path -LiteralPath 'work\_info')) {
        & (Join-Path $ModelSimBin 'vlib.exe') work | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'vlib failed' }
    }
    $files = @(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'elinx\afdx.srcs\sources_1\ip') -Recurse -Filter '*.v' |
               Where-Object { $_.Name -notin @('eth_1.v','eth_2.v','pll.v') } |
               Sort-Object Name | ForEach-Object { $_.FullName })
    $files += @(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'elinx\rtl') -Filter '*.v' |
                Where-Object { $_.Name -ne 'top.v' } | Sort-Object Name | ForEach-Object { $_.FullName })
    $testFiles = @(Get-ChildItem -LiteralPath $here -Recurse -Filter 'tb*.v' | Sort-Object FullName)
    $files += @($testFiles | ForEach-Object { $_.FullName })
    $compileOutput = & (Join-Path $ModelSimBin 'vlog.exe') -work work $files 2>&1
    $compileOutput | Out-File -LiteralPath 'compile_vendor.log' -Encoding UTF8
    if ($LASTEXITCODE -ne 0) { throw ('vlog failed. See ' + (Join-Path $BuildDir 'compile_vendor.log')) }
    $results = @()
    foreach ($test in $testFiles) {
        $name = $test.BaseName
        $logPath = Join-Path $BuildDir ($name + '.log')
        & (Join-Path $ModelSimBin 'vsim.exe') -c -onfinish exit -l $logPath -L elinx_lib ('work.' + $name) -do 'run 30 ms; quit -code 3' | Out-Null
        $exitCode = $LASTEXITCODE
        $log = [IO.File]::ReadAllText($logPath)
        $hasFailure = $log -match '\bFAIL(?:ED)?\b|failures[:=]\s*[1-9]|\*\* (Error|Fatal)'
        $waveOnly = $name -in @('tb_afdx_rx', 'tb_afdx_tx')
        $hasPass = $log -match '\bPASS(?:ED)?\b'
        $completed = $log -match '\$finish'
        $ok = $exitCode -eq 0 -and !$hasFailure -and $completed -and ($hasPass -or $waveOnly)
        $results += [pscustomobject]@{
            category = $test.Directory.Name
            test = $name
            result = $(if ($ok) { 'PASS' } else { 'FAIL' })
        }
        Write-Output ($test.Directory.Name + ' / ' + $name + ': ' + $results[-1].result)
    }
    $failed = @($results | Where-Object { $_.result -ne 'PASS' })
    Write-Output ('vendor-IP run: total=' + $results.Count + ' failed=' + $failed.Count)
    if ($failed.Count -gt 0) { exit 1 }
}
finally { Set-Location -LiteralPath $previousLocation }
