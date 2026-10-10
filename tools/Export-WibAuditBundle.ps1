#Requires -Version 5.1
<#
.SYNOPSIS
    Exports all Windows Image Builder (WIB) project files into a single consolidated audit text file.
    Includes file metadata, SHA-256 cryptographic hashes, line counts, and verbatim file contents.
    PowerShell 5.1+ compatible.

.EXAMPLE
    .\tools\Export-WibAuditBundle.ps1 -OutputFile WIB_AUDIT_ALL_FILES.txt
#>

[CmdletBinding()]
param(
    [string]$OutputFile = 'WIB_AUDIT_ALL_FILES.txt',
    [switch]$IncludeDevSkill
)

$ErrorActionPreference = 'Stop'
$toolRoot = Split-Path -Parent $PSScriptRoot
if (-not $toolRoot) { $toolRoot = (Get-Item -LiteralPath '.').FullName }

# Resolve absolute output path
$outFullPath = [System.IO.Path]::GetFullPath((Join-Path $toolRoot $OutputFile))

# Define Core Project Files in logical architectural order
$coreFiles = @(
    # Root documentation, licensing & configuration
    'Windows Image Builder_ Blueprint.md',
    'WIB-plan.md',
    'README.md',
    'CHANGELOG.md',
    'GATES.md',
    'docs\COMPATIBILITY.md',
    'LICENSE',
    'NOTICE',
    '.gitignore',
    'PSScriptAnalyzerSettings.psd1',
    'build.ps1',
    '.github\workflows\ci.yml',

    # Core engine libraries
    'lib\Core.ps1',
    'lib\Hardware.ps1',
    'lib\Compact.ps1',
    'lib\Planner.ps1',
    'lib\Engine.ps1',
    'lib\Report.ps1',

    # Module definitions
    'modules\10-removal.ps1',
    'modules\20-tweaks.ps1',
    'modules\30-security-optins.ps1',
    'modules\40-hardening.ps1',

    # Build Profiles
    'profiles\balanced.json',
    'profiles\lean.json',
    'profiles\adaptive.json',
    'profiles\hardening.json',
    'profiles\custom-risk.json',

    # Target Hardware Specifications
    'specs\desktop.json',
    'specs\laptop.json',

    # Templates
    'templates\autounattend.template.xml',

    # Standalone Tools & GUIs
    'tools\WibBuilderGui.ps1',
    'tools\WibPanel.ps1',
    'tools\wib-compact.ps1',
    'tools\wib-profile.ps1',
    'tools\New-WibUnattend.ps1',
    'tools\Invoke-WibVmBenchmark.ps1',
    'tools\Export-WibAuditBundle.ps1',

    # Test suites & live test evidence
    'tests\smoke.ps1',
    'tests\verify-gates.ps1',
    'tests\integration-dism.ps1',
    'smoke_results.json'
)

# Optional wib-dev developer contract & architectural references
$devSkillFiles = @(
    '.agents\skills\wib-dev\SKILL.md',
    '.agents\skills\wib-dev\scripts\test-syntax.ps1',
    '.agents\skills\wib-dev\tests\wib-dev-contract.Tests.ps1',
    '.agents\skills\wib-dev\examples\sample-module.ps1',
    '.agents\skills\wib-dev\examples\sample-profile.json',
    '.agents\skills\wib-dev\references\architecture.md',
    '.agents\skills\wib-dev\references\checkpoints.md',
    '.agents\skills\wib-dev\references\ci-hardening.md',
    '.agents\skills\wib-dev\references\ci-security.md',
    '.agents\skills\wib-dev\references\dism.md',
    '.agents\skills\wib-dev\references\dism-workflow.md',
    '.agents\skills\wib-dev\references\hardware-adaptation.md',
    '.agents\skills\wib-dev\references\module-contract.md',
    '.agents\skills\wib-dev\references\offline-registry.md',
    '.agents\skills\wib-dev\references\pester5-patterns.md',
    '.agents\skills\wib-dev\references\powershell-5.1.md',
    '.agents\skills\wib-dev\references\ps51-pitfalls.md',
    '.agents\skills\wib-dev\references\reproducibility.md',
    '.agents\skills\wib-dev\references\rollback.md',
    '.agents\skills\wib-dev\references\testing.md',
    '.agents\skills\wib-dev\references\verification.md',
    '.agents\skills\wib-dev\references\wim-esd.md',
    'scripts\lint\gate-check.mjs',
    'scripts\lint\gate-lint.mjs'
)

