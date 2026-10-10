# Windows Image Builder (WIB) - Compatibility Matrix

This document defines the supported Windows versions, host requirements, module support tiers, and architectural capabilities for **Windows Image Builder (WIB)**.

---

## 1. Host Execution Requirements

| Host Requirement | Minimum Version | Recommended Version | Notes |
|:---|:---|:---|:---|
| **Operating System** | Windows 10 (21H2+) / Windows 11 | Windows 11 (26H2 latest & recommended) | Offline DISM image servicing host |
| **PowerShell Engine** | Windows PowerShell 5.1 (Desktop) | Windows PowerShell 5.1 / PowerShell 7.4+ | 100% native PS 5.1 compatible; zero third-party dependencies |
| **Execution Rights** | Local Administrator (Elevated) | Elevated Administrator | Required for DISM filter drivers and offline registry hive mounting (`reg load`) |
| **DISM Module** | Windows ADK DISM / In-box DISM | Latest In-box DISM (10.0.26100+) | Provides `Mount-WindowsImage`, `Save-WindowsImage`, `Dismount-WindowsImage` |
| **Packaging Tool** | `oscdimg.exe` (ADK 10 / Symbol Server) | Windows 11 ADK Deployment Tools | Verified via Authenticode (`O=Microsoft Corporation`) and SHA-256 |
| **Free Work Storage** | 25 GB | 40+ GB SSD / NVMe | Staging, index expansion, WIM compression scratch |

---

## 2. Target Windows Build Support Matrix

| Target Edition / Release | Build Number | Architecture | Status | Servicing Notes |
|:---|:---|:---|:---|:---|
| **Windows 11 21H2** | 22000.x | x64, ARM64 | **Supported** | Baseline Windows 11 release. Standard AppX and optional features. |
| **Windows 11 22H2** | 22621.x | x64, ARM64 | **Supported** | Introduces revised TaskCache layout and updated inbox UWP components. |
| **Windows 11 23H2** | 22631.x | x64, ARM64 | **Supported** | Validated with balanced, lean, adaptive, and hardening profiles. |
| **Windows 11 24H2** | 26100.x | x64, ARM64 | **Supported** | Native ARM64 Prism compatibility; requires strict LUA retention for System Components. |
| **Windows 11 26H2** | 26300.x | x64, ARM64 | **Supported (Latest & Recommended)** | Validated layout compatibility; latest Windows 11 general availability release. |
| **Windows Server 2022 / 2025** | 20348.x / 26100.x | x64 | **Supported** | Desktop Experience images; AppX module automatically skips headless server editions. |

---

## 3. Module Compatibility & Safety Notes

### AppX Removal (`appx-removal`)
- **Safety Rails:** Built-in protected list preserves `Microsoft.WindowsStore`, `Microsoft.StorePurchaseApp`, `Microsoft.DesktopAppInstaller`, `Microsoft.Windows.ShellExperienceHost`, `Microsoft.UI.Xaml`, and `Microsoft.VCLibs`.
- **Validation Guard:** Prevents wildcard `*` or short `< 3` character matches to protect critical OS dependencies.
- **24H2 Note:** Microsoft shifted several built-in apps to system components; WIB matches only scanned inbox provisioned packages.

### Edge & WebView2 Removal (`edge-removal`)
- Edge browser and update executables (`Microsoft\Edge`, `EdgeUpdate`, `EdgeCore`) are permanently removed.
- **WebView2:** Maintained by default (`removeWebView: false`). Applications such as Microsoft Teams, Widgets, and third-party modern apps rely on WebView2. Setting `removeWebView: true` is strictly opt-in.
- **Scheduled Tasks:** Cleans both `TaskCache\Tree\Microsoft\EdgeUpdate` and corresponding GUID registrations in `TaskCache\Tasks`.

### OneDrive Removal (`onedrive-removal`)
- Removes offline staging binaries (`OneDriveSetup.exe` in `System32` and `SysWOW64`).
- Purges user auto-start run keys from both `DEFAULT` (`Users\Default\NTUSER.DAT`) and `NTUSER` hives using `DeleteValue`.
- Enforces `DisableFileSyncNGSC = 1` policy.

### High-Risk Security Opt-Ins (`30-security-optins.ps1`)
- **UAC Prompt Suppression (`uac-off`):** Configures `ConsentPromptBehaviorAdmin = 0` (silent elevation) while retaining `EnableLUA = 1`. This preserves modern packaged Windows 11 applications (Settings, Store, Calculator). Full LUA disablement is available only via explicit `disableLua: true`.
- **Mitigations / Defender / Firewall:** Excluded from built-in profiles (`balanced`, `lean`, `adaptive`, `hardening`). Requires explicit `-AcceptRisk` switch.

