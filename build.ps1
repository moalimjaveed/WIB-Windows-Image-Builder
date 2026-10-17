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
    [ValidateSet('max', 'fast', 'recovery', 'none')][string]$Compression,
    [string]$SigningCertThumbprint,
    [int]$MinFreeDiskSpaceGB = 25,
    [string]$HardwareSpec,
    [switch]$AcceptRisk,
    [string]$DeltaFromManifest,
    [string]$JournalPath,
    [string]$RegistryRoot,
    [switch]$Gui,
    [switch]$NoElevate
)

$ErrorActionPreference = 'Stop'
$toolRoot = $PSScriptRoot

if ($ExpectedIsoSha256) {
    $ExpectedIsoSha256 = $ExpectedIsoSha256.Trim()
}

if ($Gui) {
    $studioExe = Join-Path $toolRoot 'tools\WibStudio\WibStudio.exe'
    if (Test-Path -LiteralPath $studioExe) {
        $launchParams = @{
            FilePath = $studioExe
            WorkingDirectory = $toolRoot
        }
        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if (-not $isAdmin -and -not $NoElevate) {
            $launchParams['Verb'] = 'RunAs'
        }
        Start-Process @launchParams
        return
    }

    $builderGui = Join-Path $toolRoot 'tools\WibBuilderGui.ps1'
    if (Test-Path -LiteralPath $builderGui) {
        $guiSplat = @{}
        if ($NoElevate) { $guiSplat['NoElevate'] = $true }
        & $builderGui @guiSplat
        return
    }
}

if ($PSBoundParameters.Count -eq 0) {
    Write-Host ""
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host "  WIB: Windows Image Builder (v0.2.29)" -ForegroundColor White
    Write-Host "  Hardware-adaptive, verifiable Windows 11 offline servicing engine" -ForegroundColor Gray
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host ""
    $isAdminSession = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($isAdminSession) {
        Write-Host "  Session:    " -NoNewline; Write-Host "Elevated (Administrator Servicing Active)" -ForegroundColor Green
    } else {
        Write-Host "  Session:    " -NoNewline; Write-Host "Standard User (Preview & Validation Mode)" -ForegroundColor Yellow
    }
    
    $profiles = @()
    $profDir = Join-Path $toolRoot 'profiles'
    if (Test-Path -LiteralPath $profDir) {
        $profiles = Get-ChildItem -LiteralPath $profDir -Filter '*.json' | ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) }
    }
    if ($profiles.Count -gt 0) {
        Write-Host "  Profiles:   " -NoNewline; Write-Host ($profiles -join ', ') -ForegroundColor White
    }
    Write-Host ""
    Write-Host "  QUICK START / CLI USAGE:" -ForegroundColor Cyan
    Write-Host "  1. Launch Desktop GUI:     " -NoNewline; Write-Host ".\build.ps1 -Gui" -ForegroundColor Yellow; Write-Host "                             (or .\tools\launch-gui.ps1 -NoElevate for Preview)" -ForegroundColor DarkGray
    Write-Host "  2. Validate a Profile:     " -NoNewline; Write-Host ".\build.ps1 -Command validate -ProfileName balanced" -ForegroundColor Yellow
    Write-Host "  3. List Registered Modules:" -NoNewline; Write-Host ".\build.ps1 -Command list" -ForegroundColor Yellow
    Write-Host "  4. Preview Execution Plan: " -NoNewline; Write-Host ".\build.ps1 -IsoPath `"D:\Win11.iso`" -Command plan" -ForegroundColor Yellow
    Write-Host "  5. Execute Full Build:     " -NoNewline; Write-Host ".\build.ps1 -IsoPath `"D:\Win11.iso`" -ProfileName balanced" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "--------------------------------------------------------------------------------" -ForegroundColor DarkGray

    if (-not [Console]::IsInputRedirected) {
        Write-Host "  Options: [G] Launch WIB Studio GUI | [V] Validate Profile | [L] List Modules | [Enter] Exit" -ForegroundColor White
        $choice = Read-Host "  Select an option"
        if ($choice -match '^[gG]') {
            $builderGui = Join-Path $toolRoot 'tools\WibBuilderGui.ps1'
            if (Test-Path -LiteralPath $builderGui) {
                $guiSplat = @{}
                if (-not $isAdminSession) {
                    Write-Host "  Launching GUI in Preview Mode (No elevation prompt)..." -ForegroundColor Cyan
                    $guiSplat['NoElevate'] = $true
                }
                & $builderGui @guiSplat
            }
            return
        } elseif ($choice -match '^[vV]') {
            & $PSCommandPath -Command validate -ProfileName balanced
            return
        } elseif ($choice -match '^[lL]') {
            & $PSCommandPath -Command list
            return
        }
    }
    return
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

