#Requires -Version 5.1
<#
.SYNOPSIS
    Convenience launcher for WIB Builder Studio GUI.
#>
[CmdletBinding()]
param(
    [switch]$NoElevate
)

$scriptPath = Join-Path $PSScriptRoot 'WibBuilderGui.ps1'
$argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $scriptPath)
if ($NoElevate) {
    $argList += '-NoElevate'
}

Start-Process -FilePath 'powershell.exe' -ArgumentList $argList