# 1. Run smoke tests first so smoke_results.json is generated fresh and included in collected files
$smokePath = Join-Path $toolRoot 'tests\smoke.ps1'
$smokeResultsPath = Join-Path $toolRoot 'smoke_results.json'
$smokeTotal   = 0
$smokePassed  = 0
$smokeFailed  = 0
$smokeExitCode = -1
$smokeTimestamp = ''
$smokeOutput   = ''
if (Test-Path -LiteralPath $smokePath) {
    Write-Host '[*] Running smoke tests to capture live evidence...' -ForegroundColor Cyan
    $smokeTimestamp = (Get-Date).ToString('o')
    $smokeOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $smokePath 2>&1
    $smokeExitCode = $LASTEXITCODE
    $smokeText = $smokeOutput -join "`n"
    # Parse actual pass/fail counts from smoke output
    $passMatches = @([regex]::Matches($smokeText, '^PASS\s', [System.Text.RegularExpressions.RegexOptions]::Multiline))
    $failMatches = @([regex]::Matches($smokeText, '^FAIL\s', [System.Text.RegularExpressions.RegexOptions]::Multiline))
    $smokePassed  = $passMatches.Count
    $smokeFailed  = $failMatches.Count
    $smokeTotal   = $smokePassed + $smokeFailed
    $statusStr = 'FAIL'
    if ($smokeExitCode -eq 0) { $statusStr = 'pass' }
    $smokeResult = [ordered]@{
        timestamp  = $smokeTimestamp
        exitCode   = $smokeExitCode
        total      = $smokeTotal
        passed     = $smokePassed
        failed     = $smokeFailed
        status     = $statusStr
    }
    $smokeResult | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $smokeResultsPath -Encoding UTF8
    $smokeStatus = 'FAILED'
    $color = 'Red'
    if ($smokeExitCode -eq 0) {
        $smokeStatus = 'ALL PASS'
        $color = 'Green'
    }
    Write-Host "    Smoke result: $smokeStatus ($smokePassed/$smokeTotal assertions, exit $smokeExitCode)" -ForegroundColor $color
} else {
    Write-Warning "smoke.ps1 not found at $smokePath -- cannot generate live test evidence."
}
$smokeLabel = 'NOT RUN'
if ($smokeTotal -gt 0) {
    $smokeLabel = "$smokePassed / $smokeTotal Assertions Passing (exit $smokeExitCode)"
}

$fileList = @($coreFiles)
if ($IncludeDevSkill -or $true) {
    $fileList += $devSkillFiles
}

# Collect file info (including fresh smoke_results.json)
$collected = New-Object System.Collections.ArrayList
$sha256 = [System.Security.Cryptography.SHA256]::Create()

foreach ($relPath in $fileList) {
    $fullPath = Join-Path $toolRoot $relPath
    if (Test-Path -LiteralPath $fullPath) {
        $item = Get-Item -LiteralPath $fullPath
        $bytes = [System.IO.File]::ReadAllBytes($fullPath)
        $hashBytes = $sha256.ComputeHash($bytes)
        $hashStr = -join ($hashBytes | ForEach-Object { '{0:x2}' -f $_ })
        $lines = @([System.IO.File]::ReadAllLines($fullPath)).Count

        [void]$collected.Add([PSCustomObject]@{
            RelativePath = $relPath
            FullPath     = $fullPath
            Size         = $item.Length
            Lines        = $lines
            Sha256       = $hashStr
        })
    } else {
        Write-Warning "File not found: $fullPath"
    }
}

# Build consolidated audit document
$sb = New-Object System.Text.StringBuilder

$null = $sb.AppendLine("================================================================================")
$null = $sb.AppendLine("                 WINDOWS IMAGE BUILDER (WIB) - PROJECT AUDIT DUMP                ")
$null = $sb.AppendLine("================================================================================")
# Dynamically extract runtime tool version from lib/Core.ps1
$corePath = Join-Path $toolRoot 'lib\Core.ps1'
$runtimeVersion = '0.2.4'
if (Test-Path -LiteralPath $corePath) {
    $coreMatch = Select-String -Path $corePath -Pattern '^\s*\$script:WibVersion\s*=\s*[''"]([^''"]+)[''"]' | Select-Object -First 1
    if ($coreMatch -and $coreMatch.Matches.Groups.Count -gt 1) {
        $runtimeVersion = $coreMatch.Matches.Groups[1].Value
    }
}

