param([Parameter(Mandatory=$true)][string]$ELinxRoot)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$elinxProject = Join-Path $projectRoot 'elinx'
$exe = Join-Path $ELinxRoot 'bin\shell\bin\eLinx_synthesis.exe'
$m4k = Join-Path $ELinxRoot 'bin\shell\share\stratix\common\m4k.v'
$fifo = Join-Path $ELinxRoot 'bin\shell\share\stratix\primitive\scfifo.v'
foreach ($required in @($exe,$m4k,$fifo)) {
    if (!(Test-Path -LiteralPath $required)) { throw ('Missing eLinx component: ' + $required) }
}
$template = Get-Content -LiteralPath (Join-Path $elinxProject 'afdx_synth_check.ys') -Raw -Encoding UTF8
$template = [regex]::Replace($template, 'read_verilog -lib "[^"]*common/m4k.v"', ('read_verilog -lib "' + $m4k.Replace('\','/') + '"'))
$template = [regex]::Replace($template, 'read_verilog -lib "[^"]*primitive/scfifo.v"', ('read_verilog -lib "' + $fifo.Replace('\','/') + '"'))
$scriptPath = Join-Path $projectRoot 'verification\local_elinx_check.ys'
[IO.File]::WriteAllText($scriptPath, $template, [Text.UTF8Encoding]::new($false))
$previousLocation = Get-Location
try {
    Set-Location -LiteralPath $elinxProject
    & $exe -s $scriptPath
    if ($LASTEXITCODE -ne 0) { throw 'eLinx front-end check failed' }
}
finally { Set-Location -LiteralPath $previousLocation }