---

## 4. Unattended Setup & Bypass Mechanisms

| Mechanism | Strategy | Compatibility | Notes |
|:---|:---|:---|:---|
| **TPM / Secure Boot / RAM Bypass** | `LabConfig` registry injection in `windowsPE` pass | Win 11 (21H2 - 24H2) | Default: Disabled (opt-in only per Safety Rule 5); injected only when `-HardwareBypass` is explicitly passed |
| **Network Requirement (OOBE Bypass)** | `BypassNRO = 1` registry + unattend `HideOnlineAccountScreens` | Win 11 (21H2 - 24H2) | Allows offline local administrator account creation |
| **Credential Hygiene & Exposure Risk Gate** | Centralized risk gate, mandatory ACL helpers, pre-write & pre-replace NTFS ACL lockdown, transactional DACL+SHA-256 rollback, WSIM `PasswordHash` validation & unmanaged `SecureString` byte copy | All Builds | Requires explicit `-AcceptCredentialExposureRisk` for any embedded credentials or `-AutoLogon`; `-TestOnly` never waives security gates and is restricted strictly to `[System.IO.Path]::GetTempPath()` with an embedded test-fixture warning banner; fails closed if mandatory ACL helpers (`Test-WibVolumePersistentAclSupport`, `Protect-WibSensitiveFileAcl`, `Get-WibAclFingerprint`, `Get-WibFileDaclSnapshot`, `Restore-WibFileDaclSnapshot`) are unavailable; rejects empty or whitespace-only `-PasswordHash` when bound and validates `-PasswordHash` via `Test-WibUnattendPasswordHash` against the Microsoft WSIM `<PlainText>false</PlainText>` UTF-16LE `<password>Password` Base64 format in a zero-scrubbed byte buffer; verifies destination volume supports `FILE_PERSISTENT_ACLS` (`GetVolumeInformationW`), locks down a 0-byte staging file (`Protect-WibSensitiveFileAcl`) *before* writing XML payload bytes, captures a pre-existing `-Force` target's SHA-256 and DACL snapshot (`Get-WibFileDaclSnapshot` / `Get-WibAclFingerprint`) and locks down its DACL *before* `[System.IO.File]::Replace`, and on any pre- or post-replace failure restores and verifies both the original bytes (SHA-256) and original DACL fingerprint before removing `.bak` (preserving `.bak` on `CRITICAL ROLLBACK FAILURE`); copies `SecureString` UTF-16LE bytes directly from unmanaged memory (`SecureStringToGlobalAllocUnicode`) in default obscured mode without allocating an intermediate plaintext managed `[string]` (while noting assembled XML strings and plaintext CLI string parameters remain subject to CLR garbage collection) |

---

## 5. Recovery Lifecycle & Architectural Boundaries

| Phase / State | Resumable? | Mechanism | Boundary Notes |
|:---|:---|:---|:---|
| **Preflight / Mount** | Yes | Pre-DISM recovery validation | Verifies tool version, effective profile canonical hash, source WIM baseline hash, and workspace integrity before locking |
| **Servicing Stages (1-7)** | Yes | Stage checkpoints (`Save-WindowsImage -Append`) | Each completed stage appends a committed WIM index with authoritative provenance; `-Resume` rolls back dirty mounts to the last committed index |
| **Finalization (`finalizing`)** | No | Clean rebuild required | Intermediate servicing changes are being saved to disk; interrupted finalization invalidates checkpoint monotonicity |
| **Post-Export Packaging (`post-export`)** | No | Clean rebuild required | `dism /Export-Image` compresses and exports the servicing image into the final WIM format. Packaging failures at or after this stage permanently alter the workspace layout; crash recovery is supported through servicing checkpoints, and post-export packaging failures require a clean rebuild without `-Resume` |

---

## 6. Trusted Recovery-Ledger Model & HMAC Boundaries

WIB implements cryptographic HMAC-SHA256 authentication (`TransactionMac`) bound to an ephemeral 32-byte secret (`TransactionAuthSecret`) generated per append transaction.

