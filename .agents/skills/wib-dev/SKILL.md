---
name: wib-dev
description: >-
  Expert guide for developing Windows Image Builder (WIB). Covers the DISM/WIM
  pipeline, offline registry hive workflow, module contract, PowerShell 5.1
  compatibility rules, Pester v5 testing, GitHub Actions CI, reversibility tiers,
  and every hard project constraint. Activate whenever working on WIB code, tests,
  profiles, or CI.
---

# WIB Developer Skill

Windows Image Builder is a manifest-driven, hardware-aware, verifiable Windows 11
image-trimming tool. It is **not** a script you run on faith — every change is
declared, previewed, logged, and (where possible) reversible. This skill encodes the
project's non-negotiable rules, architecture, and workflows.

Read this skill fully before writing or reviewing any WIB code.

---

## 1. Hard constraints — never break these

| Rule | Why |
|---|---|
| **PowerShell 5.1 only** — no ternary `? :`, no null-coalescing `??`, no `pwsh`-only cmdlets | The tool runs on the Windows environment it modifies |
| **First-party tools only** — DISM cmdlets, `reg.exe`, `oscdimg` (ADK) | No unvetted binaries touch the image |
| **Never ship a Windows ISO** | Licensing; users supply their own Microsoft ISO |
| **Never claim something is tested unless it actually ran** | README must always distinguish logic-tested from real-image-tested |
| **Dry-run must never modify the image** | Mount read-only; `--dry-run` stops before `Invoke-WibApply` |
| **Source ISO is never modified in place** | Files are copied to the work directory first |
| **Profile validates before any mount** | `Test-WibProfile` must throw on unknown modules; mount never starts on a bad profile |
| **Every new module declares: id, risk, reversibility tier, tradeoff text, verify step** | Without these the planner and panel cannot function |
| **Smoke test required for every new feature** | No new code ships without at least one `Assert` in `tests/smoke.ps1` |
| **Reproducibility** — never introduce current timestamps, random temp names, unordered enumeration, machine-specific paths, or non-pinned dependencies into build output | `same ISO + same profile + same tool version = identical result` |

---

## 2. Repository layout

```
build.ps1              CLI entry point
lib/
  Core.ps1             Logging, profiles, module registry, offline registry, undo journal
  Planner.ps1          Scan, app matching, plan generation, dry-run display
  Engine.ps1           Build pipeline (stages 1-9)
  Report.ps1           manifest.json + report.html
modules/
  10-removal.ps1       appx-removal, edge-removal, onedrive-removal, copilot-removal,
                       teams-outlook-autoinstall-block, tasks-cleanup, features-cleanup
  20-tweaks.ps1        visual-effects, background-apps, telemetry, widgets-off,
                       hardware-check-bypass, local-account-oobe, services-tuning,
                       search-indexing, component-store-slim
profiles/
  balanced.json
  lean.json            (extends balanced)
tests/
  smoke.ps1            Pure-logic tests; no admin, no ISO, no DISM required
reports/<stamp>/       build.log, manifest.json, report.html  (git-ignored)
work/                  iso/, mount/  (git-ignored, 25 GB required)
```

> [!IMPORTANT]
> The smoke test dot-sources `lib/Core.ps1`, `lib/Planner.ps1`, `lib/Report.ps1`, and
> all `modules/*.ps1` relative to `$PSScriptRoot/..`. Keep those paths stable.

---

## 3. Build pipeline (stages)

```
[1 Preflight] → [2 Copy+Mount] → [3 Scan] → [4 Plan/Diff]
                                                    ↓
[10 Report] ← [9 Validate] ← [8 Package] ← [7 Verify] ← [5 Apply] ← [4 if not dry-run]
                                            [6 Checkpoint between every stage]
```

