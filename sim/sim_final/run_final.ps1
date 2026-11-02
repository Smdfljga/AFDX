param(
    [string]$ModelSimBin = '',
    [string]$BuildDir = '',
    [string]$ReportPath = ''
)
# Compile our RTL (board top.v needs vendor MAC/PLL sim models, so it is excluded) plus every TB in the three category folders.
# Run each TB and judge PASS/FAIL. tb_afdx_rx and tb_afdx_tx are waveform-only (no PASS print): pass = reached $finish with no FAIL/Error.
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$projectRoot = Split-Path -Parent (Split-Path -Parent $here)
if ($ModelSimBin -eq '') {
    $vsimCommand = Get-Command vsim.exe -ErrorAction SilentlyContinue
    if (!$vsimCommand) { throw 'Pass -ModelSimBin with the ModelSim win64 directory.' }
    $ModelSimBin = Split-Path -Parent $vsimCommand.Source
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
        if ($LASTEXITCODE -ne 0) { throw 'vlib failed' }
    }
    $files = @((Join-Path $projectRoot 'sim\ip_sim_models.v'))
    $files += @(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'elinx\rtl') -Filter '*.v' |
                Where-Object { $_.Name -ne 'top.v' } | Sort-Object Name | ForEach-Object { $_.FullName })
    # testbenches live in the three category sub folders (recursive search)
    $testFiles = @(Get-ChildItem -LiteralPath $here -Recurse -Filter 'tb*.v' | Sort-Object FullName)
    $files += @($testFiles | ForEach-Object { $_.FullName })
    $compileOutput = & (Join-Path $ModelSimBin 'vlog.exe') -work work $files 2>&1
    $compileCode = $LASTEXITCODE
    $compileOutput | Out-File -LiteralPath 'compile.log' -Encoding UTF8
    if ($compileCode -ne 0) { throw ('vlog failed. See ' + (Join-Path $BuildDir 'compile.log')) }
    $results = @()
    foreach ($test in $testFiles) {
        $name = $test.BaseName
        $logPath = Join-Path $BuildDir ($name + '.log')
        & (Join-Path $ModelSimBin 'vsim.exe') -c -onfinish exit -l $logPath ('work.' + $name) -do 'run 30 ms; quit -code 3' | Out-Null
        $exitCode = $LASTEXITCODE
        $log = [IO.File]::ReadAllText($logPath)
        $hasFailure = $log -match '\bFAIL(?:ED)?\b|failures[:=]\s*[1-9]|result:\s*[1-9][0-9]*\s+failures|\*\* (Error|Fatal)'
        $waveOnly = $name -in @('tb_afdx_rx','tb_afdx_tx')
        $hasPass = $log -match '\bPASS(?:ED)?\b'
        $completed = $log -match '\$finish'
        $ok = $exitCode -eq 0 -and !$hasFailure -and $completed -and ($hasPass -or $waveOnly)
        $results += [pscustomobject]@{
            category = $test.Directory.Name
            test = $name
            result = $(if ($ok) { 'PASS' } else { 'FAIL' })
            kind = $(if ($waveOnly) { 'waveform_only' } else { 'self_checking' })
            exitCode = $exitCode
        }
        Write-Output ($test.Directory.Name + ' / ' + $name + ': ' + $results[-1].result)
    }
    $failed = @($results | Where-Object { $_.result -ne 'PASS' })
    $report = [pscustomobject]@{
        result = $(if ($failed.Count -eq 0) { 'PASS' } else { 'FAIL' })
        simulator = 'ModelSim SE-64 2020.4'
        compileErrors = 0
        total = $results.Count
        selfChecking = @($results | Where-Object { $_.kind -eq 'self_checking' }).Count
        waveformOnly = @($results | Where-Object { $_.kind -eq 'waveform_only' }).Count
        tests = $results
    }
    $json = ConvertTo-Json -InputObject $report -Depth 30
    if ($ReportPath -ne '') { [IO.File]::WriteAllText([IO.Path]::GetFullPath($ReportPath), $json, [Text.Encoding]::UTF8) }
    Write-Output ('total=' + $results.Count + ' failed=' + $failed.Count)
    Write-Output $json
    if ($failed.Count -gt 0) { exit 1 }
}
finally { Set-Location -LiteralPath $previousLocation }
