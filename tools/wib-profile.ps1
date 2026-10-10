#Requires -Version 5.1
<#
.SYNOPSIS
    WIB Profile Manager & Community Catalog Tool.
    Inspects, validates, exports, and imports WIB customization profiles.
    PowerShell 5.1+ compatible (zero external dependencies).

.DESCRIPTION
    Manages WIB profiles (balanced, lean, adaptive, hardening, custom-risk),
    computes canonical hashes, checks parent inheritance chains, validates
    schemas against module registries, and exports standalone flattened profiles.

.PARAMETER Command
    The action to execute: 'list', 'info', 'validate', 'export', or 'import'.
.PARAMETER ProfileName
    Target profile name (e.g., 'balanced', 'hardening', 'adaptive') or JSON file path.
.PARAMETER ProfilesDir
    Directory containing WIB profiles. Defaults to .\profiles relative to repo.
.PARAMETER OutFile
    Destination path for the 'export' command.
.PARAMETER Source
    Source JSON path or directory for the 'import' command.
.PARAMETER AcceptRisk
    Permits validating profiles containing high-risk security opt-ins.
#>

[CmdletBinding()]
param(
    [ValidateSet('list', 'info', 'validate', 'export', 'import')]
    [string]$Command = 'list',

    [string]$ProfileName = 'balanced',

    [string]$ProfilesDir = '',

    [string]$OutFile = '',

    [string]$Source = '',

    [switch]$AcceptRisk,

    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# Locate repo root and libraries
$root = Split-Path -Parent $PSScriptRoot
$libDir = Join-Path $root 'lib'
if (-not (Test-Path -LiteralPath $libDir)) {
    $libDir = Join-Path $PSScriptRoot 'lib'
}

$coreLib = Join-Path $libDir 'Core.ps1'
if (Test-Path -LiteralPath $coreLib) {
    . $coreLib
} else {
    throw "Core library not found: $coreLib"
}

# Load modules for schema validation
$modDir = Join-Path $root 'modules'
if (-not (Test-Path -LiteralPath $modDir)) {
    $modDir = Join-Path $PSScriptRoot 'modules'
}
if (Test-Path -LiteralPath $modDir) {
    Get-ChildItem -LiteralPath $modDir -Filter '*.ps1' | Sort-Object Name | ForEach-Object { . $_.FullName }
}

# Resolve profiles directory
if (-not $ProfilesDir) {
    $ProfilesDir = Join-Path $root 'profiles'
    if (-not (Test-Path -LiteralPath $ProfilesDir)) {
        $ProfilesDir = Join-Path $PSScriptRoot 'profiles'
    }
}

function Resolve-ProfilePath {
    param([string]$Name, [string]$Dir)
    if (Test-Path -LiteralPath $Name -PathType Leaf) {
        return (Resolve-Path -LiteralPath $Name).Path
    }
    $candidate = Join-Path $Dir "$Name.json"
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        return (Resolve-Path -LiteralPath $candidate).Path
    }
    throw "Profile not found: $Name (searched $candidate)"
}