$null = $sb.AppendLine("Project Name     : Windows Image Builder (WIB)")
$null = $sb.AppendLine("Tool Version     : $runtimeVersion")
$null = $sb.AppendLine("Generated At     : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$null = $sb.AppendLine("Repository Root  : $toolRoot")
$null = $sb.AppendLine("Total Files      : $($collected.Count)")
$totalBytes = ($collected | Measure-Object -Property Size -Sum).Sum
$totalLines = ($collected | Measure-Object -Property Lines -Sum).Sum
$null = $sb.AppendLine("Total Code Lines : $totalLines")
# Verified tests label already computed from live run during file collection
$null = $sb.AppendLine("Verified Tests   : $smokeLabel (tests/smoke.ps1 -- live run at bundle time)")
$null = $sb.AppendLine("Compatibility    : Windows PowerShell 5.1 & PowerShell 7+ | Pure First-Party Tools")
$null = $sb.AppendLine("================================================================================")
$null = $sb.AppendLine()
$null = $sb.AppendLine("TABLE OF CONTENTS / MANIFEST")
$null = $sb.AppendLine("--------------------------------------------------------------------------------")
$fmt = "{0,-4} | {1,-42} | {2,8} | {3,6} | {4}"
$null = $sb.AppendLine([string]::Format($fmt, [object[]]@("NO", "RELATIVE PATH", "BYTES", "LINES", "SHA-256")))
$null = $sb.AppendLine("--------------------------------------------------------------------------------")

$idx = 1
foreach ($f in $collected) {
    $null = $sb.AppendLine([string]::Format($fmt, [object[]]@($idx, $f.RelativePath, $f.Size, $f.Lines, $f.Sha256)))
    $idx++
}

$null = $sb.AppendLine("--------------------------------------------------------------------------------")
$null = $sb.AppendLine()
$null = $sb.AppendLine()

# Append each file content verbatim
$idx = 1
foreach ($f in $collected) {
    $null = $sb.AppendLine("================================================================================")
    $null = $sb.AppendLine(("FILE [{0}/{1}]: {2}" -f @($idx, $collected.Count, $f.RelativePath)))
    $null = $sb.AppendLine(("LOCATION   : {0}" -f $f.FullPath))
    $null = $sb.AppendLine(("SIZE       : {0:N0} bytes" -f $f.Size))
    $null = $sb.AppendLine(("LINES      : {0:N0} lines" -f $f.Lines))
    $null = $sb.AppendLine(("SHA-256    : {0}" -f $f.Sha256))
    $null = $sb.AppendLine("================================================================================")
    $null = $sb.AppendLine()

    $content = [System.IO.File]::ReadAllText($f.FullPath, [System.Text.Encoding]::UTF8)
    $null = $sb.AppendLine($content)

    if (-not $content.EndsWith("`n")) {
        $null = $sb.AppendLine()
    }
    $null = $sb.AppendLine()
    $null = $sb.AppendLine("--------------------------------------------------------------------------------")
    $null = $sb.AppendLine(("[END OF FILE: {0}]" -f $f.RelativePath))
    $null = $sb.AppendLine("--------------------------------------------------------------------------------")
    $null = $sb.AppendLine()
    $null = $sb.AppendLine()
    $idx++
}

# Write consolidated text file in UTF-8
[System.IO.File]::WriteAllText($outFullPath, $sb.ToString(), [System.Text.Encoding]::UTF8)

Write-Host "Consolidated audit file created successfully!" -ForegroundColor Green
Write-Host "  File Path   : $outFullPath" -ForegroundColor Cyan
Write-Host "  Total Files : $($collected.Count)" -ForegroundColor Gray
Write-Host "  Total Size  : $([math]::Round((Get-Item -LiteralPath $outFullPath).Length / 1KB, 1)) KB" -ForegroundColor Gray
Write-Host "  Total Lines : $totalLines" -ForegroundColor Gray

return [PSCustomObject]@{
    OutputPath = $outFullPath
    FileCount  = $collected.Count
    TotalBytes = (Get-Item -LiteralPath $outFullPath).Length
    TotalLines = $totalLines
}
