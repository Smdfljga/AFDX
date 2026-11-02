$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$ipRoot = Join-Path $projectRoot 'elinx\afdx.srcs\sources_1\ip'
foreach ($eci in Get-ChildItem -LiteralPath $ipRoot -Recurse -Filter '*.eci') {
    $sourcePath = Join-Path $eci.DirectoryName ($eci.BaseName + '.v')
    if (!(Test-Path -LiteralPath $sourcePath)) { throw ('IP source missing: ' + $sourcePath) }
    $content = [IO.File]::ReadAllText($eci.FullName, [Text.Encoding]::UTF8)
    $escaped = [Security.SecurityElement]::Escape($sourcePath.Replace('\','/'))
    $updated = [regex]::Replace($content, '<spirit:file>[^<]*</spirit:file>', ('<spirit:file>' + $escaped + '</spirit:file>'))
    [IO.File]::WriteAllText($eci.FullName, $updated, [Text.UTF8Encoding]::new($false))
}
Write-Output 'Updated 8 IP metadata source paths. Generated IP Verilog is unchanged.'