switch ($Command) {
    'list' {
        Write-Host "================ WIB PROFILE CATALOG ================" -ForegroundColor Cyan
        if (-not (Test-Path -LiteralPath $ProfilesDir)) {
            throw "Profiles directory not found: $ProfilesDir"
        }

        $files = Get-ChildItem -LiteralPath $ProfilesDir -Filter '*.json' | Sort-Object Name
        '{0,-15} {1,-12} {2,-8} {3,-10} {4}' -f 'PROFILE', 'EXTENDS', 'MODULES', 'MAX RISK', 'DESCRIPTION'
        '--------------------------------------------------------------------------------------------------'

        $results = New-Object System.Collections.ArrayList
        foreach ($f in $files) {
            try {
                $prof = Import-WibProfile $f.FullName
                $parent = if ($prof.ContainsKey('extends') -and $prof['extends']) { $prof['extends'] } else { '-' }
                $modCount = if ($prof.ContainsKey('modules') -and $prof['modules']) { $prof['modules'].Count } else { 0 }
                $desc = if ($prof.ContainsKey('description') -and $prof['description']) { $prof['description'] } else { '' }
                
                # Assess max risk level of enabled modules
                $maxRisk = 'low'
                if ($prof.ContainsKey('modules')) {
                    foreach ($mKey in $prof['modules'].Keys) {
                        $mCfg = $prof['modules'][$mKey]
                        if ((Test-WibModuleEnabled $mCfg) -and $script:WibModules.Contains($mKey)) {
                            $mRisk = $script:WibModules[$mKey].Risk
                            if ($mRisk -eq 'high') { $maxRisk = 'high' }
                            elseif ($mRisk -eq 'medium' -and $maxRisk -ne 'high') { $maxRisk = 'medium' }
                        }
                    }
                }

                $shortDesc = if ($desc.Length -gt 45) { $desc.Substring(0, 42) + '...' } else { $desc }
                '{0,-15} {1,-12} {2,-8} {3,-10} {4}' -f $prof.profile, $parent, $modCount, $maxRisk, $shortDesc

                [void]$results.Add([PSCustomObject]@{
                    Profile     = $prof.profile
                    Extends     = $parent
                    Modules     = $modCount
                    MaxRisk     = $maxRisk
                    Description = $desc
                    Path        = $f.FullName
                })
            } catch {
                Write-Warning "Failed to parse $($f.Name): $_"
            }
        }
        return @($results)
    }

    'info' {
        $pPath = Resolve-ProfilePath -Name $ProfileName -Dir $ProfilesDir
        $prof = Import-WibProfile $pPath
        $hash = Get-WibProfileCanonicalHash $prof
        $chain = if ($prof.ContainsKey('parentChain') -and $prof['parentChain']) { $prof['parentChain'] -join ' -> ' } else { 'none' }

        Write-Host ("`n=== WIB Profile: {0} ===" -f $prof.profile) -ForegroundColor Green
        Write-Host ("Path          : {0}" -f $pPath)
        $descStr = 'No description provided.'
        if ($prof.ContainsKey('description') -and $prof['description']) { $descStr = $prof['description'] }
        Write-Host ("Description   : {0}" -f $descStr)
        Write-Host ("Parent Chain  : {0}" -f $chain)
        Write-Host ("Canonical Hash: {0}" -f $hash) -ForegroundColor Gray

        Write-Host "`nConfigured Modules:" -ForegroundColor Cyan
        '{0,-26} {1,-8} {2,-6} {3,-14} {4}' -f 'MODULE', 'STATUS', 'RISK', 'REVERSIBILITY', 'DESCRIPTION'
        '------------------------------------------------------------------------------------------------'

        $enabledCount = 0
        foreach ($mId in ($prof['modules'].Keys | Sort-Object)) {
            $mCfg = $prof['modules'][$mId]
            $enabled = Test-WibModuleEnabled $mCfg
            if ($enabled) { $enabledCount++ }

            $risk = 'unknown'
            $rev = 'unknown'
            $desc = ''
            if ($script:WibModules.Contains($mId)) {
                $mod = $script:WibModules[$mId]
                $risk = $mod.Risk
                $rev = $mod.Reversibility
                $desc = $mod.Description
            }
            $shortDesc = if ($desc.Length -gt 40) { $desc.Substring(0, 37) + '...' } else { $desc }
            $statusStr = if ($enabled) { 'enabled' } else { 'off' }

            '{0,-26} {1,-8} {2,-6} {3,-14} {4}' -f $mId, $statusStr, $risk, $rev, $shortDesc
        }
        Write-Host ("`nTotal Modules: {0} configured, {1} active." -f $prof['modules'].Count, $enabledCount) -ForegroundColor Green
        return $prof
    }

    'validate' {
        $pPath = Resolve-ProfilePath -Name $ProfileName -Dir $ProfilesDir
        Write-Host "Validating profile: $pPath" -ForegroundColor Cyan
        $prof = Import-WibProfile $pPath
        Test-WibProfile -BuildProfile $prof -AcceptRisk:$AcceptRisk
        $hash = Get-WibProfileCanonicalHash $prof

        Write-Host "VALIDATION PASS: Profile '$($prof.profile)' conforms to schema and safety rules." -ForegroundColor Green
        Write-Host "Canonical SHA-256: $hash" -ForegroundColor Gray
        return [PSCustomObject]@{
            Profile       = $prof.profile
            Valid         = $true
            CanonicalHash = $hash
        }
    }

    'export' {
        if (-not $OutFile) {
            throw "Parameter -OutFile is required for 'export' command."
        }
        $pPath = Resolve-ProfilePath -Name $ProfileName -Dir $ProfilesDir
        Write-Host "Resolving and exporting profile '$ProfileName'..." -ForegroundColor Cyan
        $prof = Import-WibProfile $pPath
        Test-WibProfile -BuildProfile $prof -AcceptRisk:$AcceptRisk

        if ($prof.ContainsKey('extends')) {
            [void]$prof.Remove('extends')
        }

        $outDir = Split-Path -Parent $OutFile
        if ($outDir -and -not (Test-Path -LiteralPath $outDir)) {
            New-Item -ItemType Directory -Path $outDir -Force | Out-Null
        }

        # Export fully resolved profile as formatted JSON
        $prof | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutFile -Encoding UTF8
        Write-Host "Exported resolved profile to: $OutFile" -ForegroundColor Green
        return (Resolve-Path -LiteralPath $OutFile).Path
    }

    'import' {
        if (-not $Source -or -not (Test-Path -LiteralPath $Source -PathType Leaf)) {
            throw "Source file not found: $Source"
        }
        Write-Host "Importing profile from $Source..." -ForegroundColor Cyan
        $importedProf = Import-WibProfile $Source
        Test-WibProfile -BuildProfile $importedProf -AcceptRisk:$AcceptRisk

        $profName = [string]$importedProf.profile
        if (-not $profName -or $profName -notmatch '^[A-Za-z0-9_-]+$') {
            throw "Invalid profile name '$profName'. Must contain only alphanumeric characters, underscores, and hyphens (^[A-Za-z0-9_-]+$)."
        }

        $builtInProfiles = if ($script:WibBuiltInProfiles) { @($script:WibBuiltInProfiles) } else { @('balanced', 'lean', 'adaptive', 'hardening') }
        if ($builtInProfiles -contains $profName.ToLower() -and -not $Force) {
            throw "Profile '$profName' is a built-in profile. Specify -Force to overwrite built-in profiles."
        }

        $destFile = Join-Path $ProfilesDir "$profName.json"
        Copy-Item -LiteralPath $Source -Destination $destFile -Force
        Write-Host "Successfully imported profile '$profName' into $destFile" -ForegroundColor Green
        return $destFile
    }
}
