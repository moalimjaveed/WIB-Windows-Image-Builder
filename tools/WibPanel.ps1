#Requires -Version 5.1
<#
.SYNOPSIS
    WIB Post-Install Control Panel.
    Inspects live registry state against Windows\WIB\journal.json,
    detects policy drift from Windows Updates, and safely rolls back tweaks.
    PowerShell 5.1+ compatible (WinForms, zero external dependencies).
#>

[CmdletBinding()]
param(
    [string]$JournalPath = 'C:\Windows\WIB\journal.json',
    [switch]$NonInteractive,
    [switch]$CheckDriftOnly,
    [switch]$RestoreAll,
    [switch]$Repatch,
    [switch]$DryRun,
    [string]$LogFile = '',
    [string]$RegistryRoot = ''
)

$ErrorActionPreference = 'Stop'
$script:RegistryRoot = $RegistryRoot
$journalDir = Split-Path -Parent $JournalPath
if (-not $journalDir) { $journalDir = '.' }
$script:RestoredPath = Join-Path $journalDir 'restored.json'

if (-not (Get-Command ConvertTo-WibHashtable -ErrorAction SilentlyContinue)) {
    function ConvertTo-WibHashtable {
        param($InputObject)
        if ($null -eq $InputObject) { return $null }
        if ($InputObject -is [System.Collections.IDictionary]) {
            $h = @{}
            foreach ($k in $InputObject.Keys) { $h[$k] = ConvertTo-WibHashtable $InputObject[$k] }
            return $h
        }
        if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
            $h = @{}
            foreach ($p in $InputObject.PSObject.Properties) { $h[$p.Name] = ConvertTo-WibHashtable $p.Value }
            return $h
        }
        if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
            $l = @()
            foreach ($i in $InputObject) { $l += , (ConvertTo-WibHashtable $i) }
            return , $l
        }
        return $InputObject
    }
}

function Convert-WibExportedReg {
    param([string]$Text, [string]$Hive)
    $map = @{
        SOFTWARE = 'HKEY_LOCAL_MACHINE\SOFTWARE'
        SYSTEM   = 'HKEY_LOCAL_MACHINE\SYSTEM'
        DEFAULT  = 'HKEY_USERS\.DEFAULT'
        NTUSER   = 'HKEY_CURRENT_USER'
    }
    $h = $Hive.ToUpper()
    if (-not $map.ContainsKey($h)) { return $null }
    return ($Text -replace "HKEY_LOCAL_MACHINE\\wib_([a-zA-Z0-9]+_)?$h", $map[$h])
}

function Get-WibEffectiveEntries {
    param($Entries)
    $map = [ordered]@{}
    foreach ($e in $Entries) {
        $key = "$($e.Hive)|$($e.Path)|$($e.Name)|$($e.Action)".ToLower()
        if (-not $map.Contains($key)) {
            $copy = @{}
            foreach ($k in $e.Keys) { $copy[$k] = $e[$k] }
            $map[$key] = $copy
        } else {
            # Retain original OldValue/OldKind/Existed from first mutation; update NewValue/NewKind from last mutation
            $first = $map[$key]
            $first['NewValue']  = $e['NewValue']
            $first['NewKind']   = $e['NewKind']
            $first['Timestamp'] = $e['Timestamp']
            if ($e.Keys -contains 'ScopeNote') { $first['ScopeNote'] = $e['ScopeNote'] }
        }
    }
    return @($map.Values)
}

function Get-WibLiveRegistryPath {
    param([string]$Hive, [string]$Path)
    if ($script:RegistryRoot) {
        return "$script:RegistryRoot\$Path"
    }
    switch ($Hive.ToUpper()) {
        'SOFTWARE' { return "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\$Path" }
        'SYSTEM'   { return "Registry::HKEY_LOCAL_MACHINE\SYSTEM\$Path" }
        'DEFAULT'  { return "Registry::HKEY_USERS\.DEFAULT\$Path" }
        'NTUSER'   { return "Registry::HKEY_CURRENT_USER\$Path" }
        default    { return "Registry::HKEY_LOCAL_MACHINE\$Hive\$Path" }
    }
}

