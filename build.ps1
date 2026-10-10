#Requires -Version 5.1
<#
.SYNOPSIS
    WIB - Windows Image Builder. Manifest-driven, previewable, verifiable Windows 11 image trimming.

.EXAMPLE
    .\build.ps1 -Command validate -ProfileName balanced        # validates profile schema and types without admin
    .\build.ps1 -Command list                                  # lists all registered modules with tiers and risk
    .\build.ps1 -IsoPath D:\Win11.iso -Command plan            # preview plan (dry-run)
    .\build.ps1 -IsoPath D:\Win11.iso -ProfileName lean        # build lean profile
    .\build.ps1 -IsoDrive E -WorkDir D:\wib-work -Index 6      # build from already-mounted ISO on drive E:
#>
[CmdletBinding()]
param(
    [ValidateSet('build', 'plan', 'verify', 'validate', 'list', 'repatch')][string]$Command = 'build',
    [string]$IsoPath,
    [string]$IsoDrive,
    [string]$ExpectedIsoSha256,
    [switch]$SkipIsoHash,
    [string]$ProfileName = 'balanced',     # name in .\profiles or a path to a .json file
    [string]$WorkDir,
    [string]$OutputIso,
    [int]$Index = 0,
    [switch]$DryRun,
    [switch]$KeepWork,
    [switch]$DownloadOscdimg,
    [switch]$Validate,
    [switch]$ListModules,
    [switch]$Resume,
    [switch]$Strict,
    [switch]$Force,
    [switch]$NoCheckpoints,
    [string]$SigningCertThumbprint,
    [int]$MinFreeDiskSpaceGB = 25,
    [string]$HardwareSpec,
    [switch]$AcceptRisk,
    [string]$DeltaFromManifest,
    [string]$JournalPath,
    [string]$RegistryRoot,
    [switch]$Gui
)

$ErrorActionPreference = 'Stop'
$toolRoot = $PSScriptRoot

if ($ExpectedIsoSha256) {
    $ExpectedIsoSha256 = $ExpectedIsoSha256.Trim()
}

if ($Gui) {
    $builderGui = Join-Path $toolRoot 'tools\WibBuilderGui.ps1'
    if (Test-Path -LiteralPath $builderGui) {
        & $builderGui
        return
    }
}

. (Join-Path $toolRoot 'lib\Core.ps1')
. (Join-Path $toolRoot 'lib\Planner.ps1')
. (Join-Path $toolRoot 'lib\Report.ps1')
. (Join-Path $toolRoot 'lib\Engine.ps1')
Get-ChildItem -LiteralPath (Join-Path $toolRoot 'modules') -Filter '*.ps1' | Sort-Object Name | ForEach-Object { . $_.FullName }

# Resolve aliases
if ($Validate) { $Command = 'validate' }
if ($ListModules) { $Command = 'list' }
if ($DryRun -and $Command -eq 'build') { $Command = 'plan' }

if ($Command -eq 'list') {
    Write-Host '================ WIB MODULE REGISTRY ================' -ForegroundColor Cyan
    '{0,-26} {1,-6} {2,-14} {3,-5} {4}' -f 'ID', 'RISK', 'REVERSIBILITY', 'ORDER', 'DESCRIPTION'
    Write-Host ('-' * 85)
    $script:WibModules.Values | Sort-Object { $_.Order }, { $_.Id } | ForEach-Object {
        '{0,-26} {1,-6} {2,-14} {3,-5} {4}' -f $_.Id, $_.Risk, $_.Reversibility, $_.Order, $_.Description
    }
    return
}

$profilePath = $ProfileName
if (-not (Test-Path -LiteralPath $profilePath)) { $profilePath = Join-Path $toolRoot "profiles\$ProfileName.json" }

if ($Command -eq 'validate') {
    Write-Host "Validating profile: $profilePath" -ForegroundColor Cyan
    $p = Import-WibProfile -Path $profilePath
    Test-WibProfile -BuildProfile $p -AcceptRisk:$AcceptRisk
    $canonicalHash = Get-WibProfileCanonicalHash $p
    Write-Host "VALIDATION PASS: Profile '$($p.profile)' is valid." -ForegroundColor Green
    Write-Host "Canonical SHA-256: $canonicalHash" -ForegroundColor Gray
    if ($p.parentChain -and @($p.parentChain).Count -gt 0) {
        Write-Host "Parent Chain: $(@($p.parentChain) -join ' -> ')" -ForegroundColor Gray
    }
    return
}

