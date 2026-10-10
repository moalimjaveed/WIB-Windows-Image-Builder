#Requires -Version 5.1
<#
.SYNOPSIS
    Forwarding proxy for build.ps1 from tools\WibStudio to repository root.
#>
[CmdletBinding()]
param()

$rootBuildScript = Join-Path $PSScriptRoot '..\..\build.ps1'
if (Test-Path -LiteralPath $rootBuildScript) {
    & $rootBuildScript @args
} else {
    Write-Error "Could not locate root build.ps1 relative to WibStudio tools directory."
}