function Get-WibEntryKey {
    param($Entry)
    return "$($Entry.Hive)|$($Entry.Path)|$($Entry.Name)".ToLower()
}

function Get-WibRestoredSet {
    if (Test-Path -LiteralPath $script:RestoredPath) {
        try {
            $raw = Get-Content -LiteralPath $script:RestoredPath -Raw -Encoding UTF8
            if ($raw -and $raw.Trim().Length -gt 2) {
                $list = $raw | ConvertFrom-Json
                $h = @{}
                foreach ($item in @($list)) {
                    $key = [string]$item
                    $h[$key.ToLower()] = $true
                }
                return $h
            }
        } catch { Write-Verbose $_.Exception.Message }
    }
    return @{}
}

function Add-WibRestoredMarker {
    param($Entry)
    $key = Get-WibEntryKey $Entry
    $set = Get-WibRestoredSet
    $set[$key] = $true
    try {
        $dir = Split-Path -Parent $script:RestoredPath
        if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        @($set.Keys) | ConvertTo-Json | Set-Content -LiteralPath $script:RestoredPath -Encoding UTF8
    } catch { Write-Verbose $_.Exception.Message }
}

function Remove-WibRestoredMarker {
    param($Entry)
    $key = Get-WibEntryKey $Entry
    $set = Get-WibRestoredSet
    if ($set.ContainsKey($key)) {
        $null = $set.Remove($key)
        try {
            @($set.Keys) | ConvertTo-Json | Set-Content -LiteralPath $script:RestoredPath -Encoding UTF8
        } catch { Write-Verbose $_.Exception.Message }
    }
}

function Test-WibRegistryValueMatch {
    param($Val1, $Val2, [string]$Kind = '')
    if ($null -eq $Val1 -and $null -eq $Val2) { return $true }
    if ($null -eq $Val1 -or $null -eq $Val2) { return $false }

    if ($Kind -eq 'Binary' -or ($Val1 -is [byte[]]) -or ($Val2 -is [byte[]])) {
        $b1 = if ($Val1 -is [byte[]]) { $Val1 } elseif ($Val1 -is [System.Collections.IEnumerable] -and -not ($Val1 -is [string])) { [byte[]]@($Val1) } else { $null }
        $b2 = if ($Val2 -is [byte[]]) { $Val2 } elseif ($Val2 -is [System.Collections.IEnumerable] -and -not ($Val2 -is [string])) { [byte[]]@($Val2) } else { $null }
        if ($null -eq $b1 -or $null -eq $b2) { return $false }
        if ($b1.Length -ne $b2.Length) { return $false }
        return ([System.BitConverter]::ToString($b1) -eq [System.BitConverter]::ToString($b2))
    }

    if ($Kind -eq 'DWord' -or ($Val1 -is [int32] -or $Val1 -is [uint32])) {
        try {
            $normalizeU32 = {
                param($val)
                if ($val -is [uint32]) { return [uint32]$val }
                if ($val -is [string] -and $val.StartsWith('0x', [System.StringComparison]::OrdinalIgnoreCase)) {
                    return [Convert]::ToUInt32($val, 16)
                }
                $masked = ([int64]$val) -band 0x00000000FFFFFFFFL
                return [uint32]$masked
            }
            $u1 = & $normalizeU32 $Val1
            $u2 = & $normalizeU32 $Val2
            return ($u1 -eq $u2)
        } catch {
            return ([string]$Val1 -eq [string]$Val2)
        }
    }

    if ($Kind -eq 'QWord' -or ($Val1 -is [int64] -or $Val1 -is [uint64])) {
        try {
            $normalizeU64 = {
                param($val)
                if ($val -is [uint64]) { return [uint64]$val }
                if ($val -is [string] -and $val.StartsWith('0x', [System.StringComparison]::OrdinalIgnoreCase)) {
                    return [Convert]::ToUInt64($val, 16)
                }
                if ($val -is [string] -and $val -match '^-') {
                    return [BitConverter]::ToUInt64([BitConverter]::GetBytes([int64]$val), 0)
                }
                if ($val -is [int64] -or $val -is [int32] -or $val -is [int]) {
                    return [BitConverter]::ToUInt64([BitConverter]::GetBytes([int64]$val), 0)
                }
                return [uint64]$val
            }
            $u1 = & $normalizeU64 $Val1
            $u2 = & $normalizeU64 $Val2
            return ($u1 -eq $u2)
        } catch {
            return ([string]$Val1 -eq [string]$Val2)
        }
    }

    if ($Kind -eq 'MultiString' -or ($Val1 -is [array]) -or ($Val2 -is [array])) {
        $a1 = @($Val1) | ForEach-Object { [string]$_ }
        $a2 = @($Val2) | ForEach-Object { [string]$_ }
        if ($a1.Count -ne $a2.Count) { return $false }
        for ($i = 0; $i -lt $a1.Count; $i++) {
            if ($a1[$i] -ne $a2[$i]) { return $false }
        }
        return $true
    }

    return ([string]$Val1 -eq [string]$Val2)
}

