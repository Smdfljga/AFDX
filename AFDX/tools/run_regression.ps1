param(
    [string]$ModelSimBin = '',
    [string]$BuildDir = '',
    [string]$ReportPath = ''
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if ($ModelSimBin -eq '') {
    $vsimCommand = Get-Command vsim.exe -ErrorAction SilentlyContinue
    if (!$vsimCommand) { throw 'Pass -ModelSimBin with the ModelSim win64 directory.' }
    $ModelSimBin = Split-Path -Parent $vsimCommand.Source
}
foreach ($exe in @('vlib.exe','vlog.exe','vsim.exe')) {
    if (!(Test-Path -LiteralPath (Join-Path $ModelSimBin $exe))) { throw ('Missing ' + $exe) }
}
if ($BuildDir -eq '') { $BuildDir = Join-Path $projectRoot 'sim_build' }
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
    # Module-level regression compiles only our own RTL. top.v is the board wrapper
    # (PLL + two MAC IPs) and needs vendor IP sim models; its joint sim is separate.
    $files += @(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'elinx\rtl') -Filter '*.v' |
                Where-Object { $_.Name -ne 'top.v' } | Sort-Object Name | ForEach-Object { $_.FullName })
    $testFiles = @(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'sim') -Filter 'tb*.v' | Sort-Object Name)
    $files += @($testFiles | ForEach-Object { $_.FullName })
    $compileOutput = & (Join-Path $ModelSimBin 'vlog.exe') -work work $files 2>&1
    $compileCode = $LASTEXITCODE
    $compileOutput | Out-File -LiteralPath 'compile.log' -Encoding UTF8
    if ($compileCode -ne 0) { throw ('vlog failed. See ' + (Join-Path $BuildDir 'compile.log')) }
    $results = @()
    foreach ($test in $testFiles) {
        $name = $test.BaseName
        $logPath = Join-Path $BuildDir ($name + '.log')
        & (Join-Path $ModelSimBin 'vsim.exe') -c -onfinish exit -l $logPath ('work.' + $name) -do 'run 20 ms; quit -code 3' | Out-Null
        $exitCode = $LASTEXITCODE
        $log = [IO.File]::ReadAllText($logPath)
        $hasFailure = $log -match '\bFAIL(?:ED)?\b|failures[:=]\s*[1-9]|result:\s*[1-9][0-9]*\s+failures|\*\* (Error|Fatal)'
        $waveOnly = $name -in @('tb_afdx_rx','tb_afdx_tx')
        $hasPass = $log -match '\bPASS(?:ED)?\b'
        $completed = $log -match '\$finish'
        $ok = $exitCode -eq 0 -and !$hasFailure -and $completed -and ($hasPass -or $waveOnly)
        $results += [pscustomobject]@{
            test = $name
            result = $(if ($ok) { 'PASS' } else { 'FAIL' })
            kind = $(if ($waveOnly) { 'stimulus_and_waveform_only' } else { 'self_checking' })
            exitCode = $exitCode
        }
        Write-Output ($name + ': ' + $results[-1].result)
    }
    $failed = @($results | Where-Object { $_.result -ne 'PASS' })
    $report = [pscustomobject]@{
        result = $(if ($failed.Count -eq 0) { 'PASS' } else { 'FAIL' })
        simulator = 'ModelSim SE-64 10.4'
        compileErrors = 0
        compileWarnings = $(if (($compileOutput -join "`n") -match 'Errors: 0, Warnings: 0') { 0 } else { 'See compile.log' })
        total = $results.Count
        selfChecking = @($results | Where-Object { $_.kind -eq 'self_checking' }).Count
        waveformOnly = @($results | Where-Object { $_.kind -eq 'stimulus_and_waveform_only' }).Count
        tests = $results
    }
    $json = ConvertTo-Json -InputObject $report -Depth 30
    if ($ReportPath -ne '') { [IO.File]::WriteAllText([IO.Path]::GetFullPath($ReportPath), $json, [Text.Encoding]::UTF8) }
    Write-Output $json
    if ($failed.Count -gt 0) { exit 1 }
}
finally { Set-Location -LiteralPath $previousLocation }
