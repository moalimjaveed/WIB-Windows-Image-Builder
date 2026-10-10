# Testing Strategy Reference

## Testing Principles

1. **Never claim a test passed unless that test actually ran.**
2. **Never claim a benchmark result unless it was actually measured.**
3. **Never claim verification unless verification actually occurred.**
4. **Logic tests must run anywhere (no admin, no ISO, no VM).**
5. **Real-image tests must be isolated and snapshot-protected.**

## Test Architecture

WIB employs a two-tier testing model:

```
                  ┌─────────────────────────────────────────────────────────┐
                  │                 Pure-Logic Test Suite                   │
                  │   tests/smoke.ps1 + Pester 5 Unit Tests (tests/unit/)    │
                  │                                                         │
                  │  • No Admin Required     • No Windows ISO Needed        │
                  │  • No DISM Invocation    • Runs in CI in < 15 seconds   │
                  └────────────────────────────┬────────────────────────────┘
                                               │
                                               ▼
                  ┌─────────────────────────────────────────────────────────┐
                  │                Integration & VM Test Suite              │
                  │              tests/integration/ + VM Boot               │
                  │                                                         │
                  │  • Requires Admin        • Requires Real Windows ISO    │
                  │  • DISM Offline Mount    • Hyper-V / QEMU Benchmark     │
                  └─────────────────────────────────────────────────────────┘
```

## Pester 5.x Standard

WIB standardizes on **Pester 5.x**. Do not use legacy Pester 3/4 syntax, and do not migrate to Pester 6.

### Pester 5 Two-Phase Execution Model
Pester 5 separates execution into **Discovery** and **Run**:
- Code placed directly inside `Describe` runs during Discovery.
- Setup code that generates test data or imports modules must be placed inside `BeforeAll` or `BeforeDiscovery`.

```powershell
Describe 'WIB Profile Inheritance' -Tag 'smoke', 'unit' {
    BeforeAll {
        . "$PSScriptRoot/../../lib/Core.ps1"
    }

    Context 'When loading lean profile' {
        It 'Merges with balanced parent' -Tag 'smoke' {
            $profile = Import-WibProfile -Path "$PSScriptRoot/../../profiles/lean.json"
            $profile.modules['visual-effects'].enabled | Should -Be $true
        }
    }
}
```

## Standard Test Categories and Tags

Use standardized tags across all Pester test files:

| Tag | Purpose | Execution Context |
|---|---|---|
| `smoke` | Fast sanity checks covering critical logic | CI and local pre-commit |
| `regression` | Validates fixes for previously identified bugs | CI and local testing |
| `integration` | Tests interacting with filesystems, DISM mocks, or registry | Local elevated session |
| `performance` | Measures parsing and execution timing | Dedicated performance test runner |
| `security` | Validates permission bounds, input sanitization, signature checks | CI security workflow |
| `boundary` | Validates edge cases (null inputs, missing keys, empty arrays) | Unit test suite |
| `negative` | Asserts that invalid inputs or corrupted profiles throw errors | Unit test suite |
| `critical-path`| Primary workflow (preflight, scan, plan, dry-run, report) | Core test suite |

## Minimum Test Taxonomy for WIB

- **Smoke**:
  * `preflight`: parameter checking, environment detection.
  * `mount`: directory creation, path resolution.
  * `scan`: AppX pattern matching, capability filtering.
  * `package`: report serialization, manifest structure.

- **Regression**:
  * `module-behavior`: keep rules preventing removal of required components.
  * `manifest-parsing`: circular `extends` detection, unknown key rejection.
  * `rollback`: journal undo accuracy and value restoration.

- **Integration**:
  * `DISM`: offline mounting, package removal, unmounting.
  * `offline-registry`: hive load, key modification, clean unload.
  * `ISO-creation`: oscdimg parameter validation and image generation.

- **Performance**:
  * Build execution time.
  * Target ISO file size.
  * VM boot duration to desktop.
  * Idle RAM consumption after settle period.

- **Security**:
  * Detection of unintended file modifications.
  * Verification of Microsoft Authenticode signatures on `oscdimg`.
  * CI workflow least-privilege token permissions.