| Stage | Key actions | Code location |
|---|---|---|
| 1 Preflight | DISM cmdlet check, oscdimg resolve, free space, stale-mount cleanup, ISO hash | `Engine.ps1: Invoke-WibBuild` |
| 2 Mount | ESD→WIM convert if needed, `Mount-WindowsImage`, set `$ctx` | `Engine.ps1` |
| 3 Scan | `Get-WibScan` — AppX, optional features, capabilities, services, tasks | `Planner.ps1` |
| 4 Plan | `New-WibPlan` + `Show-WibPlan`; `--dry-run` dismounts here | `Planner.ps1` |
| 5 Apply | `Invoke-WibApply`: (A) file work, (B) hive load + tweaks, (C) verify, (E) post | `Engine.ps1` |
| 6 Checkpoint | `Save-WindowsImage -Append` after each stage with rollback restoration | `Engine.ps1: New-WibCheckpoint` |
| 7 Verify | General leftover scan: ghost registry refs, orphaned TaskCache entries | `Engine.ps1` |
| 8 Package | `dism /Export-Image`, `boot.wim`, `autounattend.xml`, `oscdimg` | `Engine.ps1` |
| 9 Validate | VM boot, benchmark (`tools/Invoke-WibVmBenchmark.ps1`) | `tools/` |
| 10 Report | `Write-WibReport` → `manifest.json` + `report.html` | `Report.ps1` |

---

## 4. Module contract

Every module is registered with `Register-WibModule`. All parameters are **mandatory for new modules**:

