# Offline Registry Hive Reference

WIB modifies Windows configuration offline by directly mounting the registry hives from the offline image filesystem into the host system's `HKLM` namespace.

## Hive Architecture

| Hive Name | Source File in Image | Host Mount Target | Target Configuration |
|---|---|---|---|
| `SOFTWARE` | `Windows\System32\config\SOFTWARE` | `HKLM\wib_SOFTWARE` | System-wide software policies, AppX, Windows components |
| `SYSTEM` | `Windows\System32\config\SYSTEM` | `HKLM\wib_SYSTEM` | Services, device drivers, kernel settings, ControlSet001 |
| `DEFAULT` | `Windows\System32\config\DEFAULT` | `HKLM\wib_DEFAULT` | Default system account (LocalSystem) profile |
| `NTUSER` | `Users\Default\NTUSER.DAT` | `HKLM\wib_NTUSER` | Template profile cloned for all newly created user accounts |

> [!IMPORTANT]
> Settings targeted at newly created user accounts (e.g. Taskbar icons, Explorer preferences, Start recommendations) must be applied to `NTUSER` (`Users\Default\NTUSER.DAT`). Modifications made to `DEFAULT` only affect the SYSTEM service context.

## Mount and Dismount Protocol

Registry hive mounting and unmounting must adhere to strict hygiene to prevent file lock leakage on host systems.

### Mount Function
```powershell
function Mount-WibHives {
    param([string]$MountDir)

    $hives = @(
        @{ Name = 'SOFTWARE'; File = Join-Path $MountDir 'Windows\System32\config\SOFTWARE' },
        @{ Name = 'SYSTEM';   File = Join-Path $MountDir 'Windows\System32\config\SYSTEM' },
        @{ Name = 'DEFAULT';  File = Join-Path $MountDir 'Windows\System32\config\DEFAULT' },
        @{ Name = 'NTUSER';   File = Join-Path $MountDir 'Users\Default\NTUSER.DAT' }
    )

    foreach ($h in $hives) {
        if (Test-Path $h.File) {
            $key = "HKLM\wib_$($h.Name)"
            & reg.exe load $key $h.File 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to load offline registry hive $($h.Name) from $($h.File) (Exit code: $LASTEXITCODE)"
            }
        }
    }
}
```

### Dismount Protocol with Retry Loop
PowerShell and Windows keep file handles open across garbage collection cycles. An explicit garbage collection pass and exponential backoff retry loop are mandatory:

```powershell
function Dismount-WibHives {
    $hives = @('NTUSER', 'DEFAULT', 'SYSTEM', 'SOFTWARE') # reverse order

    # Force .NET garbage collection to release open registry key handles
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()

    foreach ($name in $hives) {
        $key = "HKLM\wib_$name"
        $unloaded = $false
        $attempts = 0

        while (-not $unloaded -and $attempts -lt 6) {
            $attempts++
            & reg.exe unload $key 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                $unloaded = $true
            } else {
                [System.GC]::Collect()
                [System.GC]::WaitForPendingFinalizers()
                Start-Sleep -Milliseconds (250 * $attempts)
            }
        }

        if (-not $unloaded) {
            Write-Warning "Failed to unload registry hive $key after 6 attempts. Run reg.exe unload manually."
        }
    }
}
```

### Mandatory `try/finally` Scope
All offline registry manipulations must occur within an enclosed `try/finally` block:

```powershell
try {
    Mount-WibHives -MountDir $Ctx.MountDir
    Invoke-WibTweaks -Ctx $Ctx
}
finally {
    Dismount-WibHives
}
```

## Declarative Tweak Application and Undo Journaling

When modifying values offline, the existing state must be captured before writing new values:

```powershell
function Set-WibTweak {
    param(
        [hashtable]$Ctx,
        [string]$Hive,
        [string]$Path,
        [string]$Name,
        [object]$Value,
        [string]$Type = 'DWord'
    )

    $fullPath = "Registry::HKLM\wib_$Hive\$Path"
    if (-not (Test-Path $fullPath)) {
        New-Item -Path $fullPath -Force | Out-Null
        $originalExists = $false
        $originalValue = $null
        $originalType = $null
    } else {
        $prop = Get-ItemProperty -Path $fullPath -Name $Name -ErrorAction SilentlyContinue
        if ($null -ne $prop -and $null -ne $prop.$Name) {
            $originalExists = $true
            $originalValue = $prop.$Name
            $originalType = (Get-Item -Path $fullPath).GetValueKind($Name).ToString()
        } else {
            $originalExists = $false
            $originalValue = $null
            $originalType = $null
        }
    }

    # Record to undo journal
    $Ctx.Journal += [PSCustomObject]@{
        Hive           = $Hive
        Path           = $Path
        Name           = $Name
        NewValue       = $Value
        NewType        = $Type
        OriginalExists = $originalExists
        OriginalValue  = $originalValue
        OriginalType   = $originalType
        AppliedUtc     = (Get-Date).ToUniversalTime().ToString('o')
    }

    Set-ItemProperty -Path $fullPath -Name $Name -Value $Value -Type $Type -Force
}
```