function Test-WibTweakDrift {
    param($Entry)
    if ($Entry.TargetScope -eq 'default-user-only') {
        return @{
            Status    = 'Template only (not checked on live system)'
            LiveValue = $null
            LiveKind  = $null
            Drifted   = $false
        }
    }

    $regPath = Get-WibLiveRegistryPath -Hive $Entry.Hive -Path $Entry.Path
    $result = @{
        Status    = 'Unknown'
        LiveValue = $null
        LiveKind  = $null
        Drifted   = $false
    }

    $restoredSet = Get-WibRestoredSet
    $entryKey = Get-WibEntryKey $Entry
    $isRestored = $restoredSet.ContainsKey($entryKey)

    if ($Entry.Action -eq 'DeleteKey') {
        $exists = Test-Path -LiteralPath $regPath
        if ($exists) {
            if ($isRestored) {
                $result.Status  = 'Restored by user'
                $result.Drifted = $false
            } else {
                $result.Status  = 'Drifted (Key Recreated)'
                $result.Drifted = $true
            }
        } else {
            $result.Status  = 'Intact (Key Absent)'
            $result.Drifted = $false
        }
        return $result
    }

    if ($Entry.Action -eq 'DeleteValue') {
        if (-not (Test-Path -LiteralPath $regPath)) {
            $result.Status  = 'Intact (Key Absent)'
            $result.Drifted = $false
            return $result
        }
        $key = Get-Item -LiteralPath $regPath
        try {
            $hasVal = ($Entry.Name -and ($key.GetValueNames() -contains $Entry.Name))
            if ($hasVal) {
                if ($isRestored) {
                    $result.Status  = 'Restored by user'
                    $result.Drifted = $false
                } else {
                    $val = $key.GetValue($Entry.Name)
                    $result.LiveValue = $val
                    $result.LiveKind  = [string]$key.GetValueKind($Entry.Name)
                    $result.Status  = 'Drifted (Value Recreated)'
                    $result.Drifted = $true
                }
            } else {
                $result.Status  = 'Intact (Value Absent)'
                $result.Drifted = $false
            }
        } finally {
            $key.Close()
        }
        return $result
    }

    if (-not (Test-Path -LiteralPath $regPath)) {
        if ($isRestored) {
            $result.Status  = 'Restored by user'
            $result.Drifted = $false
        } elseif ($Entry.Existed) {
            $result.Status  = 'Drifted (Key Deleted)'
            $result.Drifted = $true
        } else {
            $result.Status  = 'Drifted (Missing)'
            $result.Drifted = $true
        }
        return $result
    }

    $key = Get-Item -LiteralPath $regPath
    try {
        if ($Entry.Name -and ($key.GetValueNames() -contains $Entry.Name)) {
            $val = $key.GetValue($Entry.Name)
            $kind = [string]$key.GetValueKind($Entry.Name)
            $result.LiveValue = $val
            $result.LiveKind  = $kind

            if (Test-WibRegistryValueMatch $val $Entry.NewValue $kind) {
                $result.Status  = 'Intact (Applied)'
                $result.Drifted = $false
            } elseif ($isRestored) {
                $result.Status  = 'Restored by user'
                $result.Drifted = $false
            } elseif ($Entry.Existed -and (Test-WibRegistryValueMatch $val $Entry.OldValue $kind)) {
                $result.Status  = 'Drifted (Reverted to Original)'
                $result.Drifted = $true
            } else {
                $displayVal = if ($val -is [byte[]]) { [System.BitConverter]::ToString($val) } else { [string]$val }
                $result.Status  = "Drifted (Value = $displayVal)"
                $result.Drifted = $true
            }
        } else {
            if ($isRestored) {
                $result.Status  = 'Restored by user'
                $result.Drifted = $false
            } elseif ($Entry.Existed) {
                $result.Status  = 'Drifted (Value Missing)'
                $result.Drifted = $true
            } else {
                $result.Status  = 'Drifted (Missing)'
                $result.Drifted = $true
            }
        }
    } finally {
        $key.Close()
    }

    return $result
}

