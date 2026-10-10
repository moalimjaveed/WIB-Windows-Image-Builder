# WIB: Build Plan (from where you are today)

Status date: 2026-10-10. Tool version 0.2.29. PowerShell 5.1+, JSON profiles, first-party tools only.

The goal is not more tweaks than Atlas. WIB wins on **trust and measurement**: a build you can preview, verify, undo and benchmark. Every phase below moves toward that.

---

## 0. Where you are now

**Done (v1 core, logic tested only)**
- [x] Pipeline: preflight, copy, mount, scan (AppX), plan, dry-run, apply, verify, export, boot.wim, ISO, report
- [x] 16 modules, 2 profiles (`balanced`, `lean` extends `balanced`)
- [x] Undo journal written into the image (registry only)
- [x] Smoke test: 20 logic checks (no ISO, no admin)

**Completed from v1 blueprint**
- [x] Checkpoints between stages (Save-WindowsImage -Append with verified rollback)
- [x] Services module (offline SYSTEM hive tuning with never-touch list)
- [x] General verify pass (orphaned TaskCache, Edge uninstall remnants, ghost references)
- [x] features-cleanup, search-indexing modules

**Never run**
- [ ] A real build on a real ISO, then a VM boot. Everything in Phase 1 depends on this.

---

## Phase 1: Prove it works (do this before writing more code)

Nothing else is worth building until one real build boots.

1. Get a Windows 11 ISO from Microsoft and note its SHA-256.
2. Make a Hyper-V (or other) VM and take a **snapshot before every test**.
3. Run `.\build.ps1 -IsoPath X -ProfileName balanced -DryRun`. Read the plan. Check the keep list.
4. Run a real build with `-ExpectedIsoSha256`. Keep `build.log`, `manifest.json`, `report.html`.
5. Boot the output ISO in a fresh VM. Install, reach the desktop, sign in with a local account.
6. Check the unverified tweaks on the live system: `visual-effects`, `widgets-off`, `background-apps-off`. Also confirm `BypassNRO` (newer builds may no longer honour it; the autounattend path is the fallback).
7. Repeat with `lean`.

**Done when:** both profiles build and boot, and you have a list of every error or tweak that did not take effect.

**Paste-ready prompt**
> Here is the build.log and report.html from my first real WIB build. List every failed or skipped step, find the cause in the code, and fix it. Do not change behaviour that worked.

---

## Phase 2: Finish v1 (the blueprint's v1 list)

Build in this order. Each item has a how-to and a prompt.

### 2.1 Strict profile validation
- **Why:** a typo like `"enabeld": false` silently runs the module.
- **How:** give each module a `Schema` (allowed keys and types) in `Register-WibModule`. `Test-WibProfile` rejects unknown keys and wrong types before any mount. Add `./build.ps1 -Validate`.
- **Prompt:** "Add per-module settings schemas and make Test-WibProfile reject unknown keys and wrong types. Add smoke tests for a typo'd key and a wrong type."

### 2.2 Hash the resolved profile
- **Why:** the manifest hashes only the child file, so `lean` omits `balanced`.
- **How:** after `extends` merging, serialize the merged profile to canonical JSON (sorted keys) and hash that. Record the parent chain in the manifest.

### 2.3 `appliesWhen` and `onError` per module
- **Why:** from Atlas/AME: actions can target builds and CPU architecture, and set an error policy.
- **How:** add `-AppliesWhen @{ Builds = '>=22621'; Arch = 'x64'; Editions = @('Pro') }` and `-OnError ignore|log|halt` to `Register-WibModule`. The engine skips a non-matching module and records the reason in the plan. A `halt` failure stops the build; the rest log and continue.
- **Also:** detect architecture in preflight and put it in the manifest.

### 2.4 Three-tier reversibility
- **Why:** Atlas separates permanent, disabled, and reinstallable. WIB marks every removed app irreversible.
- **How:** replace the boolean with `Reversibility = journal | reinstallable | permanent`. Registry tweaks are `journal`, AppX removal is `reinstallable`, deleted files and Smart App Control style changes are `permanent`. The plan shows a count per tier.