if ($Command -eq 'repatch') {
    $jp = $JournalPath
    if (-not $jp) { $jp = 'C:\Windows\WIB\journal.json' }
    $wibPanel = Join-Path $toolRoot 'tools\WibPanel.ps1'
    if (-not (Test-Path -LiteralPath $wibPanel)) {
        throw "WibPanel tool not found: $wibPanel"
    }
    Write-Host "Invoking WIB Update-Aware Re-patching on $jp..." -ForegroundColor Cyan
    $splat = @{
        JournalPath    = $jp
        Repatch        = $true
        NonInteractive = $true
    }
    if ($DryRun) { $splat['DryRun'] = $true }
    if ($RegistryRoot) { $splat['RegistryRoot'] = $RegistryRoot }
    $res = & $wibPanel @splat
    return $res
}

# Commands beyond this point (build, plan, verify) require Administrator privileges
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    throw "Command '$Command' requires administrator privileges. Start Windows PowerShell by using the Run as Administrator option."
}

if ($Command -eq 'plan') {
    Invoke-WibBuild -IsoPath $IsoPath -IsoDrive $IsoDrive -ExpectedIsoSha256 $ExpectedIsoSha256 -SkipIsoHash:$SkipIsoHash `
        -ProfilePath $profilePath -ToolRoot $toolRoot -WorkDir $WorkDir -OutputIso $OutputIso -Index $Index `
        -DryRun -KeepWork:$KeepWork -DownloadOscdimg:$DownloadOscdimg -Resume:$Resume -HardwareSpec $HardwareSpec -AcceptRisk:$AcceptRisk `
        -DeltaFromManifest $DeltaFromManifest -Strict:$Strict -Force:$Force -NoCheckpoints:$NoCheckpoints `
        -SigningCertThumbprint $SigningCertThumbprint -MinFreeDiskSpaceGB $MinFreeDiskSpaceGB
    return
}

if ($Command -eq 'build') {
    Invoke-WibBuild -IsoPath $IsoPath -IsoDrive $IsoDrive -ExpectedIsoSha256 $ExpectedIsoSha256 -SkipIsoHash:$SkipIsoHash `
        -ProfilePath $profilePath -ToolRoot $toolRoot -WorkDir $WorkDir -OutputIso $OutputIso -Index $Index `
        -DryRun:$DryRun -KeepWork:$KeepWork -DownloadOscdimg:$DownloadOscdimg -Resume:$Resume -HardwareSpec $HardwareSpec -AcceptRisk:$AcceptRisk `
        -DeltaFromManifest $DeltaFromManifest -Strict:$Strict -Force:$Force -NoCheckpoints:$NoCheckpoints `
        -SigningCertThumbprint $SigningCertThumbprint -MinFreeDiskSpaceGB $MinFreeDiskSpaceGB
    return
}

if ($Command -eq 'verify') {
    Write-Host 'General verify pass on mounted image...' -ForegroundColor Cyan
    if (-not $WorkDir) { $WorkDir = Join-Path $toolRoot 'work' }
    $WorkDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($WorkDir)
    $mountDir = Join-Path $WorkDir 'mount'
    if (-not (Test-Path -LiteralPath $mountDir)) {
        throw "Mount directory not found at $mountDir"
    }
    New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
    $verifyRunId = [System.Guid]::NewGuid().ToString('N').Substring(0, 8).ToUpper()
    $script:WibHivePrefix = "wib_verify_${verifyRunId}_"
    $verifyLock = Lock-WibWorkspace -WorkDir $WorkDir -RunId $verifyRunId
    $p = Import-WibProfile -Path $profilePath
    $ctx = @{ MountDir = $mountDir; Image = 'install'; Journal = (New-Object System.Collections.ArrayList); Extras = @{}; ToolRoot = $toolRoot }
    try {
        Mount-WibHives -MountDir $mountDir
        $findings = Invoke-WibGeneralVerify -Ctx $ctx -BuildProfile $p
        $findings | ForEach-Object {
            Write-Host ("[{0}] {1}: {2}" -f $_.Status.ToUpper(), $_.Item, $_.Detail)
        }
    } finally {
        $teardownFailed = $false
        $teardownError = $null
        try {
            Dismount-WibHives -ThrowOnFailure | Out-Null
        } catch {
            $teardownFailed = $true
            $teardownError = $_
        }
        $script:WibHivePrefix = 'wib_'
        if ($verifyLock) {
            Unlock-WibWorkspace -LockStream $verifyLock -WorkDir $WorkDir
        }
        if ($teardownFailed) {
            throw $teardownError
        }
    }
    return
}
