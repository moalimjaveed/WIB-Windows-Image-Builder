# DISM Offline Servicing — WIB Reference

Command reference for the DISM operations WIB uses. All operations are offline
(image not booted). Run elevated.

---

## Image lifecycle

```powershell
# Mount (read-write for apply; read-only for dry-run)
Mount-WindowsImage -ImagePath $wim -Index $index -Path $mount
Mount-WindowsImage -ImagePath $wim -Index $index -Path $mount -ReadOnly

# Check what is mounted
Get-WindowsImage -Mounted

# Save and dismount (commit changes)
Dismount-WindowsImage -Path $mount -Save

# Discard (rollback, no changes committed)
Dismount-WindowsImage -Path $mount -Discard

# Cleanup stale mounts (when WIB crashes mid-build)
dism /Cleanup-Wim
# or
Clear-WindowsCorruptMountPoint
```

## Scan operations (Stage 3)

```powershell
# Provisioned AppX packages
Get-AppxProvisionedPackage -Path $mount

# Optional features (e.g. Internet Explorer, Steps Recorder)
Get-WindowsOptionalFeature -Path $mount

# Capabilities (e.g. Quick Assist, Math Recognizer)
Get-WindowsCapability -Path $mount

# (Future) Packages / KBs installed in image
Get-WindowsPackage -Path $mount
```

## Removal operations (Stage 5 Apply)

```powershell
# Remove provisioned AppX
Remove-AppxProvisionedPackage -Path $mount -PackageName $pkg.PackageName

# Disable optional feature (keeps the payload; can be re-enabled)
Disable-WindowsOptionalFeature -Path $mount -FeatureName $name -Remove

# Remove capability
Remove-WindowsCapability -Path $mount -Name $capabilityName
```

> [!WARNING]
> `-Remove` on `Disable-WindowsOptionalFeature` deletes the payload. Do NOT use it
> on servicing-critical features (e.g. `NetFx4`). Keep a `never-touch` list.

## Export (Stage 8 Package)

```powershell
# Export single index with recovery compression (WIB default)
dism /Export-Image /SourceImageFile:$wim /SourceIndex:$index `
     /DestinationImageFile:$wim2 /Compress:recovery

# Compression options: none | fast | max | recovery
# 'recovery' = WIMBoot-compatible, good balance for distribution
```

## ESD to WIM conversion

```powershell
# WIB uses Export-WindowsImage for ESD conversion
Export-WindowsImage -SourceImagePath $esd -SourceIndex $index `
    -DestinationImagePath $wim -CompressionType max -CheckIntegrity
```

## Component store cleanup

```powershell
# Conservative (WIB default, serviceability preserved)
dism /Image:$mount /Cleanup-Image /StartComponentCleanup

# Aggressive (opt-in, breaks update rollback)
dism /Image:$mount /Cleanup-Image /StartComponentCleanup /ResetBase
```

> [!CAUTION]
> `/ResetBase` removes superseded component versions permanently. Updates cannot be
> rolled back after `/ResetBase`. Only enable with `aggressive: true` in the profile
> AND an explicit `-AcceptRisk` flag.

## boot.wim specifics

`boot.wim` has two indexes:
- Index 1: Windows PE (setup environment)
- Index 2: Windows Setup (the one WIB patches for hardware-check-bypass)

WIB only mounts index 2. Registry tweaks go to `SOFTWARE` hive only (boot image
hive paths differ from install image).

## Offline registry hive paths (relative to mount root)

| Hive | Relative path |
|---|---|
| SOFTWARE | `Windows\System32\config\SOFTWARE` |
| SYSTEM | `Windows\System32\config\SYSTEM` |
| DEFAULT | `Windows\System32\config\DEFAULT` |
| NTUSER (Default user) | `Users\Default\NTUSER.DAT` |

Load with `reg.exe load HKLM\wib_<NAME> <absolute-path>`. The key name `wib_*` is
WIB's namespace; do not use `HKLM\SOFTWARE` directly.

## oscdimg — ISO creation

```
oscdimg -m -o -u2 -udfver102 -lWIB_WIN11
  -bootdata:2#p0,e,b<isoDir>\boot\etfsboot.com#pEF,e,b<isoDir>\efi\microsoft\boot\efisys.bin
  <isoDir> <outputIso>
```

- `-m` — ignore maximum image size
- `-o` — optimise storage by encoding duplicate files
- `-u2` — UDF file system version 2.01
- `-udfver102` — force UDF version 1.02 for broader compatibility
- `-l` — volume label

oscdimg comes from the **Windows ADK — Deployment Tools** feature. Verify signature
before use: `(Get-AuthenticodeSignature $path).SignerCertificate.Subject` must contain
`Microsoft`.

## DISM exit codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | General error (check DISM log at `%WINDIR%\Logs\DISM\dism.log`) |
| 2 | Invalid argument |
| 14098 | Component store corrupted |
| 50 | Not supported in current state (stale mount, wrong image type) |

WIB checks `$LASTEXITCODE -ne 0` and throws after every `dism.exe` call.