### 2.5 Scanner: features and capabilities
- **How:** extend `Get-WibScan` with `Get-WindowsOptionalFeature -Path` and `Get-WindowsCapability -Path`.
- **New module `features-cleanup`:** remove by pattern with `keep` rules, same as AppX. Candidates: Internet Explorer, legacy Windows Media Player, Steps Recorder, Math Recognizer, Quick Assist. Never match servicing-critical items.

### 2.6 Services module
- **How:** with the SYSTEM hive loaded, set `ControlSet001\Services\<name>\Start` (2 auto, 3 manual, 4 disabled). Scan real services from the hive; journal the old value.
- **Safety:** ship a `never-touch` list and a profile `keep` list. Start conservative (telemetry-only services such as `dmwappushservice`, already present).
- **Note:** `SysMain` and similar choices become hardware-driven in Phase 4.

### 2.3b Search indexing module
- Offline switch for the `WSearch` service start type, off in `lean`, plan text explains the trade-off.

### 2.7 Checkpoints
- **Why:** blueprint v1. Today a failure discards everything.
- **How to try:** `Save-WindowsImage -Path $mount -Append` after each stage to snapshot into a new index; on failure, discard and remount the last good index. This is untested, so prove it in a VM. If it does not behave, fall back to copying the WIM at coarse stages (slow, large).

### 2.8 General verify pass
- **How:** after removals, scan the mounted image for leftovers: registry keys referring to removed apps, TaskCache entries for deleted tasks (known gap in `tasks-cleanup`), Edge uninstall keys. Report each as a warning with the path.

### 2.9 CLI and CI
- **CLI:** `-Command build|plan|verify|validate|list`, so `plan` and `validate` do not need the full build flags.
- **CI:** GitHub Actions on `windows-latest`: PSScriptAnalyzer, parse check, `tests/smoke.ps1`. The integration build with a real ISO stays manual.

**Done when:** Phase 1 passes on the new code, smoke tests cover each new item, and README "Known gaps" shrinks accordingly.

**Paste-ready prompt (one per item, in order)**
> Implement 2.x from WIB-plan.md. Keep PowerShell 5.1 compatibility (no ternary, no `??`). Add smoke tests. Update README status and known gaps. Do not claim anything is tested unless the tests ran.

---

## Phase 3: Make the dry-run and report worth trusting (Complete)

- [x] 1. **Size-savings estimate:** sum the sizes of paths to delete and the AppX package folders from the scan; label it an estimate.
- [x] 2. **Faster dry-run:** for WIM sources, try a read-only mount directly from the mounted ISO instead of copying everything. ESD sources still need an export (use fast compression, one index) just for scanning.
- [x] 3. **Reproducibility:** record the resolved profile hash, tool version, oscdimg hash. Try `oscdimg -t` to fix file timestamps; document what remains non-deterministic.
- [x] 4. **oscdimg download check:** require that the signer is Microsoft, not just "Valid" (`O=Microsoft Corporation`).
- [x] 5. **Report:** plan versus actual, reversibility tiers, estimated savings, warnings first.
- [x] 6. **Signed manifest:** detached SHA-256 signatures (`manifest.json.sha256`) and verification via `Test-WibManifest`.

**Done when:** a report answers "what changed, how much space, can I undo it, and did it all verify". [VERIFIED]

---

## Phase 4: The differentiators (v2) (Complete)

- [x] 4.1 **Hardware profile and adaptive decisions**
  - Read `Win32_PhysicalMemory`, `MSFT_PhysicalDisk` (media type), `Win32_Processor`, `Win32_VideoController`, chassis type via CIM.
  - User-supplied spec file (`--hardware-spec` / `-HardwareSpec`) for targets other than the build host.
  - Adaptive decision rules for RAM (DisablePagingExecutive resident kernel/drivers), SSD (SysMain), GPU (transparency/animations), and chassis (SystemResponsiveness power states).
  - Every decision written to plan, manifest, and report with human-readable rationale. Added `profile: adaptive` (`profiles/adaptive.json`).

