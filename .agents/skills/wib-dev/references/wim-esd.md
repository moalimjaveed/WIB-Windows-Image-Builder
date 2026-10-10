# WIM vs ESD Image Reference

## Image Formats in Windows Setup

Official Microsoft Windows media ships with one of two container formats inside `sources\`:

| Feature | WIM (`install.wim`) | ESD (`install.esd`) |
|---|---|---|
| **Primary Compression** | LZX (`max`) or XPRESS (`fast`) | LZMS (`recovery`) |
| **Mounting** | Read-write or Read-only | Read-only only (cannot mount read-write) |
| **File Size** | Larger (typically 4.5 – 6 GB) | Smaller (typically 3.5 – 4.5 GB) |
| **Common Origin** | Volume License / MSDN / TechNet ISOs | Media Creation Tool (MCT) ISOs |
| **Modifiability** | Directly modifiable via DISM | Must be exported to WIM before servicing |

## ESD to WIM Conversion Workflow

Because `install.esd` cannot be mounted read-write for offline servicing, Stage 2 (`Mount`) checks whether `sources\install.wim` exists. If only `install.esd` is present, it is converted before mounting:

```powershell
# Inspect available indexes inside ESD
$images = Get-WindowsImage -ImagePath "$isoDir\sources\install.esd"

# Select index (e.g. Index 1 for Windows 11 Pro)
$index = 1

# Export specific index from ESD to WIM
Export-WindowsImage -SourceImagePath "$isoDir\sources\install.esd" `
    -SourceIndex $index `
    -DestinationImagePath "$isoDir\sources\install.wim" `
    -CompressionType max `
    -CheckIntegrity

# Remove install.esd to conserve disk space and prevent setup conflict
Remove-Item "$isoDir\sources\install.esd" -Force
```

## Index Enumeration and Edition Discovery

Never assume Index 1 is the intended edition. Always query image metadata:

```powershell
$imageInfo = Get-WindowsImage -ImagePath "$imagePath"
foreach ($img in $imageInfo) {
    [PSCustomObject]@{
        Index       = $img.ImageIndex
        Name        = $img.ImageName
        Description = $img.ImageDescription
        SizeGB      = [math]::Round($img.ImageSize / 1GB, 2)
        Architecture= $img.Architecture
        Version     = $img.Version
    }
}
```

## Boot Image Servicing (`boot.wim`)

`boot.wim` contains the Windows Preinstallation Environment (WinPE) and Windows Setup loader:

- **Index 1 (WinPE)**: Minimal pre-boot environment. Used by recovery tools and command prompt.
- **Index 2 (Windows Setup)**: Interactive GUI installer started from bootable media.

When hardware requirement bypasses (e.g. TPM 2.0, Secure Boot, RAM, CPU checks) are applied for setup, WIB mounts **Index 2**:

```powershell
# Mount boot.wim index 2
Mount-WindowsImage -ImagePath "$isoDir\sources\boot.wim" -Index 2 -Path "$workDir\mount_boot"

# Load SYSTEM hive from boot image
& reg.exe load "HKLM\wib_boot_SYSTEM" "$workDir\mount_boot\Windows\System32\config\SYSTEM" 2>&1 | Out-Null

# Apply setup bypass keys under HKLM\wib_boot_SYSTEM\Setup\LabConfig
New-Item -Path "Registry::HKLM\wib_boot_SYSTEM\Setup\LabConfig" -Force | Out-Null
Set-ItemProperty -Path "Registry::HKLM\wib_boot_SYSTEM\Setup\LabConfig" -Name "BypassTPMCheck" -Value 1 -Type DWord
Set-ItemProperty -Path "Registry::HKLM\wib_boot_SYSTEM\Setup\LabConfig" -Name "BypassSecureBootCheck" -Value 1 -Type DWord
Set-ItemProperty -Path "Registry::HKLM\wib_boot_SYSTEM\Setup\LabConfig" -Name "BypassRAMCheck" -Value 1 -Type DWord
Set-ItemProperty -Path "Registry::HKLM\wib_boot_SYSTEM\Setup\LabConfig" -Name "BypassCPUCheck" -Value 1 -Type DWord

# Unload hive and commit boot.wim
[gc]::Collect()
[gc]::WaitForPendingFinalizers()
& reg.exe unload "HKLM\wib_boot_SYSTEM" 2>&1 | Out-Null
Dismount-WindowsImage -Path "$workDir\mount_boot" -Save -CheckIntegrity
```

## Final Packaging Compression

During Stage 8 (`Package`), the serviced `install.wim` is re-exported to remove residual block fragmentation and apply clean compression:

```powershell
# Export with recovery compression (WIMBoot / LZMS solid compression)
& dism.exe /Export-Image /SourceImageFile:$tempWim /SourceIndex:1 `
    /DestinationImageFile:$finalWim /Compress:recovery /CheckIntegrity
```
