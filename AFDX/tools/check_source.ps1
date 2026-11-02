param([string]$ReportPath = '')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$baselinePath = Join-Path $projectRoot 'verification\original_fsm_baseline.json'
$baseline = Get-Content -LiteralPath $baselinePath -Raw -Encoding UTF8 | ConvertFrom-Json
function Remove-Comments([string]$Text) {
    $clean = [regex]::Replace($Text, '/\*[\s\S]*?\*/', '')
    return [regex]::Replace($clean, '//[^\r\n]*', '')
}
function Normalize-Code([string]$Text) {
    return [regex]::Replace((Remove-Comments $Text), '\s+', '')
}
function Get-Hash([string]$Text) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}
function Get-Protected([string]$Text) {
    $clean = Remove-Comments $Text
    $comb = @()
    foreach ($match in [regex]::Matches($clean, 'always\s*@\s*\(\s*\*\s*\)\s*begin\b')) {
        $start = $match.Index
        $beginPos = $start + $match.Length - 5
        $depth = 0
        $blockEnd = -1
        foreach ($token in [regex]::Matches($clean.Substring($beginPos), '\bbegin\b|\bend\b')) {
            if ($token.Value -eq 'begin') { $depth++ } else { $depth-- }
            if ($depth -eq 0) { $blockEnd = $beginPos + $token.Index + $token.Length; break }
        }
        if ($blockEnd -lt 0) { throw 'Unbalanced always block' }
        $block = $clean.Substring($start, $blockEnd - $start)
        if ($block -match '\bnxt_(state|phase)\b') { $comb += (Normalize-Code $block) }
    }
    $stateParams = @([regex]::Matches($clean, '\blocalparam\b[^;]*\b[SP]_[A-Z0-9_]+\b[^;]*;') | ForEach-Object { Normalize-Code $_.Value })
    $updates = @([regex]::Matches($clean, '\b(state|state_r|phase)\s*<=\s*[^;]+;') | ForEach-Object { Normalize-Code $_.Value })
    $stateRegisters = @([regex]::Matches($clean, '\breg\b[^;]*\b(state|state_r|phase|nxt_state|nxt_phase)\b[^;]*;') | ForEach-Object { Normalize-Code $_.Value })
    $assigns = @()
    if ($comb.Count -gt 0) { $assigns = @([regex]::Matches($clean, '\bassign\b[^;]+;') | ForEach-Object { Normalize-Code $_.Value }) }
    $moduleStart = $clean.IndexOf('module ')
    $headerEnd = $clean.IndexOf(');') + 2
    return [pscustomobject]@{
        header = Normalize-Code $clean.Substring($moduleStart, $headerEnd - $moduleStart)
        stateParams = $stateParams
        comb = $comb
        updates = $updates
        stateRegisters = $stateRegisters
        assigns = $assigns
    }
}
$issues = @()
$changed = @()
$fsmCount = 0
$stateCount = 0
$commentedLines = 0
$codeLinesWithComments = 0
foreach ($entry in $baseline.files) {
    $filePath = Join-Path $projectRoot ('elinx\rtl\' + $entry.file)
    $source = [IO.File]::ReadAllText($filePath, [Text.Encoding]::UTF8)
    $protected = Get-Protected $source
    foreach ($key in @('header','stateParams','comb','updates','stateRegisters','assigns')) {
        $before = ConvertTo-Json -InputObject $entry.protected.$key -Depth 30 -Compress
        $after = ConvertTo-Json -InputObject $protected.$key -Depth 30 -Compress
        if ($before -cne $after) { $issues += ($entry.file + ': changed frozen ' + $key) }
    }
    if ((Get-Hash (Normalize-Code $source)) -ne $entry.tokenSha256) { $changed += $entry.file }
    if ($protected.comb.Count -gt 0) { $fsmCount++ }
    $stateCount += $protected.stateParams.Count
    $lineNo = 0
    $inBlockComment = $false
    foreach ($line in ($source -split '\r?\n')) {
        $lineNo++
        if ($line.Trim() -eq '') { continue }
        if ($inBlockComment) { if ($line -match '\*/') { $inBlockComment = $false }; continue }
        if ($line -match '/\*') { if ($line -notmatch '\*/') { $inBlockComment = $true }; continue }
        if ($line -notmatch '//') { $issues += ($entry.file + ':' + $lineNo + ': missing line comment') }
        else {
            $commentedLines++
            if ($line.Substring(0, $line.IndexOf('//')).Trim() -ne '') { $codeLinesWithComments++ }
        }
    }
}
if ($baseline.vendorFiles) {
    foreach ($vendor in $baseline.vendorFiles) {
        $vendorPath = Join-Path $projectRoot $vendor.file
        if ((Get-FileHash -LiteralPath $vendorPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $vendor.sha256) {
            $issues += ($vendor.file + ': vendor IP modified')
        }
    }
}
$report = [pscustomobject]@{
    result = $(if ($issues.Count -eq 0) { 'PASS' } else { 'FAIL' })
    rtlModules = @($baseline.files).Count
    frozenFsmModules = $fsmCount
    frozenStates = $stateCount
    commentedNonemptyRtlLines = $commentedLines
    rtlCodeLinesWithComments = $codeLinesWithComments
    functionalChanges = $changed
    issues = $issues
}
$json = ConvertTo-Json -InputObject $report -Depth 30
if ($ReportPath -ne '') { [IO.File]::WriteAllText([IO.Path]::GetFullPath($ReportPath), $json, [Text.Encoding]::UTF8) }
Write-Output $json
if ($issues.Count -gt 0) { exit 1 }
