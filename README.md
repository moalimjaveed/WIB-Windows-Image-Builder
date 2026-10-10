# WIB: Windows Image Builder (v0.2.29)

A manifest-driven PowerShell engine for planning, customizing, and auditing Windows installation media offline.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![PowerShell: 5.1 | 7.4+](https://img.shields.io/badge/PowerShell-5.1%20%7C%207.4%2B-blue.svg)](docs/COMPATIBILITY.md)
[![Host: Windows 10 | 11](https://img.shields.io/badge/Host-Windows%2010%20(21H2%2B)%20%7C%2011%20(21H2--26H2)-blue.svg)](docs/COMPATIBILITY.md)
[![Target: Win 11 (26H2 Latest/Rec) | Server 2022/2025](https://img.shields.io/badge/Target-Win%2011%20(26H2%20Latest%2FRec)%20%7C%20Server%202022%2F2025-blue.svg)](docs/COMPATIBILITY.md)

---

## Status at a Glance

* **Version:** `0.2.29`
* **Authoritative CLI:** [`build.ps1`](build.ps1)
* **Runtime Support:** Windows PowerShell 5.1 (native desktop engine, pure ASCII, zero third-party module dependencies) and PowerShell 7.4+ on Windows 10/11.
* **Automated Test Evidence:**
  * **655/655 assertions passing** across 51 test suites in [`tests/smoke.ps1`](tests/smoke.ps1).
  * **22/22 behavioral gates passing** (`G1`–`G22`) in [`tests/verify-gates.ps1`](tests/verify-gates.ps1).
* **Independent Software:** WIB is an independent open-source project and is not affiliated with, sponsored by, or endorsed by Microsoft Corporation. WIB does not bundle or distribute Windows installation media. You must supply legitimate Windows installation media obtained directly from Microsoft.

---

## What is Windows Image Builder?

**Windows Image Builder (WIB)** lets you create clean, fast, and bloat-free Windows 11 installation media (ISO or USB) **before** you install Windows on your PC.

Instead of installing Windows and then spending hours manually uninstalling junk apps, disabling telemetry, or running risky scripts on your live computer, WIB customizes the official Windows installer directly. When your installation finishes, your computer boots into an optimized, private, and responsive Windows desktop from day one.

### Why is WIB Better Than Traditional "Debloat" Scripts?

* **Safe & Isolated (Offline vs. Live):** Most debloat tools run directly on your active Windows desktop. If a script removes the wrong component or corrupts a registry key, your system can break, become unstable, or fail future Windows Updates. WIB modifies installation media *offline* in an isolated temporary workspace—your actual computer is never modified or put at risk during the build.
* **Never Breaks Core Subsystems:** Aggressive debloaters often break the Microsoft Store, Windows Security (Defender), Xbox Game Pass, or Windows Update. WIB includes strict built-in safeguards that protect critical OS dependencies (`Microsoft.WindowsStore`, `winget`, `SecHealthUI`, `WebView2`) by default.
* **Preview Every Change First (Zero Guesswork):** You never have to guess what will change. Running a dry-run (`.\build.ps1 -Command plan`) generates an exact preview of every package, feature, and registry tweak scheduled for modification before changing a single byte.
* **Reversible & Auditable:** Every registry tweak is recorded in an in-image undo journal (`journal.reg` and `journal.json`). You can review, audit, or reverse any setting at any time using [`tools/WibPanel.ps1`](tools/WibPanel.ps1). If a build is ever interrupted, transactional WIM checkpoints restore a clean state automatically.
* **100% Native & Transparent:** WIB is pure PowerShell built exclusively on official Microsoft utilities (`dism.exe`, `reg.exe`, and `oscdimg.exe`). There are zero closed-source executables, mystery background services, or untrusted binary wrappers.

---

## System Requirements

| Requirement | Specification | Details |
| :--- | :--- | :--- |
| **Host OS** | Windows 10 (21H2+) or Windows 11 (26H2 latest & recommended) x64 | Elevated Administrator prompt required for DISM filter drivers and registry hive mounting (`reg.exe load`). |
| **PowerShell Engine** | Windows PowerShell 5.1 or PowerShell 7.4+ | 100% native PS 5.1 compatible. Zero external PSGallery module dependencies. |
| **Target Images** | Windows 11 (21H2–26H2, with 26H2 latest & recommended) x64/ARM64, Windows Server 2022/2025 Desktop Experience | Official Microsoft ISO or WIM source. |
| **Disk Space** | 25–40 GB free temporary storage | Required on the scratch drive for WIM index extraction, staging, and ISO authoring. |
| **Image Authoring** | `oscdimg.exe` (v2.56+) | Sourced from Windows ADK Deployment Tools or the verified download cache (`-DownloadOscdimg`). |

For full compatibility details, see [`docs/COMPATIBILITY.md`](docs/COMPATIBILITY.md).

---

## How to Use WIB: Beginner's Step-by-Step Guide

Whether you prefer a graphical desktop app, an interactive menu, or automated PowerShell commands, WIB makes creating clean Windows installation media simple and transparent.

### Step 1: Download and Extract WIB

1. **Option A (GitHub ZIP Download):**
   * Download the repository ZIP file from GitHub.
   * Extract the files to a fast local drive (for example, `C:\WIB`).
   * *Avoid deeply nested folders, OneDrive-synced paths, or network shares.*
2. **Option B (Git Clone):**
   ```powershell
   git clone https://github.com/moalimjaveed/WIB-Windows-Image-Builder.git C:\WIB
   cd C:\WIB
   ```

### Step 2: Download the Official Windows 11 ISO

1. **Get Clean Installation Media Directly from Microsoft:**
   * Visit the official Microsoft download portal: [Download Windows 11](https://www.microsoft.com/software-download/windows11).
   * Download the multi-edition ISO for **Windows 11 (26H2 latest & recommended)** or 24H2.
2. **Place the ISO File on Your Computer:**
   * Save the file in a convenient folder, such as:
     * `C:\ISOs\Win11_26H2_English_x64.iso`
     * (or place it directly inside your `C:\WIB` folder).

---

### Step 3: Choose How to Launch WIB (3 Easy Ways)

Choose the method that works best for you:

#### Option 1: Desktop GUI Studio (`launch-gui.cmd`) -- *Easiest for Beginners*

No command typing required!

1. Open your `C:\WIB` folder in File Explorer.
2. Double-click **`launch-gui.cmd`** (or run `.\build.ps1 -Gui` in PowerShell).
3. If prompted by Windows User Account Control (UAC), click **Yes** to allow Administrator servicing.
4. In the **WIB Builder Studio** window:
   * **Source Windows ISO:** Click **Browse...** and select your downloaded Windows 11 ISO file.
   * **Custom Output ISO:** Choose where to save your customized ISO (e.g., `C:\ISOs\Win11_Custom_Balanced.iso`).
   * **Optimization Profile:** Select **`balanced`** (recommended for workstations & daily use) or **`lean`** (maximum speed for VMs & gaming).
   * **Target Edition:** Select your Windows edition (e.g., *Windows 11 Pro*) or leave as *Auto-detect*.
   * **Hardware Profile:** Keep on *Live Host (CIM Auto-Detect)* or choose a specific hardware spec.
   * **Unattended Setup:** Check options to bypass TPM/RAM requirements or configure an offline local user account.
5. Click **Preview Plan** to review all scheduled changes, then click **Start Build**!

#### Option 2: Interactive Menu Launcher (`build.cmd`) -- *Simple Console Menu*

1. Right-click **`build.cmd`** and select **Run as administrator** (or double-click it).
2. An interactive terminal menu opens immediately:
   ```text
   ================================================================================
     WIB: Windows Image Builder (v0.2.29)
     Hardware-adaptive, verifiable Windows 11 offline servicing engine
   ================================================================================
     Session:    Elevated (Administrator Servicing Active)
     Profiles:   adaptive, balanced, custom-risk, hardening, lean

     QUICK START / CLI USAGE:
     1. Launch Desktop GUI:      .\build.ps1 -Gui       (or .\launch-gui.cmd)
     2. Validate a Profile:      .\build.ps1 -Command validate -ProfileName balanced
     3. List Registered Modules: .\build.ps1 -Command list
     4. Preview Execution Plan:  .\build.ps1 -IsoPath "D:\Win11.iso" -Command plan
     5. Execute Full Build:      .\build.ps1 -IsoPath "D:\Win11.iso" -ProfileName balanced
   --------------------------------------------------------------------------------
     Select an option: [G] GUI Studio | [V] Validate | [L] List Modules | [Enter] Exit
   ```
3. Type `G` and press **Enter** to open the GUI, or select any option.

#### Option 3: PowerShell Command Line (`build.ps1`) -- *Power Users & Automation*

Open **Windows PowerShell** as Administrator (press `Win + X` -> select **Terminal (Admin)** or **Windows PowerShell (Admin)**), then navigate to your WIB folder:

```powershell
cd C:\WIB
```

##### 1. Inspect Modules & Validate Profiles (No ISO Required)
```powershell
# List all 14 registered servicing modules, execution order, and risk ratings:
.\build.ps1 -Command list

# Validate profile syntax, schema rules, and inheritance chains:
.\build.ps1 -Command validate -ProfileName balanced
```

##### 2. Preview Changes Without Writing (Dry-Run Plan)
Mounts the image in a temporary sandbox, inspects packages, builds a complete report, and dismounts cleanly without writing changes:
```powershell
.\build.ps1 `
    -IsoPath "C:\ISOs\Win11_26H2_English_x64.iso" `
    -ProfileName balanced `
    -Command plan
```

##### 3. Execute Full Build
Builds your customized Windows 11 installation ISO:
```powershell
.\build.ps1 `
    -IsoPath "C:\ISOs\Win11_26H2_English_x64.iso" `
    -ProfileName balanced `
    -OutputIso "C:\ISOs\Win11_Custom_Balanced.iso"
```

##### 4. Automated Build with Hardware Bypass & Profiles
Use the `balanced` or `lean` profile, which include the `hardware-check-bypass` and `oobe-local-account` modules out-of-the-box to bypass TPM 2.0 / Secure Boot checks:
```powershell
.\build.ps1 `
    -IsoPath "C:\ISOs\Win11_26H2_English_x64.iso" `
    -ProfileName balanced `
    -OutputIso "C:\ISOs\Win11_Custom_Bypass.iso"
```
*(To generate standalone customized `autounattend.xml` answer files, use `.\tools\New-WibUnattend.ps1`)*

---

### Command Line Parameter Reference

| Parameter | What It Does | What to Give (Example) | Required? |
| :--- | :--- | :--- | :--- |
| **`-IsoPath`** | Full path to the clean Windows 11 ISO downloaded from Microsoft. | `"C:\ISOs\Win11_26H2.iso"` | Yes (for build and plan) |
| **`-ProfileName`** | The customization profile preset to apply (`balanced`, `lean`, `adaptive`, `hardening`, `custom-risk`). | `balanced` | No (defaults to `balanced`) |
| **`-OutputIso`** | File path where your finished, customized ISO should be saved. | `"C:\ISOs\Win11_Clean.iso"` | Recommended for builds |
| **`-Command`** | The operation to perform: `build` (default), `plan` (dry-run preview), `validate` (schema check), or `list` (show modules). | `build`, `plan`, `validate`, or `list` | No (defaults to `build`) |
| **`-Gui`** | Launches the desktop graphical user interface. | Switch flag: `-Gui` | Optional |
| **`-NoElevate`** | Runs GUI or preview inspection without prompting for elevation. | Switch flag: `-NoElevate` | Optional |
| **`-WorkDir`** | Custom folder for temporary image mounting and servicing files. | `"D:\Scratch\WibWork"` | No (defaults to `.\work` on NTFS) |
| **`-DownloadOscdimg`** | Automatically downloads and verifies official Microsoft `oscdimg.exe` if not found in ADK. | Switch flag: `-DownloadOscdimg` | Optional |
| **`-ExpectedIsoSha256`** | SHA-256 hash to verify the input ISO has not been modified or corrupted. | `"5A1B2C..."` | Optional |

---

### Step 4: Testing & Installing Your Custom Windows

1. **Always Test in a Virtual Machine First:**
   * Before deploying to physical computers, create a temporary VM in **Hyper-V**, **VirtualBox**, or **Proxmox**.
   * Attach your new ISO (`Win11_Custom_Balanced.iso`) and confirm setup boots to the desktop cleanly.
2. **Flash to USB for Bare-Metal Installation:**
   * Use [Rufus](https://rufus.ie/) or [Ventoy](https://ventoy.net/) to write your customized ISO to a USB flash drive.
   * Boot your target PC from the USB drive to install optimized, bloat-free Windows 11.

---

## Built-in Profiles

| Profile | Target Scenario | AppX Packages | Telemetry / Diagnostics | Security Controls | Rollback Scope |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`balanced`** | Workstations & daily use | Removes consumer bloat | Configured to Basic / Required (`AllowTelemetry = 1`) | Preserved intact | In-image registry journal (`journal.reg`); AppX re-installable via Store |
| **`lean`** | Lab VMs & high-performance | Strips non-essential inbox apps | Minimized per edition policy | Preserved intact | In-image registry journal; AppX re-installable via Store |
| **`adaptive`** | Hardware-aware baseline | Dynamic package selection | Tuned to detected hardware | Preserved intact | In-image registry journal |
| **`hardening`** | High-security & compliance | Minimal attack surface | Auditing & restrictive baselines | Enhanced defensive policies | In-image registry journal |
| **`custom-risk`** | Isolated research environments | Aggressive package removal | Experimental | High-impact opt-ins (requires `-AcceptRisk`) | Partial / Advanced |

---

## Security, Credentials & Operational Boundaries

1. **Unattended Credentials Disclosure:**  
   Microsoft Windows Setup answer files (`autounattend.xml`) store passwords in reversible Base64 obfuscation (`<PlainText>false</PlainText>`), **not cryptographic encryption**. Anyone with read access to the installation media or the answer file can decode the password.  
   * WIB copies credentials directly from unmanaged memory buffers (`SecureStringToGlobalAllocUnicode`) to minimize CLR string retention during XML assembly.  
   * **Always use unique, temporary setup credentials.**  
   * Never commit answer files to public repositories.  
   * Rotate or delete the initial local administrator account immediately after installation.
2. **Handle-Bound File Security:**  
   WIB implements kernel handle-bound deletions and strict DACL inheritance verification (`Protect-WibSensitiveFileAcl`) on recovery ledgers (`recovery-state.json`) and answer files to defend against concurrent path redirection and unowned file substitution.
3. **High-Impact Controls Require Explicit Opt-In:**  
   Features that disable security controls (such as UAC prompt suppression or core isolation alterations) are strictly segregated and require the `-AcceptRisk` switch.
4. **Isolated Servicing:**  
   WIB operates exclusively on offline image mounts. It makes no configuration changes to your running host operating system.

---

## Verification & Test Evidence

Run the automated test suites from an elevated PowerShell session:

```powershell
# Run all 51 smoke test suites (655 assertions)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\smoke.ps1

# Run all 22 behavioral release gates (G1 through G22)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\verify-gates.ps1 -Gate All
```

> [!NOTE]
> Passing automated tests validates parser correctness, registry injection logic, recovery mechanics, and file security. It does not substitute for end-to-end VM boot and OOBE validation.

---

## Project Documentation

* [Getting Started Guide](docs/GETTING_STARTED.md) &mdash; Detailed installation, ISO acquisition, and VM test instructions.
* [Compatibility Matrix](docs/COMPATIBILITY.md) &mdash; Host OS, target builds, and architectural boundaries.
* [GitHub Launch & SEO Checklist](docs/GITHUB_AND_SEO_LAUNCH_CHECKLIST.md) &mdash; Repository configuration, metadata, and launch guide.
* [Contributing Guide](CONTRIBUTING.md) &mdash; Coding conventions, PowerShell 5.1 compatibility, and PR workflow.
* [Security Policy](SECURITY.md) &mdash; Vulnerability disclosure and security scope.
* [Code of Conduct](CODE_OF_CONDUCT.md) &mdash; Contributor Covenant v2.1.
* [Changelog](CHANGELOG.md) &mdash; Version history and release notes.

---

## License & Attribution

This project is licensed under the [MIT License](LICENSE).  
Third-party component notices and attributions are documented in [NOTICE](NOTICE).
