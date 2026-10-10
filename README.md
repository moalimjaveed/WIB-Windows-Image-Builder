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

## Quick Start

```powershell
# Clone the repository
git clone https://github.com/moalimjaveed/WIB-Windows-Image-Builder.git
cd WIB-Windows-Image-Builder
```

### 1. Inspect Modules and Validate a Profile

Commands that only inspect or validate profiles do not require elevation:

```powershell
# List all registered modules, execution order, and risk tiers
.\build.ps1 -Command list

# Validate profile syntax, schema, and inheritance chain
.\build.ps1 -Command validate -ProfileName balanced
```

### 2. Preview Build Plan (Dry Run)

Run in an **elevated Administrator** PowerShell session. Planning mounts the WIM in a temporary workspace, inspects installed packages and features, generates a report, and dismounts without writing changes to the source media or generating an ISO:

```powershell
.\build.ps1 `
    -IsoPath "C:\ISOs\Win11_26H2_English_x64.iso" `
    -ProfileName balanced `
    -Command plan
```

### 3. Build Customized Media

Build an optimized Windows installation ISO to a separate output path:

```powershell
.\build.ps1 `
    -IsoPath "C:\ISOs\Win11_26H2_English_x64.iso" `
    -ProfileName balanced `
    -OutputIso "C:\Images\Win11_Custom_Balanced.iso" `
    -ExpectedIsoSha256 "<KNOWN_MICROSOFT_SHA256>"
```

> [!TIP]
> **Integrity vs. Provenance:** `-ExpectedIsoSha256` verifies cryptographic *integrity* against the digest you supply. To establish *provenance* (authenticity), obtain the expected SHA-256 hash independently from an authoritative Microsoft release bulletin (such as the Microsoft Evaluation Center or MSDN subscriber portal). Copying a hash from an unverified local ISO file only proves file consistency, not authenticity.

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
