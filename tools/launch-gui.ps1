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
$scriptPath = Join-Path $PSScriptRoot 'WibBuilderGui.ps1'

# Check if current session is elevated
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

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