function New-WibPanelTempFile {
    param([string]$Extension = '.reg')
    $tempPath = [System.IO.Path]::GetTempPath()
    $fileName = 'wib-panel-' + [System.Guid]::NewGuid().ToString('N') + $Extension
    $fullPath = Join-Path $tempPath $fileName
    [System.IO.File]::WriteAllBytes($fullPath, [byte[]]@())
    try {
        $acl = Get-Acl -LiteralPath $fullPath
        $acl.SetAccessRuleProtection($true, $false)
        $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $adminSid = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid, $null)
        $systemSid = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::LocalSystemSid, $null)
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($currentUser, 'FullControl', 'Allow')))
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($adminSid, 'FullControl', 'Allow')))
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($systemSid, 'FullControl', 'Allow')))
        Set-Acl -LiteralPath $fullPath -AclObject $acl
    } catch {
        if (Test-Path -LiteralPath $fullPath) {
            Remove-Item -LiteralPath $fullPath -Force -ErrorAction SilentlyContinue
        }
        throw "Failed to enforce secure ACL permissions on temporary file '$fullPath': $($_.Exception.Message)"
    }
    return $fullPath
}

function Restore-WibTweakEntry {
    param($Entry)
    if ($Entry.ContainsKey('Restorable') -and -not [bool]$Entry.Restorable) {
        Write-Verbose "Skipping restore of non-restorable tweak: $($Entry.Path)"
        return $false
    }
    if ($Entry.TargetScope -eq 'default-user-only') {
        Write-Verbose "Skipping restore of default-user template tweak: $($Entry.Path)"
        return $false
    }

    $regPath = Get-WibLiveRegistryPath -Hive $Entry.Hive -Path $Entry.Path

    if ($Entry.Action -eq 'DeleteKey') {
        if ($Entry.ExportedReg) {
            $text = Convert-WibExportedReg -Text ([string]$Entry.ExportedReg) -Hive $Entry.Hive
            if (-not $text) { return $false }
            $tmpReg = New-WibPanelTempFile -Extension '.reg'
            try {
                [System.IO.File]::WriteAllText($tmpReg, $text, [System.Text.Encoding]::Unicode)
                & reg.exe import $tmpReg 2>&1 | Out-Null
                $ok = ($LASTEXITCODE -eq 0)
                if ($ok) { Add-WibRestoredMarker -Entry $Entry }
                return $ok
            } finally {
                Remove-Item -LiteralPath $tmpReg -Force -ErrorAction SilentlyContinue
            }
        }
        return $false
    }

    if ($Entry.Existed) {
        if (-not (Test-Path -LiteralPath $regPath)) {
            $null = New-Item -Path $regPath -Force
        }
        $val = $Entry.OldValue
        if ($Entry.OldKind -eq 'DWord') { $val = [int]$val }
        elseif ($Entry.OldKind -eq 'QWord') { $val = [long]$val }
        elseif ($Entry.OldKind -eq 'Binary' -and $val -isnot [byte[]]) {
            $val = [byte[]]$val
        }
        New-ItemProperty -LiteralPath $regPath -Name $Entry.Name -Value $val -PropertyType $Entry.OldKind -Force | Out-Null
        Add-WibRestoredMarker -Entry $Entry
        return $true
    } else {
        if (Test-Path -LiteralPath $regPath) {
            Remove-ItemProperty -LiteralPath $regPath -Name $Entry.Name -Force -ErrorAction SilentlyContinue | Out-Null
        }
        Add-WibRestoredMarker -Entry $Entry
        return $true
    }
}