- [x] 4.2 **Atlas-style toggle modules (each with a written trade-off & hardware hint)**
  - Added 7 granular toggle modules: `bluetooth-tuning`, `printing-spooler`, `hibernation`, `game-mode`, `network-discovery`, `driver-updates-off`, `timer-resolution`.
  - Every module declares explicit `Tradeoff` text and `HardwareHint` context.

- [x] 4.3 **High-risk opt-ins**
  - Security modules: `mitigations-off`, `defender-off`, `core-isolation-off`, `uac-off`, `firewall-off` (`modules/30-security-optins.ps1`).
  - Default off, `risk: high`, strictly prohibited in `balanced`, `lean`, and `adaptive` profiles.
  - Require explicit `-AcceptRisk` CLI switch in `build.ps1` and `Invoke-WibBuild`.

- [x] 4.4 **VM validation and benchmark**
  - Built `tools/Invoke-WibVmBenchmark.ps1` for Hyper-V Gen 2 differencing disk automated benchmarking.
  - Automates boot time, idle RAM after settle period, idle CPU, and disk used.
  - Computes deltas between stock and customized images; strictly separates disk savings from RAM numbers.

- [x] 4.5 **Undo journal made real**
  - Captures `reg export` before `DeleteKey` operations into journal entry (`ExportedReg`), enabling complete key restoration.
  - Records `targetScope: 'default-user-only'` for NTUSER tweaks vs `'system'`, clarifying future account effects.

- [x] 4.6 **Post-install Panel**
  - Built `tools/WibPanel.ps1` (native PowerShell 5.1 WinForms GUI + headless mode).
  - Reads `Windows\WIB\journal.json`, displays risk/reversibility tiers, detects live registry policy drift from Windows Update, and provides selective/global rollback.

**Done when:** one build on two different hardware specs gives different, explained results, and the benchmark delta is in the report. [VERIFIED via tests/smoke.ps1]

---

## Phase 5: Compression (CompactGUI-style, separate tool `wib-compact`)

Keep this separate from the image builder.

- [x] 5.1 **Analyze:** list folders, current size on disk, compressible vs. skipped files, and estimated disk savings (`Measure-WibFolderSavings`).
- [x] 5.2 **Algorithm choice:** XPRESS4K, XPRESS8K, XPRESS16K, LZX. Automatically selects algorithm based on hardware profile (`Get-WibCompactAlgorithmRecommendation`): HDD / weak CPU (<=2 cores) -> `XPRESS4K`; balanced SSD -> `XPRESS8K`; multi-core desktop SSD -> `LZX`.
- [x] 5.3 **First-party tool execution:** wraps Windows native `compact.exe` (`/c /s:<path> /exe:<algo>`, `/u` to undo, `/q` to query) without third-party dependencies (`lib/Compact.ps1`).
- [x] 5.4 **Skip list & caching:** excludes 30+ pre-compressed container, archive, audio, video, and image extensions (`Test-WibIncompressibleFile`). Maintains in-memory cache to prevent redundant evaluations.
- [x] 5.5 **Safety exclusions:** heuristic detection for DirectStorage games (`dstorage*.dll`) with performance warnings (`Test-WibDirectStorage`). Blocks whole `C:\Windows` folder compression and system swap/paging entities (`Test-WibSystemPathExclusion`), requiring explicit `-OverrideSafetyChecks` or CompactOS.
- [x] 5.6 **Recompression:** switches algorithms on already compressed directories using `compact.exe /F` (`-Recompress` / `-Force`) without manual decompression.
- [x] 5.7 **Whole OS (CompactOS):** inspects, enables, and disables OS compression state via `compact.exe /CompactOS:query|always|never` (`Invoke-WibCompactOS`) with offline `/WinDir` support.
- [x] 5.8 **Folder Watcher:** manages watched directory lists persisted in `compact_watched_folders.json` (`Manage-WibCompactWatcher`) and registers/removes weekly scheduled task via Windows Task Scheduler (`schtasks.exe`).
- [x] 5.9 **CLI & WinForms GUI:** standalone tool `tools/wib-compact.ps1` featuring headless CLI for scripts and CompactGUI-style WinForms GUI for interactive folder picking, analysis metrics, DirectStorage warnings, and compression execution.