```powershell
Register-WibModule `
    -Id          'my-module' `
    -Description 'One sentence.' `
    -Risk        'low'              # low | medium | high
    -Reversibility 'journal'        # 'journal' | 'reinstallable' | 'permanent'
    -Tradeoff    'What you gain vs. what you lose.' `  # required from v1.1
    -Scope       @('install')       # 'install' | 'boot'
    -Order       50 `
    -Plan        { param($Ctx, $S) <# returns New-WibPlanItem objects #> } `
    -Apply       { param($Ctx, $S) <# file-level work; hives NOT loaded #> } `
    -Verify      { param($Ctx, $S) <# called with hives loaded #> } `
    -Tweaks      @(                 # static registry tweaks; or use -TweakProvider
        New-WibTweak -Hive SOFTWARE -Path 'Policies\...' -Name 'Val' -Value 0
    )
```

### Reversibility tiers

| Tier | Value | Meaning | Example |
|---|---|---|---|
| Journal | `journal` | Registry change recorded in `journal.json`; Panel can undo | All `New-WibTweak` changes |
| Reinstallable | `reinstallable` | Removed but can be put back (Store, DISM) | AppX removal |
| Permanent | `permanent` | Cannot be undone without a rebuild | File deletion, `/ResetBase` |

> [!WARNING]
> **Never mark a file deletion or permanent change as `Reversibility = 'journal'`.** File deletions, package removals with `/ResetBase`, or unrecoverable filesystem modifications must always be marked `Reversibility = 'permanent'`.


### Risk levels

- `low` — can be in `balanced` by default
- `medium` — off in `balanced`, on in `lean` or opt-in
- `high` — **must require `-AcceptRisk`**; never in `balanced` or `lean`; examples: mitigations, Defender, UAC

---

## 5. Offline registry workflow

```
Mount-WibHives  (reg.exe load HKLM\wib_<NAME> <hive-file>)
    ↓
Invoke-WibTweaks  (Set-WibTweak / Test-WibTweak via Registry::HKLM\wib_<NAME>\...)
    ↓
Dismount-WibHives  ([gc]::Collect + reg.exe unload, 6 retries)
```

Rules:
- **Always** wrap hive work in `try/finally { Dismount-WibHives }`.
- **Never** access `HKLM\wib_*` keys after `Dismount-WibHives`.
- Hive names: `SOFTWARE`, `SYSTEM`, `DEFAULT`, `NTUSER`.
- `Set-WibTweak` records the pre-change value in `$Ctx.Journal` automatically.
- `Test-WibTweak` is called during the verify pass; return a `New-WibResult` object.

---

## 6. PowerShell 5.1 compatibility checklist

Before submitting any `.ps1` file, check every item:

- [ ] No ternary operator `$x = $a ? $b : $c` → use `if`/`else`
- [ ] No null-coalescing `$x ?? $y` → use `if ($null -eq $x)`
- [ ] No `ConvertFrom-Json -AsHashtable` → use `ConvertTo-WibHashtable` from `Core.ps1`
- [ ] No `ForEach-Object -Parallel` → sequential only
- [ ] No `[System.IO.Path]::Join` (PS7) → use `Join-Path`
- [ ] No string interpolation with complex expressions `"$($a.B.C ?? $d)"` containing `??`
- [ ] Test with `powershell.exe` (5.1), not `pwsh` (7)
- [ ] `$ErrorActionPreference = 'Stop'` at script top
- [ ] ASCII-only source files (no smart quotes, no BOM issues with `reg.exe`)

---

## 7. Testing rules

### smoke.ps1 (pure logic — no admin, no ISO)

The smoke test is the CI gate. Add an `Assert` for every new code path:

```powershell
Assert (<bool expression>) 'descriptive message'
```

Run: `powershell .\tests\smoke.ps1`  (also `pwsh` to catch cross-version regressions)

Current coverage: profile loading/merging, module registry, AppX matching + keep rules,
plan generation against a fake temp directory, report writing.

**Required asserts for new features:**
- Profile validation rejects the new schema violation
- Plan includes the new module's items
- Apply results include `applied` or `skipped` (not `failed`) for happy path
- Verify results include `pass` for happy path

### Pester v5 (integration, where admin not needed)

Use Pester v5 with `Describe`/`It`/`BeforeAll`/`AfterAll`. Tag tests:

```powershell
Describe 'appx-removal' -Tag 'smoke', 'unit' {
    It 'keep rule wins over remove pattern' -Tag 'smoke' {
        # ...
    }
}
```

Tags to use: `smoke`, `unit`, `integration`, `regression`, `manual` (for tests that need admin/ISO).

> [!CAUTION]
> **Do NOT mix Pester v3 syntax with v5.** No `Should Be` (old style) — use `Should -Be`.
> No `Mock -Verifiable` without `Assert-VerifiableMocks`.
> Pester baseline: **v5.x**. Do not migrate to Pester 6 unless explicitly requested.

### What must never be claimed as "tested"

- Any path that touches `Mount-WindowsImage`, `Dismount-WindowsImage`, `dism.exe`, or
  `reg.exe load` is **not** tested by smoke tests.
- README `Status` section must list these as "NOT yet tested on a real image".

---

## 8. Profile format rules

Profiles are JSON (YAML for authors later). Required fields: `profile`, `version`, `modules`.

```json
{
  "profile": "my-profile",
  "version": 1,
  "extends": "balanced",
  "modules": {
    "visual-effects": { "enabled": true },
    "appx-removal": { "addRemove": ["My.Extra.App"] }
  }
}
```

- `enabled: false` disables a module even if it is in the profile.
- `extends` chains inherit parent modules; child values override; arrays **replace** (use `addRemove` to append).
- Unknown module ids **must** be rejected by `Test-WibProfile` before any mount.
- Profile hash is computed over the **merged** (resolved) profile, not the source file.

---

## 9. CI rules (GitHub Actions)

Workflow file: `.github/workflows/ci.yml`. Windows runner only.

Required steps:
1. `PSScriptAnalyzer` — zero warnings, `Severity = Warning, Error`
2. Parse check — `powershell -Command "& { Get-ChildItem *.ps1, lib/*.ps1, modules/*.ps1 -Recurse | ForEach-Object { $null = [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$null) } }"`
3. Smoke test — `powershell .\tests\smoke.ps1`

CI hardening (apply to all workflow files):
- Pin every third-party action to a **full commit SHA**, not a tag.
- Use minimum required `permissions:` per job.
- No secrets in `env:` at workflow level if they can be scoped to a step.
- Never use `pull_request_target` with code checkout.

> [!TIP]
> Run `PSScriptAnalyzer` locally before pushing:
> `Invoke-ScriptAnalyzer -Path . -Recurse -Severity Warning,Error`

---

## 10. Manifest and reporting rules

`manifest.json` must contain:

```jsonc
{
  "tool": { "name": "WIB", "version": "0.1.0" },
  "createdUtc": "<ISO 8601>",
  "status": "success | completed-with-warnings | failed | dry-run",
  "profile": { "name": "...", "version": 1, "sha256": "<merged-profile-hash>" },
  "source": { "isoSha256": "...", "edition": "...", "build": "...", "index": 1 },
  "oscdimg": { "path": "...", "sha256": "..." },
  "plan": [...],
  "results": [...],
  "verification": [...],
  "output": { "iso": "...", "sha256": "...", "sizeBytes": 0 }
}
```

- `status` must be `"failed"` if an unhandled exception occurred.
- `verification` failures are `"fail"`, not `"failed"` (the engine uses both; keep them consistent).
- Report disk savings **separately** from RAM numbers — they are different things.
- Never publish benchmark numbers that the built-in benchmark did not produce.

---

## 11. Safety rules

1. **Snapshot VM before every real test.** Do not use a WIB-built image on a machine you cannot reinstall until it boots in a VM.
2. **oscdimg signer must be Microsoft** — `(Get-AuthenticodeSignature $path).Status -eq 'Valid'` is not sufficient; verify the signer organization.
3. **Never add a tweak without a documented or measured effect.** "It might help" is not enough.
4. **`/ResetBase` is opt-in only** — `aggressive: false` default; `component-store-slim` only runs `/StartComponentCleanup` by default.
5. **Hardware-check bypass is off by default** — explicitly set `hardware-check-bypass: enabled: true`.
6. **Unattend files are never downloaded** — `unattendPath` is user-supplied only.

---

## 12. What is NOT yet implemented (as of v0.1.0)

Current feature status and pending test requirements:

**Implemented Subsystems (Core v1 & Platform v2/v3):**
- [x] Per-stage checkpoints and WIM index rollback (`lib/Engine.ps1`)
- [x] Services module with never-touch protection (`modules/20-tweaks.ps1`)
- [x] `features-cleanup` module with critical servicing protection (`modules/10-removal.ps1`)
- [x] `search-indexing` module (`modules/20-tweaks.ps1`)
- [x] General verify pass for leftover remnants (`lib/Engine.ps1`)
- [x] `appliesWhen` / `onError` policy enforcement per module (`lib/Planner.ps1`, `lib/Engine.ps1`)
- [x] Three-tier reversibility (`journal`, `reinstallable`, `permanent`)
- [x] Canonical profile hashing & parent chain tracking (`lib/Core.ps1`)
- [x] Hardware-adaptive decision engine (`lib/Hardware.ps1`, `profiles/adaptive.json`)
- [x] VM boot validation & benchmarking tool (`tools/Invoke-WibVmBenchmark.ps1`)
- [x] Post-install Control Panel & update-aware re-patching (`tools/WibPanel.ps1`)
- [x] NTFS / WOF transparent compression engine & GUI (`lib/Compact.ps1`, `tools/wib-compact.ps1`)
- [x] Enterprise hardening profile & audit logging (`profiles/hardening.json`, `modules/40-hardening.ps1`)
- [x] Detached RSA SHA-256 manifest integrity & signing (`lib/Core.ps1`)

**Pending Live-System Verification:**
- [ ] End-to-end VM installation boot test against a physical Microsoft Windows 11 ISO (Phase 1 validation).
- [ ] Live unattend OOBE bypass verification on physical hardware.

---

## 13. References

The `references/` directory contains deep authoritative documentation for every subsystem:

1. [`references/architecture.md`](references/architecture.md) — 10-stage pipeline, core components, and context flow.
2. [`references/dism.md`](references/dism.md) — Offline image servicing, mounts, cleanup, and dismount lifecycle.
3. [`references/wim-esd.md`](references/wim-esd.md) — WIM vs ESD formats, conversions, index discovery, and `boot.wim`.
4. [`references/offline-registry.md`](references/offline-registry.md) — Hive mounting, key paths, retry loops, and safe unloading.
5. [`references/powershell-5.1.md`](references/powershell-5.1.md) — Strict PowerShell 5.1 compatibility rules and forbidden syntax.
6. [`references/module-contract.md`](references/module-contract.md) — `Register-WibModule` contract, reversibility tiers, and risk levels.
7. [`references/checkpoints.md`](references/checkpoints.md) — Per-stage checkpointing and rollback mechanisms.
8. [`references/rollback.md`](references/rollback.md) — In-image undo journal (`Windows\WIB\journal.json`) and live reversion.
9. [`references/verification.md`](references/verification.md) — Post-apply verification and general leftover scanning.
10. [`references/reproducibility.md`](references/reproducibility.md) — Deterministic ISO builds and hash management.
11. [`references/testing.md`](references/testing.md) — Pester v5 test architecture, test tags, and pure-logic vs VM testing.
12. [`references/ci-security.md`](references/ci-security.md) — GitHub Actions supply chain security and SHA pinning.
13. [`references/hardware-adaptation.md`](references/hardware-adaptation.md) — Hardware profile discovery and adaptive decisions.

Historical & operational guides:
- [`references/ps51-pitfalls.md`](references/ps51-pitfalls.md) — Quick cheatsheet for PS 5.1 vs 7.
- [`references/dism-workflow.md`](references/dism-workflow.md) — DISM command reference.
- [`references/pester5-patterns.md`](references/pester5-patterns.md) — Pester v5 pattern guide.
- [`references/ci-hardening.md`](references/ci-hardening.md) — CI hardening guide.

