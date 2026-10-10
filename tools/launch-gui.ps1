#Requires -Version 5.1
<#
.SYNOPSIS
    Convenience launcher for WIB Builder Studio GUI.
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [switch]$NoElevate,
    [string]$ScreenshotPath,
    [switch]$CloseAfterScreenshot,
    [int]$InitialTab = 0
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$studioExe = Join-Path $PSScriptRoot 'WibStudio\WibStudio.exe'
$scriptPath = Join-Path $PSScriptRoot 'WibBuilderGui.ps1'

# Check if current session is elevated
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# If modern WPF WibStudio is present and this isn't an automated script-screenshot request, launch WibStudio
if ((Test-Path -LiteralPath $studioExe) -and -not $ScreenshotPath) {
    $procParams = @{
        FilePath = $studioExe
        WorkingDirectory = $repoRoot
    }
    if (-not $isAdmin -and -not $NoElevate) {
        $procParams['Verb'] = 'RunAs'
    }
    Start-Process @procParams
    return
}

# Fallback to PowerShell WinForms engine
if (-not $isAdmin -and -not $NoElevate) {
    # Launch elevated process with properly quoted file path for paths with spaces
    $elevateArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$scriptPath`"")
    if ($PSBoundParameters.ContainsKey('InitialTab') -and $InitialTab -gt 0) {
        $elevateArgs += @('-InitialTab', [string]$InitialTab)
    }
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $elevateArgs
} else {
    # If already elevated or running in preview mode (-NoElevate), invoke directly
    $splat = @{}
    if ($NoElevate) { $splat['NoElevate'] = $true }
    if ($ScreenshotPath) { $splat['ScreenshotPath'] = $ScreenshotPath }
    if ($CloseAfterScreenshot) { $splat['CloseAfterScreenshot'] = $true }
    if ($PSBoundParameters.ContainsKey('InitialTab')) { $splat['InitialTab'] = $InitialTab }
    
    & $scriptPath @splat
}