### Threat Model & Scope
- **Within the Workspace Boundary:** The HMAC cryptographically binds all 11 execution context properties (`TransactionId`, `ActiveCheckpointId`, `Stage`, `ProfileHash`, `EffectiveSha256`, `PreAppendWimSha256`, `PreAppendPhysicalCount`, `ExpectedAppendedIndex`, `RunId`, `ToolVersion`, `MountedIndex`) to the authoritative recovery ledger (`recovery-state.json`) before DISM physical append mutations begin.
- **Protection Provided:** Detects interrupted crash states across all 7 persistence fault-injection boundaries, prevents uncoordinated marker mutations, prevents stale marker re-use across distinct build runs, and guarantees deterministic orphan index reconciliation without marker forgery.
- **Explicit Trust Boundary & File Permissions:** Operates under a *trusted recovery-ledger model*. `Set-WibDurableJsonFile` requires `Test-WibVolumePersistentAclSupport` and `Protect-WibSensitiveFileAcl` to exist and succeed when `-ProtectAcl` is enabled, applies protected NTFS ACLs (`CurrentUser`, `BUILTIN\Administrators`, `NT AUTHORITY\SYSTEM` only, inheritance disabled) to a 0-byte staging file *before* writing JSON payload bytes for `recovery-state.json`, `checkpoint.transaction.json`, and `terminal-state.json`, captures any pre-existing target file's SHA-256 and DACL snapshot (`Get-WibFileDaclSnapshot` / `Get-WibAclFingerprint`) and locks down its DACL *before* `[System.IO.File]::Replace`, and retains the `.bak` backup across post-replacement ACL and JSON read-back verification so any failure restores and verifies both the prior file bytes (SHA-256) and prior DACL fingerprint before removing `.bak` (preserving `.bak` on `CRITICAL ROLLBACK FAILURE`). `Lock-WibWorkspace` / `Invoke-WibBuild` enforce the same restricted ACLs on `$WorkDir`, `$mountDir`, `$isoDir`, `$reportDir`, and `build.log`. If an adversary already possesses elevated local administrator write access to mutate both `recovery-state.json` and `checkpoint.transaction.json` simultaneously, this mechanism does not claim to serve as an external cryptographic root-of-trust (such as a hardware TPM or external PKI timestamp authority).

---

## 7. Supply Chain & Dependency Security

WIB adheres to a strict zero-third-party-runtime dependency posture:
- **Zero Third-Party PowerShell Modules:** WIB runtime code relies exclusively on Microsoft built-in PowerShell 5.1 cmdlets (`Dism`, `Microsoft.PowerShell.Utility`, `Microsoft.PowerShell.Management`).
- **First-Party Tooling Only:** DISM (`dism.exe`), `reg.exe`, and `oscdimg.exe` (from the Windows ADK). First-party system tools (`dismExe`, `regExe`, `compactExe`, `takeownExe`, `icaclsExe`, `attribExe`) are strictly resolved to approved absolute paths under `%SystemRoot%\System32` (or `Sysnative` for 32-bit processes on 64-bit OS) via `Resolve-WibTrustedNativeTool`, and in-process mocks are strictly confined behind `$script:WibAllowNativeToolMocks = $true` (WIB-021).
- **Oscdimg Authenticode Verification:** `Resolve-WibOscdimg` verifies that `oscdimg.exe` is signed with a valid Microsoft Corporation Authenticode signature (`O=Microsoft Corporation`) and calculates its SHA-256 digest into `manifest.json`.
- **CI Dependency Pinning:** GitHub Actions workflows pin all actions to immutable full commit SHAs (e.g. `actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683`). `PSScriptAnalyzer` is pinned to version `1.22.0` installed from `-Repository PSGallery` without `-SkipPublisherCheck` to enforce catalog publisher verification.

---

## 8. Filesystem Boundary, Reparse Point Containment & Cryptographic Source Invariance