function Invoke-WibTweakRepatch {
    param($Entry)
    if ($Entry.TargetScope -eq 'default-user-only') {
        Write-Verbose "Skipping repatch of default-user template tweak: $($Entry.Path)"
        return $false
    }

    $regPath = Get-WibLiveRegistryPath -Hive $Entry.Hive -Path $Entry.Path

    if ($Entry.Action -eq 'DeleteKey') {
        if (Test-Path -LiteralPath $regPath) {
            Remove-Item -LiteralPath $regPath -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
            $ok = (-not (Test-Path -LiteralPath $regPath))
            if ($ok) { Remove-WibRestoredMarker -Entry $Entry }
            return $ok
        }
        Remove-WibRestoredMarker -Entry $Entry
        return $true
    }

    if ($Entry.Action -eq 'Set') {
        if (-not (Test-Path -LiteralPath $regPath)) {
            $null = New-Item -Path $regPath -Force
        }
        $val = $Entry.NewValue
        if ($Entry.NewKind -eq 'DWord') { $val = [int]$val }
        New-ItemProperty -LiteralPath $regPath -Name $Entry.Name -Value $val -PropertyType $Entry.NewKind -Force | Out-Null
        Remove-WibRestoredMarker -Entry $Entry
        return $true
    }

    return $false
}
Set-Alias -Name Repatch-WibTweakEntry -Value Invoke-WibTweakRepatch -ErrorAction SilentlyContinue

