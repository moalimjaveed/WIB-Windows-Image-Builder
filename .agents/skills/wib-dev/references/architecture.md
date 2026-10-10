# WIB Architecture Reference

## Overview

Windows Image Builder (WIB) is a manifest-driven, hardware-aware, reversible, and verifiable image-building system. Unlike one-way destructive scripts (such as tiny11builder), WIB operates on an explicit pipeline model where every operation is previewable via dry-run, checkpointed between stages, verified against dangling artifacts, and backed by measured telemetry.

## Core Pipeline

```
 Source ISO ──► [Stage 1: Preflight] ──► [Stage 2: Mount] ──► [Stage 3: Scan] ──► [Stage 4: Plan/Diff]
                                                                                        │
 Report + SBOM ◄── [Stage 10: Report] ◄── [Stage 9: Validate] ◄── [Stage 8: Package] ◄──┤ (if not dry-run)
                          ▲                                            │               │
                          └─────────── [Stage 7: Verify] ◄──────────────┴───────────────┘
                                                ▲
                                                └── [Stage 5: Apply Modules]
                                             [Stage 6: Checkpoints between stages]
```

### Pipeline Stages

1. **Preflight**:
   - Check Windows administrator elevation.
   - Verify host free disk space (minimum 25 GB on target drive).
   - Verify native DISM version and Windows ADK (`oscdimg.exe`) presence and Microsoft Authenticode signature.
   - Detect image SKU/edition, build number, and target architecture.
   - Verify input ISO hash against published/expected SHA-256 (never modify source ISO).

2. **Mount**:
   - Copy ISO contents to workspace (`work/iso`).
   - If `install.esd` is present, export the selected index to `install.wim` using maximum compression.
   - Create isolated mount point (`work/mount`).
   - Mount image index offline via DISM (`Mount-WindowsImage`).

3. **Scan**:
   - Dynamically inspect the mounted image without hardcoded assumptions.
   - Enumerate provisioned AppX packages (`Get-AppxProvisionedPackage`).
   - Enumerate optional Windows features (`Get-WindowsOptionalFeature`).
   - Enumerate Windows capabilities (`Get-WindowsCapability`).
   - Enumerate installed services and scheduled tasks from offline hives.

4. **Plan / Diff (Dry-Run)**:
   - Resolve profile inheritance (`extends` chain) and merge settings.
   - Evaluate module conditions (`AppliesWhen` rules for Build, Arch, Edition).
   - Match scan results against profile inclusion/exclusion/keep rules.
   - Generate concrete, itemized change plan with estimated disk space savings.
   - If `-DryRun` is active, display the plan, write dry-run manifest, dismount cleanly, and exit.

5. **Apply Modules**:
   - Run enabled module actions in strict dependency order (`Order` parameter).
   - File-level modifications (package removal, capability removal).
   - Mount offline registry hives (`SOFTWARE`, `SYSTEM`, `DEFAULT`, `NTUSER`).
   - Execute declarative tweaks (`New-WibTweak`) and programmatic tweaks (`-TweakProvider`).
   - Record all previous registry values into the in-image undo journal.
   - Safely unload registry hives with garbage collection and retry loop.

6. **Checkpoints**:
   - Commit incremental state between discrete pipeline stages.
   - Enable stage-level rollback ($N \to N-1$) upon failures instead of starting over.

7. **Verify**:
   - Audit mounted image for leftover references:
     * AppX registration remnants in registry.
     * Orphaned Scheduled Tasks (`TaskCache\Tasks`, `TaskCache\Tree`).
     * Edge and OneDrive remnant keys in Run / Active Setup.
   - Execute module-specific verification scriptblocks (`-Verify`).
   - Generate structured pass/warn/fail results.

8. **Package**:
   - Export optimized `install.wim` using recovery or high compression.
   - Mount `boot.wim` (Index 2: Setup) if setup-level tweaks (e.g. bypass hardware checks) are enabled.
   - Inject unattend answer file (`autounattend.xml`) if specified.
   - Master bootable UDF ISO using authenticated `oscdimg.exe` with deterministic parameters.

9. **Validate (VM)**:
   - Boot generated ISO in an isolated throwaway virtual machine (Hyper-V / QEMU).
   - Verify unattended setup boots to interactive desktop without OOBE errors.
   - Collect benchmark metrics (boot duration, idle RAM usage, footprint on disk).

10. **Report**:
    - Compile `manifest.json` (machine-readable SBOM with SHA-256 hashes of all inputs and outputs).
    - Render `report.html` (human-readable build summary, plan vs actual deltas, warnings, verification status).

## Core Components

| Component | Responsibility | Source File |
|---|---|---|
| **Core** | Logging, profile loading/validation, module registry, offline hive management, undo journal | `lib/Core.ps1` |
| **Scanner** | Dynamic query of AppX, features, capabilities, services, tasks in mounted offline image | `lib/Planner.ps1` |
| **Planner** | Resolves profiles, evaluates `AppliesWhen`, matches scan results, computes plan items | `lib/Planner.ps1` |
| **Engine** | Orchestrates pipeline stages, mounts/dismounts, invokes apply/verify passes, exports WIM/ISO | `lib/Engine.ps1` |
| **Modules** | Self-registering units declaring metadata, plan logic, apply actions, and verify checks | `modules/*.ps1` |
| **Verifier** | Detects dangling registry keys, orphaned tasks, and verifies applied module state | `lib/Engine.ps1` |
| **Reporter** | Generates `manifest.json` and standalone HTML reports | `lib/Report.ps1` |
| **Panel (v2)** | Post-install UI for reviewing applied tweaks, toggling reversible items, detecting drift | `panel/` |

## Context Object (`$Ctx`)

The build pipeline passes a central `$Ctx` hashtable across all stages and modules:

```powershell
$Ctx = @{
    IsoPath         = 'C:\Path\To\Win11.iso'
    WorkDir         = 'C:\WIB\work'
    MountDir        = 'C:\WIB\work\mount'
    IsoDir          = 'C:\WIB\work\iso'
    ProfileName     = 'balanced'
    Profile         = @{ ... }               # Merged profile hashtable
    ProfileHash     = 'abc123...'            # SHA-256 of canonical resolved profile
    Scan            = @{ ... }               # Discovered AppX, Features, Capabilities
    Plan            = @( ... )               # Generated New-WibPlanItem objects
    Journal         = @( ... )               # Undo entries for registry modifications
    Results         = @( ... )               # Execution results from applied modules
    Verification    = @( ... )               # Verification results (pass/warn/fail)
    DryRun          = $false
    AcceptRisk      = $false
}
```