To defend against path traversal, symlink redirection, and out-of-band mutation:
- **Lexical & Namespace Containment:** Confined paths must reside strictly within their designated base directory; UNC paths (`\\server\share`), Win32 device namespace paths (`\\?\`, `\\.\`), volume drive roots (`C:\`), and NTFS Alternate Data Streams (`file.xml:stream`) are rejected fail-closed.
- **Fail-Closed Kernel Handle, 64-Bit NTFS File ID & Node-by-Node Confined Tree Deletion:** `Test-WibPathContainment` inspects all path segments up to `$BaseDir` for `FileAttributes.ReparsePoint` and verifies final kernel handle path containment via Win32 `CreateFileW` + `GetFinalPathNameByHandleW`. Furthermore, `Get-WibKernelNodeIdentity` (`WibKernelPathHelper::GetKernelNodeIdentity`) uses `CreateFileW(FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT)` + `GetFileInformationByHandle` to inspect 64-bit NTFS File IDs (`VolumeSerialNumber:FileIndexHigh:FileIndexLow`) without following junctions and strictly fails closed (no `OK:FALLBACK` downgrade) if the kernel helper is unavailable. `Remove-WibConfinedTreeSafe` (used by `Remove-WibImagePaths`) records 64-bit NTFS File IDs during non-following tree enumeration and re-verifies each node's 64-bit File ID and non-reparse status immediately before unlinking each file (`[System.IO.File]::Delete`) and each bottom-up empty directory (`[System.IO.Directory]::Delete($dPath, $false)`), and `Assert-WibCompactTargetIdentity` in `lib/Compact.ps1` enforces `Assert-WibNoReparsePointsInTree` + 64-bit NTFS File ID verification in `Invoke-WibFolderCompression`, `Invoke-WibFolderDecompression`, and `Set-WibCompactWatcher` (`'add'`) with no direct `[WibKernelPathHelper]` fallback.
- **Target & Parent Identity Binding with Reparse Point Rejection:** In `Set-WibDurableJsonFile` and `tools/New-WibUnattend.ps1`, parent directory and destination paths are rejected if they are reparse points or junctions, and parent/target node identities are captured and re-verified immediately prior to replacement (WIB-023). Pre-commit backup deletion zeroing is eliminated, preserving backup integrity until transaction commit, and pre-commit rollback validates backup SHA-256 before restoring and preserves `.bak` on corruption (WIB-022).
- **Canonical DACL Integrity Verification:** `Assert-WibSensitiveAclIntegrity` validates that sensitive files and directories have inheritance protected, contain no unauthorized principals (e.g. `BUILTIN\Users`, `Everyone`), and grant `FullControl` Allow rules strictly to `CurrentUser`, `BUILTIN\Administrators` (`S-1-5-32-544`), and `NT AUTHORITY\SYSTEM` (`S-1-5-18`) (WIB-024).
- **Separated Compression Safety & Error Contracts:** `Invoke-WibFolderCompression` separates `-Force` (`compact.exe /F` recompression) from `-OverrideSafetyChecks` (DirectStorage / system path exclusions) and `-ContinueOnNativeError` (suppressing nonzero `compact.exe` exit exceptions while always returning `Success = $false` and `State = 'failed'`).
- **Atomic Rollback:** Published ISO replacement uses Win32 `[System.IO.File]::Replace` inside an exclusive publication lock (`$OutputIso.publock`) to guarantee atomic replacement without filesystem deletion windows.
- **Cryptographic Source-ISO TOCTOU Proof & Staged WIM Binding:** `lib/Engine.ps1` verifies both metadata (`Length`, `LastWriteTimeUtc`) and full cryptographic SHA-256 invariance (`$postMountIsoSha -eq $preMountIsoSha`) *after* `Mount-DiskImage` completes while the Windows kernel holds the mounted disk image locked against writes. Furthermore, staged `sources\install.wim` is cryptographically verified against the mounted ISO volume's `sources\install.wim`.
- **Resource Telemetry Scope Attribution & Structured Child-Process Telemetry:** `manifest.telemetry` records `powershellPeakWorkingSetBytes`, `memoryMeasurementScope = 'powershell-host-process-only'`, `childProcessNote`, and structured `nativeToolInvocations` (`dismExe`, `oscdimgExe`, `regExe`, `compactExe`, `takeownExe`, `icaclsExe`, `attribExe` with `invocations`, `totalElapsedMs`, `maxProcessWorkingSetBytes`, `workingSetMeasurementStatus`, `lastExitCode`, `launchFailures`, and `lastInvocationUtc`) collected via `Invoke-WibNativeTool` with accurate start-failure accounting (WIB-025).

---

## 9. Physical Release Gate & Hardware Validation Status

- **Status:** **STRONG ENGINEERING CORE / PHYSICAL RELEASE GATE BLOCKED**.
- **Tested & Proven:** Logic correctness, Pester/smoke test suites (618 assertions across 47 suites), 18 behavioral release gates (`G1`–`G18`), elevated DISM scratch-WIM checkpoint/rollback (`tests/integration-dism.ps1`), 7-boundary persistence fault-injection matrix, out-of-process lock recovery, and multi-process crash resumption.
- **Unproven Physical Gate (`WIB-001`):** The end-to-end physical production cycle—mounting a real multi-gigabyte Microsoft Windows 11 ISO, live offline registry and component servicing, DISM image export, oscdimg ISO packaging, and booting in a clean Hyper-V VM to reach the OOBE desktop (`validationRecord.vmBootValidated = $false` until proven)—remains the formal release blocker before production certification.
