# DISM Offline Servicing Reference

Native Deployment Image Servicing and Management (DISM) is the primary engine for offline Windows image modification in WIB. WIB utilizes native PowerShell DISM cmdlets (`Dism` module) and direct calls to `dism.exe` when specific flags or exit code controls are required.

## Mount and Dismount Lifecycle

All DISM operations occur strictly on offline mounted images with elevation (Administrator privileges required).

```powershell
# 1. Mount image
Mount-WindowsImage -ImagePath "$workDir\iso\sources\install.wim" -Index $index -Path $mountDir -CheckIntegrity

# Read-only mount for dry-run inspection (Stage 4)
Mount-WindowsImage -ImagePath "$workDir\iso\sources\install.wim" -Index $index -Path $mountDir -ReadOnly

# 2. Check mount status
Get-WindowsImage -Mounted

# 3. Commit changes and dismount
Dismount-WindowsImage -Path $mountDir -Save -CheckIntegrity

# 4. Discard changes (rollback on failure)
Dismount-WindowsImage -Path $mountDir -Discard
```

### Stale Mount Recovery

If a previous run was aborted or terminated unexpectedly:

```powershell
# Clean up orphaned mounts
& dism.exe /Cleanup-Wim
if ($LASTEXITCODE -ne 0) {
    Write-Warning "dism.exe /Cleanup-Wim returned exit code $LASTEXITCODE"
}

# PowerShell cmdlet alternative
Clear-WindowsCorruptMountPoint
```

## Inventory and Inspection (Scan Stage)

The scanner must never assume hardcoded package or feature names. All detections are performed dynamically:

```powershell
# Provisioned AppX packages
$appxPackages = Get-AppxProvisionedPackage -Path $mountDir

# Optional features
$features = Get-WindowsOptionalFeature -Path $mountDir

# Windows capabilities
$capabilities = Get-WindowsCapability -Path $mountDir

# Installed packages/updates (servicing stack)
$packages = Get-WindowsPackage -Path $mountDir
```

## Modification and Removal (Apply Stage)

### Provisioned AppX Packages
```powershell
Remove-AppxProvisionedPackage -Path $mountDir -PackageName $pkg.PackageName
```

### Optional Features
```powershell
# Disables feature without deleting servicing payload (reversible)
Disable-WindowsOptionalFeature -Path $mountDir -FeatureName $featureName

# Removing payload (-Remove) deletes binaries from WinSxS
# WARNING: Do NOT use -Remove on servicing-critical dependencies (e.g. NetFx4)
Disable-WindowsOptionalFeature -Path $mountDir -FeatureName $featureName -Remove
```

### Windows Capabilities
```powershell
Remove-WindowsCapability -Path $mountDir -Name $capabilityName
```

## Component Store Cleanup

The component store (`WinSxS`) can be trimmed, but servicing stack rules must be respected:

```powershell
# Conservative cleanup (WIB default, maintains update rollback capability)
& dism.exe /Image:$mountDir /Cleanup-Image /StartComponentCleanup
if ($LASTEXITCODE -ne 0) { throw "StartComponentCleanup failed ($LASTEXITCODE)" }

# Aggressive cleanup (opt-in only, requires aggressive: true and -AcceptRisk)
# WARNING: Deletes superseded component baselines. Cumulative updates cannot be uninstalled.
& dism.exe /Image:$mountDir /Cleanup-Image /StartComponentCleanup /ResetBase
if ($LASTEXITCODE -ne 0) { throw "ResetBase failed ($LASTEXITCODE)" }
```

## Image Packaging and Compression

```powershell
# Export single index with recovery compression (LZMS)
& dism.exe /Export-Image /SourceImageFile:$sourceWim /SourceIndex:$index `
    /DestinationImageFile:$destWim /Compress:recovery /CheckIntegrity
if ($LASTEXITCODE -ne 0) { throw "Export-Image failed ($LASTEXITCODE)" }

# PowerShell cmdlet equivalent
Export-WindowsImage -SourceImagePath $sourceWim -SourceIndex $index `
    -DestinationImagePath $destWim -CompressionType max -CheckIntegrity
```

## Exit Code Handling

Always inspect `$LASTEXITCODE` following direct calls to `dism.exe`:

| Exit Code | Meaning | Remediation |
|---|---|---|
| `0` | Success | Continue pipeline |
| `1` | General error | Check `%WINDIR%\Logs\DISM\dism.log` |
| `2` | Invalid arguments | Verify path formatting and parameter syntax |
| `50` | Operation not supported | Check if image is mounted or in bad state |
| `14098` | Component store corrupt | Repair source or re-extract clean ISO |
