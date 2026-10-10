# Getting Started with Windows Image Builder (WIB)

This guide walks you through planning, building, verifying, and testing a customized Windows 11 installation image using Windows Image Builder.

---

## 1. Prerequisites Checklist

Before running WIB, ensure your workstation meets these requirements:

- [ ] **Host Operating System:** Windows 10 (version 21H2 or later) or Windows 11 (21H2 through 26H2, with 26H2 latest & recommended) x64 or ARM64.
- [ ] **PowerShell:** Windows PowerShell 5.1 (native Desktop edition included with Windows) or PowerShell 7.4+.
- [ ] **Administrative Elevation:** An elevated PowerShell session (**Run as Administrator**) is required for offline image mounting (`dism.exe`) and registry hive modification (`reg.exe load`).
- [ ] **Disk Storage:** At least **25 GB to 40 GB** of free temporary storage space on your working drive. Servicing extracts multi-gigabyte WIM images and creates scratch files.
- [ ] **Packaging Tool (`oscdimg.exe`):** Sourced from [Windows ADK Deployment Tools](https://learn.microsoft.com/windows-hardware/get-started/adk-install) or downloaded and verified automatically using `-DownloadOscdimg`.
- [ ] **Hypervisor for Testing:** Microsoft Hyper-V, Proxmox VE, or VirtualBox to validate the output ISO before installing on bare metal.

---

## 2. Obtaining & Verifying Source Installation Media

WIB does **not** provide or distribute Windows ISO files. You must supply your own legitimate Windows 11 installation media downloaded directly from Microsoft.

### Step 1: Download Official ISO Media
Download the official Windows 11 Multi-edition ISO directly from Microsoft:
- [Download Windows 11 Disk Image (ISO)](https://www.microsoft.com/software-download/windows11)

### Step 2: Verify the Cryptographic Hash
Confirm the integrity of your downloaded ISO by calculating its SHA-256 digest:

```powershell
Get-FileHash -Path "C:\ISOs\Win11_26H2_English_x64.iso" -Algorithm SHA256
```

> [!IMPORTANT]
> **Integrity vs. Provenance:** Always compare your calculated hash against Microsoft's official documentation or MSDN checksum lists. Calculating the hash of an unverified local ISO and passing it to `-ExpectedIsoSha256` only confirms that the file does not change during the build; it does not prove the file came from Microsoft.

---

## 3. Profile Inspection & Module Listing

Clone and navigate to the repository directory:

```powershell
git clone https://github.com/moalimjaveed/WIB-Windows-Image-Builder.git
cd WIB-Windows-Image-Builder
```

### Review Available Modules
To list all 36 registered trimming, optimization, and hardening modules without needing administrator privileges:

```powershell
.\build.ps1 -Command list
```

### Validate Profile Schemas
Before starting any build, validate your desired profile schema and view its canonical SHA-256 hash:

```powershell
.\build.ps1 -Command validate -ProfileName balanced
.\build.ps1 -Command validate -ProfileName lean
```

---

## 4. The Recommended Build Workflow

### Step 1: Preview the Build Plan (Dry-Run)
Always run a dry run first. A dry run mounts the image in a temporary workspace, catalogs provisioned packages and capabilities, evaluates your profile's rules, and outputs a complete preview report **without writing changes to the source image or generating an ISO**:

Open an elevated PowerShell prompt (**Run as Administrator**) and execute:

```powershell
.\build.ps1 `
    -IsoPath "C:\ISOs\Win11_26H2_English_x64.iso" `
    -ProfileName balanced `
    -Command plan
```

Review the printed plan:
- **AppX Removal:** Lists packages scheduled for removal while verifying that critical dependencies (`Microsoft.WindowsStore`, `Microsoft.DesktopAppInstaller`, `Microsoft.SecHealthUI`, `Microsoft.UI.Xaml`) remain protected.
- **Offline Registry Tweaks:** Displays targeted tweaks for `SOFTWARE`, `SYSTEM`, and `DEFAULT` user hives.
- **Servicing Checkpoints:** Confirms checkpoint boundaries.

---

### Step 2: Execute the Build Pipeline
Once you are satisfied with the preview plan, execute the full build:

```powershell
.\build.ps1 `
    -IsoPath "C:\ISOs\Win11_26H2_English_x64.iso" `
    -ProfileName balanced `
    -OutputIso "C:\Images\Win11_Balanced_Custom.iso" `
    -ExpectedIsoSha256 "<KNOWN_MICROSOFT_SHA256>"
```

#### What happens during the build:
1. **Preflight Check:** Verifies disk space, elevation, DISM availability, and source ISO hash invariance.
2. **Mounting:** Mounts the source ISO and extracts `sources\install.wim` into an isolated workspace.
3. **Stage Checkpoints:** Applies modifications in stages (packages, tweaks, hardening). Each completed stage commits a WIM append checkpoint (`Save-WindowsImage -Append`).
4. **General Verify Pass:** Performs post-modification consistency checks (ensuring no orphaned `TaskCache` registrations, ghost references, or damaged hive structures).
5. **Image Export:** Exports the modified image into a compressed, single-index WIM.
6. **ISO Authoring:** Packages the bootable UEFI/BIOS media using `oscdimg.exe`.
7. **Audit & Reporting:** Generates a timestamped HTML report, JSON manifest, and detached SHA-256 checksum.

---

## 5. Locating Build Artifacts & Audit Reports

When the build completes, the terminal displays the path to your new ISO and its associated audit report:

* **Output ISO:** `C:\Images\Win11_Balanced_Custom.iso`
* **Build Manifest:** `reports\<timestamp>_<run_id>\manifest.json`
* **HTML Report:** `reports\<timestamp>_<run_id>\report.html`
* **Detached Checksum:** `reports\<timestamp>_<run_id>\manifest.json.sha256`

Open `report.html` in your web browser to review the complete cryptographic log, package removals, applied tweaks, and execution telemetry.

---

## 6. Validating in a Disposable Virtual Machine (Hyper-V)

> [!TIP]
> **Virtual Machine Verification:**  
> Always test customized installation media in a virtual machine before deploying to bare-metal hardware.

### Quick Hyper-V VM Creation:
1. Open PowerShell as Administrator.
2. Create a Generation 2 virtual machine:
   ```powershell
   New-VM -Name "WIB-Test-VM" `
          -MemoryStartupBytes 4GB `
          -Generation 2 `
          -NewVHDPath "C:\VMs\WibTest.vhdx" `
          -NewVHDSizeBytes 60GB
   ```
3. Attach your customized ISO to the DVD drive:
   ```powershell
   Add-VMDvdDrive -VMName "WIB-Test-VM" -Path "C:\Images\Win11_Balanced_Custom.iso"
   ```
4. Configure boot order and enable TPM for Windows 11 compatibility:
   ```powershell
   Set-VMFirmware -VMName "WIB-Test-VM" -FirstBootDevice (Get-VMDvdDrive -VMName "WIB-Test-VM")
   Set-VMKeyProtector -VMName "WIB-Test-VM" -NewLocalKeyProtector
   Enable-VMTPM -VMName "WIB-Test-VM"
   ```
5. Start the virtual machine and verify that Windows Setup completes to the desktop:
   ```powershell
   Start-VM -Name "WIB-Test-VM"
   ```

---

## 7. Generating Offline Unattended Answer Files

To automate installation without interactive setup prompts, generate an `autounattend.xml` answer file using [`tools/New-WibUnattend.ps1`](../tools/New-WibUnattend.ps1):

```powershell
$adminPassword = Read-Host -Prompt "Enter local admin password" -AsSecureString

powershell.exe -File .\tools\New-WibUnattend.ps1 `
    -Username "WibAdmin" `
    -SecurePassword $adminPassword `
    -AutoLogon `
    -AcceptCredentialExposureRisk `
    -OutputPath "C:\Images\autounattend.xml"
```

> [!WARNING]
> **Credential Exposure Notice:** Windows Setup answer file passwords are Base64 obscured (`<PlainText>false</PlainText>`), **not encrypted**. Anyone with read access to the installation media or the XML file can decode the password.  
> * WIB scrubs plaintext strings from unmanaged memory buffers during generation.  
> * Use temporary, unique credentials for setup.  
> * Never commit answer files to public repositories.  
> * Rotate or delete the administrator password immediately after installation completes.

To include the answer file in your custom ISO, copy it into the root of the ISO staging directory.

---

## 8. Post-Install Auditing & Rollback (`WibPanel.ps1`)

WIB embeds an undo journal inside every customized image at `C:\Windows\WIB\journal.json` and `journal.reg`.

### Rollback Scope:
* **Registry Tweaks:** Fully cataloged in `journal.reg` and `journal.json`. Can be inspected and reversed at any time via `tools/WibPanel.ps1`.
* **Package Removals:** AppX packages removed offline are permanently excised from the installation media. Reversing an AppX removal post-installation requires downloading the package from the Microsoft Store or re-provisioning from original media.

To inspect or reverse registry settings interactively on the deployed system:

```powershell
powershell.exe -File .\tools\WibPanel.ps1
```

Or run headless drift detection and re-patching:
```powershell
.\build.ps1 -Command repatch -JournalPath "C:\Windows\WIB\journal.json" -DryRun
```

---

## 9. Troubleshooting Common Errors

### System Error 740: "The requested operation requires elevation"
* **Symptom:** Build fails immediately when attempting to mount the image.
* **Fix:** Close PowerShell and reopen it by right-clicking the shortcut and choosing **Run as Administrator**.

### Insufficient Disk Space on Drive C:
* **Symptom:** Build halts with `Free work drive space below minimum threshold`.
* **Fix:** Redirect the temporary scratch workspace to a drive with more space:
  ```powershell
  .\build.ps1 -IsoPath "..." -WorkDir "D:\WIB_Workspace" ...
  ```

### Orphaned DISM Mounts
* **Symptom:** Error stating that a directory is already mounted or locked by DISM.
* **Fix:** Dismount orphaned images and clean the servicing cache:
  ```powershell
  dism.exe /Cleanup-Wim
  dism.exe /Get-MountedWimInfo
  ```

### Missing `oscdimg.exe`
* **Symptom:** Error stating `oscdimg tool not found on PATH`.
* **Fix:** Add `-DownloadOscdimg` to your build command line to allow WIB to securely download and verify the official Microsoft ADK packaging tool.