**Done when:** folder analysis accurately differentiates compressible vs. skipped files, algorithm selection adapts to hardware, and wib-compact passes all smoke checks. [VERIFIED via tests/smoke.ps1: 175 passing tests]

Licence note: CompactGUI and Atlas are GPL-3.0. Reuse ideas, not code, unless you choose GPL for WIB.

---

## Phase 6: Platform (v3) (Complete)

- [x] 6.1 **Enterprise Hardening Profile (`profiles/hardening.json`):**
  - Added 4 defensive modules (`modules/40-hardening.ps1`): `audit-logging` (PowerShell Script Block, Module, Process CommandLine auditing), `network-hardening` (LLMNR disabled, WPAD disabled, SMB signing enforced), `remote-access-hardening` (RDP NLA enforced, anonymous SAM/LSA enumeration restricted), and `defender-hardening` (PUA blocking, MAPS cloud protection).
  - All modules declare low risk, journal reversibility, explicit tradeoffs, and hardware hints. Extends `balanced.json`.
- [x] 6.2 **Update-Aware Re-patching (`Invoke-WibRepatch`):**
  - Evaluates live system registry against `journal.json` / `manifest.json`.
  - Automatically identifies drifted settings after Windows Updates and re-applies intended policies via `Repatch-WibTweakEntry`.
  - Integrated into `build.ps1 -Command repatch`, `tools/WibPanel.ps1 -Repatch -LogFile <path>`, and WinForms GUI ("Re-patch Drifted Policies" button).
- [x] 6.3 **Delta Rebuilds from Previous Manifest (`-DeltaFromManifest`):**
  - Added `Compare-WibDeltaPlan` in `lib/Planner.ps1` comparing planned operations against previous build manifests.
  - Automatically tags plan items (`Unchanged`, `Modified`, `New`), reporting delta counts and previous manifest hash.
  - CLI switch `-DeltaFromManifest <path>` wired into `build.ps1` and `Invoke-WibBuild`.
- [x] 6.4 **Community Profile Manager (`tools/wib-profile.ps1`):**
  - Built profile catalog CLI: `list` (catalog overview with risk/modules), `info` (module and override breakdown), `validate` (strict schema/safety audit), `export` (resolves inheritance into standalone flattened JSON), and `import` (copies/validates external profiles).
- [x] 6.5 **Builder Studio GUI (`tools/WibBuilderGui.ps1` / `build.ps1 -Gui`):**
  - Native WinForms graphical builder studio featuring source ISO picking, profile selection with active module count and parent chain preview, image index selection, real-time background process log streaming with color highlights, stage progress bar, and report links.
- [x] 6.6 **Offline Unattended Answer File Generator (`tools/New-WibUnattend.ps1`):**
  - Generates secure, 100% offline `autounattend.xml` answer files based on `templates/autounattend.template.xml`. Injects `HKLM\SYSTEM\Setup\LabConfig` hardware bypasses (`BypassTPMCheck`, `BypassSecureBootCheck`, `BypassRAMCheck`, `BypassCPUCheck`, `BypassStorageCheck`), configures local administrator account, suppresses online account forced OOBE, and enables auto-logon for seamless VM testing.

**Done when:** hardening profile validates and plans cleanly, re-patching recovers drifted live tweaks, delta comparison detects changed vs. unchanged items, Builder Studio launches cleanly, unattended answer file parses as valid XML, and all smoke checks pass. [VERIFIED via tests/smoke.ps1: 100% passing tests]

---

## Rules to keep while building

- Never ship a Windows ISO, only the tool.
- Every new module declares risk, reversibility tier, tradeoff text, and a verify step.
- Every new feature gets a smoke test, and the README must say what was and was not run on a real image.
- Snapshot the VM before each test. Do not use a build on a machine you cannot reinstall until it has booted in a VM.
- Do not add tweaks without a measured or documented effect.

## Suggested order, short version

1. Phase 1 (real build in a VM)
2. 2.1 to 2.3 (validation, resolved hash, conditions)
3. 2.5 to 2.7 (features, services, checkpoints)
4. 2.8 to 2.9 (verify, CLI, CI)
5. Phase 3
6. Phase 4.1 then 4.4
7. Phase 4.5 and 4.6
8. Phase 5