if ($HardwareSpec) {
    if (-not (Test-Path -LiteralPath $HardwareSpec)) {
        $candidateHw = Join-Path $toolRoot "specs\$HardwareSpec.json"
        if (Test-Path -LiteralPath $candidateHw) {
            $HardwareSpec = (Get-Item -LiteralPath $candidateHw).FullName
        } else {
            $candidateHw2 = Join-Path $toolRoot "specs\$HardwareSpec"
            if (Test-Path -LiteralPath $candidateHw2) {
                $HardwareSpec = (Get-Item -LiteralPath $candidateHw2).FullName
            }
        }
    }
}

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
    Write-Host ""
    Write-Host "[WIB ERROR] Command '$Command' requires administrator privileges." -ForegroundColor Red
    Write-Host "Start Windows PowerShell using 'Run as Administrator', or run in preview mode:" -ForegroundColor Yellow
    Write-Host "  - To launch GUI in Preview Mode: .\build.ps1 -Gui" -ForegroundColor White
    Write-Host "  - To validate profiles:          .\build.ps1 -Command validate -ProfileName $ProfileName" -ForegroundColor White
    Write-Host "  - To list all modules:           .\build.ps1 -Command list" -ForegroundColor White
    Write-Host ""
    throw "Command '$Command' requires administrator privileges. Start Windows PowerShell by using the Run as Administrator option."
}

if ($Command -eq 'plan') {
    Invoke-WibBuild -IsoPath $IsoPath -IsoDrive $IsoDrive -ExpectedIsoSha256 $ExpectedIsoSha256 -SkipIsoHash:$SkipIsoHash `
        -ProfilePath $profilePath -ToolRoot $toolRoot -WorkDir $WorkDir -OutputIso $OutputIso -Index $Index `
        -DryRun -KeepWork:$KeepWork -DownloadOscdimg:$DownloadOscdimg -Resume:$Resume -HardwareSpec $HardwareSpec -AcceptRisk:$AcceptRisk `
        -DeltaFromManifest $DeltaFromManifest -Strict:$Strict -Force:$Force -NoCheckpoints:$NoCheckpoints -Compression $Compression `
        -SigningCertThumbprint $SigningCertThumbprint -MinFreeDiskSpaceGB $MinFreeDiskSpaceGB
    return
}

if ($Command -eq 'build') {
    Invoke-WibBuild -IsoPath $IsoPath -IsoDrive $IsoDrive -ExpectedIsoSha256 $ExpectedIsoSha256 -SkipIsoHash:$SkipIsoHash `
        -ProfilePath $profilePath -ToolRoot $toolRoot -WorkDir $WorkDir -OutputIso $OutputIso -Index $Index `
        -DryRun:$DryRun -KeepWork:$KeepWork -DownloadOscdimg:$DownloadOscdimg -Resume:$Resume -HardwareSpec $HardwareSpec -AcceptRisk:$AcceptRisk `
        -DeltaFromManifest $DeltaFromManifest -Strict:$Strict -Force:$Force -NoCheckpoints:$NoCheckpoints -Compression $Compression `
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