# --- Load Journal File ---
$script:IsDemo = $false
if (-not (Test-Path -LiteralPath $JournalPath)) {
    if ($NonInteractive -or $CheckDriftOnly -or $RestoreAll -or $Repatch) {
        throw "Journal file not found at: $JournalPath"
    }
    $script:IsDemo = $true
    Write-Warning "Journal file not found at $JournalPath. Running in demonstration mode (read-only)."
    $journalData = @{
        tool    = '0.1.0'
        profile = 'balanced'
        journal = @(
            @{ Action = 'Set'; Hive = 'SOFTWARE'; Path = 'Policies\Microsoft\Windows\DataCollection'; Name = 'AllowTelemetry'; NewValue = 0; NewKind = 'DWord'; OldValue = 3; OldKind = 'DWord'; Existed = $true; Restorable = $true; TargetScope = 'system'; ScopeNote = 'Applies system-wide.' },
            @{ Action = 'Set'; Hive = 'NTUSER'; Path = 'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; Name = 'EnableTransparency'; NewValue = 0; NewKind = 'DWord'; OldValue = 1; OldKind = 'DWord'; Existed = $true; Restorable = $true; TargetScope = 'default-user-only'; ScopeNote = 'Applies only to newly created user accounts (Users\Default\NTUSER.DAT).' }
        )
    }
} else {
    $rawContent = Get-Content -LiteralPath $JournalPath -Raw -Encoding UTF8
    $journalData = ConvertTo-WibHashtable ($rawContent | ConvertFrom-Json)
}

$entries = @()
if ($journalData.ContainsKey('journal')) {
    $entries = @($journalData['journal'])
} elseif ($journalData.ContainsKey('entries')) {
    $entries = @($journalData['entries'])
}

# --- Non-Interactive Headless Mode ---
if ($NonInteractive -or $CheckDriftOnly -or $RestoreAll -or $Repatch) {
    Write-Host "WIB Panel [Headless Mode]: Analyzing $($entries.Count) journaled tweak(s)..." -ForegroundColor Cyan
    $driftResults = New-Object System.Collections.ArrayList
    $driftedCount = 0
    $repatchedCount = 0

    $evalEntries = $entries
    if ($RestoreAll) {
        $evalEntries = @($entries); [array]::Reverse($evalEntries)
    } elseif ($Repatch -or $CheckDriftOnly) {
        $evalEntries = Get-WibEffectiveEntries -Entries $entries
    }

    foreach ($e in $evalEntries) {
        $drift = $null
        $statusStr = 'Unknown'
        try {
            $drift = Test-WibTweakDrift -Entry $e
            if ($drift.Drifted) { $driftedCount++ }

            if ($RestoreAll) {
                if ($e.ContainsKey('Restorable') -and -not [bool]$e.Restorable) {
                    $statusStr = 'Skipped (Non-Restorable)'
                } elseif ($DryRun) {
                    $statusStr = 'DryRun (Restore Preview)'
                } else {
                    $restored = Restore-WibTweakEntry -Entry $e
                    $statusStr = if ($restored) { 'Restored' } else { 'FailedToRestore' }
                }
            } elseif ($Repatch) {
                if ($drift.Drifted) {
                    if (-not $DryRun) {
                        $repatched = Invoke-WibTweakRepatch -Entry $e
                        $statusStr = if ($repatched) { 'Repatched' } else { 'FailedToRepatch' }
                        if ($repatched) { $repatchedCount++ }
                    } else {
                        $statusStr = 'Drifted (DryRun Repatch)'
                    }
                } else {
                    $statusStr = $drift.Status
                }
            } else {
                $statusStr = $drift.Status
            }
        } catch {
            $statusStr = "Error: $($_.Exception.Message)"
        }

        [void]$driftResults.Add([ordered]@{
            Hive        = $e.Hive
            Path        = $e.Path
            Name        = $e.Name
            TargetScope = $e.TargetScope
            Status      = $statusStr
            Drifted     = if ($drift) { $drift.Drifted } else { $false }
            Restorable  = [bool]$e.Restorable
        })
    }

    if ($Repatch -and $LogFile) {
        $logDir = Split-Path -Parent $LogFile
        if ($logDir -and -not (Test-Path -LiteralPath $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }
        $logLine = "[{0}] Re-patch run (DryRun={1}): {2} examined, {3} drifted, {4} re-patched.`r`n" -f `
            (Get-Date).ToUniversalTime().ToString('o'), [bool]$DryRun, $entries.Count, $driftedCount, $repatchedCount
        [System.IO.File]::AppendAllText($LogFile, $logLine)
    }

    Write-Host "Analysis Complete: $($entries.Count) tweaks examined. $driftedCount drifted from original applied configuration. Repatched: $repatchedCount." -ForegroundColor Green
    return [PSCustomObject]@{
        TotalCount     = $entries.Count
        DriftedCount   = $driftedCount
        RepatchedCount = $repatchedCount
        Results        = @($driftResults)
    }
}

# --- WinForms Interactive GUI ---
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$form = New-Object System.Windows.Forms.Form
$form.Text = "WIB Post-Install Control Panel (Profile: $($journalData.profile))"
$form.Size = New-Object System.Drawing.Size(1000, 620)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

# Header Panel
$headerPanel = New-Object System.Windows.Forms.Panel
$headerPanel.Dock = 'Top'
$headerPanel.Height = 70
$headerPanel.BackColor = [System.Drawing.Color]::FromArgb(240, 244, 248)
$form.Controls.Add($headerPanel)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = "Windows Image Builder - Live Configuration & Drift Panel"
$lblTitle.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
$lblTitle.AutoSize = $true
$lblTitle.Location = New-Object System.Drawing.Point(12, 10)
$headerPanel.Controls.Add($lblTitle)

$lblNotice = New-Object System.Windows.Forms.Label
if ($script:IsDemo) {
    $lblNotice.Text = "DEMO MODE (Read-Only): Journal file not found. Registry restoration and repatching are disabled."
    $lblNotice.ForeColor = [System.Drawing.Color]::DarkRed
} else {
    $lblNotice.Text = "Note: 'default-user-only' tweaks affect newly created accounts. Changes made to NTUSER will not rewrite active user HKCU hives."
    $lblNotice.ForeColor = [System.Drawing.Color]::DarkSlateGray
}
$lblNotice.AutoSize = $true
$lblNotice.Location = New-Object System.Drawing.Point(14, 40)
$headerPanel.Controls.Add($lblNotice)

# Data Grid View
$grid = New-Object System.Windows.Forms.DataGridView
$grid.Dock = 'Fill'
$grid.AllowUserToAddRows = $false
$grid.AllowUserToDeleteRows = $false
$grid.ReadOnly = $true
$grid.SelectionMode = 'FullRowSelect'
$grid.MultiSelect = $true
$grid.RowHeadersVisible = $false
$grid.AutoSizeColumnsMode = 'Fill'

[void]$grid.Columns.Add('Hive', 'Hive')
[void]$grid.Columns.Add('Path', 'Registry Path')
[void]$grid.Columns.Add('Name', 'Value Name')
[void]$grid.Columns.Add('Scope', 'Target Scope')
[void]$grid.Columns.Add('Applied', 'Applied Value')
[void]$grid.Columns.Add('Original', 'Original Value')
[void]$grid.Columns.Add('Status', 'Live State')

$form.Controls.Add($grid)

# Populate Grid
function Update-Grid {
    $grid.Rows.Clear()
    $effEntries = Get-WibEffectiveEntries -Entries $entries
    foreach ($e in $effEntries) {
        $drift = Test-WibTweakDrift -Entry $e
        $scopeText = if ($e.TargetScope -eq 'default-user-only') { 'Default-User (Future)' } else { 'System' }
        $appliedText = if ($e.Action -eq 'DeleteKey') { '[Deleted]' } else { [string]$e.NewValue }
        $origText    = if ($e.Existed) { [string]$e.OldValue } else { '[Did Not Exist]' }

        $rowIdx = $grid.Rows.Add($e.Hive, $e.Path, $e.Name, $scopeText, $appliedText, $origText, $drift.Status)
        $row = $grid.Rows[$rowIdx]
        $row.Tag = $e

        if ($drift.Drifted) {
            $row.DefaultCellStyle.ForeColor = [System.Drawing.Color]::DarkRed
        } else {
            $row.DefaultCellStyle.ForeColor = [System.Drawing.Color]::DarkGreen
        }
    }
}
Set-Alias -Name Refresh-Grid -Value Update-Grid -ErrorAction SilentlyContinue

Update-Grid

# Button Panel
$buttonPanel = New-Object System.Windows.Forms.Panel
$buttonPanel.Dock = 'Bottom'
$buttonPanel.Height = 50
$form.Controls.Add($buttonPanel)

$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Text = "Refresh Drift Status"
$btnRefresh.Size = New-Object System.Drawing.Size(150, 32)
$btnRefresh.Location = New-Object System.Drawing.Point(12, 9)
$btnRefresh.Add_Click({ Refresh-Grid })
$buttonPanel.Controls.Add($btnRefresh)

$btnRestoreSelected = New-Object System.Windows.Forms.Button
$btnRestoreSelected.Text = "Restore Selected"
$btnRestoreSelected.Size = New-Object System.Drawing.Size(150, 32)
$btnRestoreSelected.Location = New-Object System.Drawing.Point(170, 9)
$btnRestoreSelected.Add_Click({
    if ($script:IsDemo) {
        [System.Windows.Forms.MessageBox]::Show('Live restoration is disabled in demo mode.', 'Demo Mode', 'OK', 'Warning')
        return
    }
    $isAdmin = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
    if (-not $isAdmin) {
        [System.Windows.Forms.MessageBox]::Show('Administrator privileges are required to restore registry settings. Please restart WibPanel as Administrator.', 'Elevation Required', 'OK', 'Warning')
        return
    }
    $selectedRows = @($grid.SelectedRows | Sort-Object Index -Descending)
    if ($selectedRows.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show('Please select one or more tweaks to restore.', 'No Selection', 'OK', 'Information')
        return
    }
    $confirm = [System.Windows.Forms.MessageBox]::Show("Restore $($selectedRows.Count) selected tweak(s) to original state?", 'Confirm Revert', 'YesNo', 'Question')
    if ($confirm -eq [System.Windows.Forms.DialogResult]::Yes) {
        $succ = 0; $fail = 0
        foreach ($r in $selectedRows) {
            try {
                $entry = $r.Tag
                $ok = Restore-WibTweakEntry -Entry $entry
                if ($ok) { $succ++ } else { $fail++ }
            } catch { $fail++ }
        }
        [System.Windows.Forms.MessageBox]::Show("Restoration completed: $succ restored, $fail failed or skipped.", 'Restore Complete', 'OK', 'Information') | Out-Null
        Update-Grid
    }
})
$buttonPanel.Controls.Add($btnRestoreSelected)

$btnRestoreAll = New-Object System.Windows.Forms.Button
$btnRestoreAll.Text = "Restore All Tweaks"
$btnRestoreAll.Size = New-Object System.Drawing.Size(150, 32)
$btnRestoreAll.Location = New-Object System.Drawing.Point(330, 9)
$btnRestoreAll.Add_Click({
    if ($script:IsDemo) {
        [System.Windows.Forms.MessageBox]::Show('Global restoration is disabled in demo mode.', 'Demo Mode', 'OK', 'Warning')
        return
    }
    $isAdmin = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
    if (-not $isAdmin) {
        [System.Windows.Forms.MessageBox]::Show('Administrator privileges are required to restore registry settings. Please restart WibPanel as Administrator.', 'Elevation Required', 'OK', 'Warning')
        return
    }
    $confirm = [System.Windows.Forms.MessageBox]::Show("Are you sure you want to restore ALL $($entries.Count) journaled tweaks to original system defaults?", 'Confirm Global Rollback', 'YesNo', 'Warning')
    if ($confirm -eq [System.Windows.Forms.DialogResult]::Yes) {
        $ordered = @($entries)
        [array]::Reverse($ordered)
        $succ = 0; $fail = 0
        foreach ($e in $ordered) {
            try {
                $ok = Restore-WibTweakEntry -Entry $e
                if ($ok) { $succ++ } else { $fail++ }
            } catch { $fail++ }
        }
        [System.Windows.Forms.MessageBox]::Show("Global rollback completed: $succ restored, $fail failed or skipped.", 'Rollback Complete', 'OK', 'Information') | Out-Null
        Update-Grid
    }
})
$buttonPanel.Controls.Add($btnRestoreAll)

$btnRepatchAll = New-Object System.Windows.Forms.Button
$btnRepatchAll.Text = "Re-patch Drifted Policies"
$btnRepatchAll.Size = New-Object System.Drawing.Size(180, 32)
$btnRepatchAll.Location = New-Object System.Drawing.Point(490, 9)
$btnRepatchAll.BackColor = [System.Drawing.Color]::FromArgb(40, 167, 69)
$btnRepatchAll.ForeColor = [System.Drawing.Color]::White
$btnRepatchAll.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnRepatchAll.Add_Click({
    if ($script:IsDemo) {
        [System.Windows.Forms.MessageBox]::Show('Re-patching is disabled in demo mode.', 'Demo Mode', 'OK', 'Warning')
        return
    }
    $isAdmin = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
    if (-not $isAdmin) {
        [System.Windows.Forms.MessageBox]::Show('Administrator privileges are required to modify system policies. Please restart WibPanel as Administrator.', 'Elevation Required', 'OK', 'Warning')
        return
    }
    $confirm = [System.Windows.Forms.MessageBox]::Show("Re-apply configured WIB policies to all drifted tweaks?", 'Confirm Re-patch', 'YesNo', 'Question')
    if ($confirm -eq [System.Windows.Forms.DialogResult]::Yes) {
        $reCount = 0
        $effEntries = Get-WibEffectiveEntries -Entries $entries
        foreach ($e in $effEntries) {
            $drift = Test-WibTweakDrift -Entry $e
            if ($drift.Drifted) {
                try {
                    $ok = Invoke-WibTweakRepatch -Entry $e
                    if ($ok) { $reCount++ }
                } catch { Write-Verbose $_.Exception.Message }
            }
        }
        [System.Windows.Forms.MessageBox]::Show("Re-patched $reCount drifted tweak(s) back to intended configuration.", 'Re-patch Complete', 'OK', 'Information') | Out-Null
        Update-Grid
    }
})
$buttonPanel.Controls.Add($btnRepatchAll)

if ($script:IsDemo) {
    $btnRestoreSelected.Enabled = $false
    $btnRestoreAll.Enabled = $false
    $btnRepatchAll.Enabled = $false
}

[void]$form.ShowDialog()
