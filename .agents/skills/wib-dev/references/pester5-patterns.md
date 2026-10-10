# Pester v5 Patterns for WIB

WIB uses **Pester v5.x**. Do not migrate to Pester 6 unless explicitly requested.
Smoke tests in `tests/smoke.ps1` use a hand-rolled `Assert` function (no admin,
no Pester dependency). Pester is for integration tests that can live alongside them.

---

## Installation note (Windows PowerShell 5.1)

```powershell
# Install for current user (no admin needed)
Install-Module Pester -Force -Scope CurrentUser -MinimumVersion 5.0 -MaximumVersion 5.99

# Import explicitly (5.1 ships with Pester 3 built-in)
Import-Module Pester -MinimumVersion 5.0
```

> [!IMPORTANT]
> Windows PowerShell 5.1 ships with Pester **3.4.0**. Always import with
> `-MinimumVersion 5.0` or the old version will shadow the new one.

---

## File layout

```
tests/
  smoke.ps1                  Pure-logic Assert tests (no Pester)
  unit/
    Core.Tests.ps1
    Planner.Tests.ps1
  integration/               Requires admin; tagged 'manual'
    Engine.Tests.ps1
```

---

## Standard test file structure

```powershell
#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '../..')

Describe 'Core.ps1 — profile loading' -Tag 'unit' {

    BeforeAll {
        . (Join-Path $root 'lib/Core.ps1')
        . (Join-Path $root 'lib/Planner.ps1')
        Get-ChildItem (Join-Path $root 'modules') -Filter '*.ps1' |
            Sort-Object Name | ForEach-Object { . $_.FullName }
    }

    Context 'extends inheritance' {
        It 'child overrides parent module setting' -Tag 'unit', 'smoke' {
            $lean = Import-WibProfile (Join-Path $root 'profiles/lean.json')
            $lean['modules']['visual-effects']['enabled'] | Should -Be $true
        }

        It 'addRemove appends to parent remove list' -Tag 'unit' {
            $lean = Import-WibProfile (Join-Path $root 'profiles/lean.json')
            $lean['modules']['appx-removal']['addRemove'].Count | Should -BeGreaterThan 0
        }
    }

    Context 'validation' {
        It 'rejects unknown module id' -Tag 'unit', 'smoke' {
            $bad = @{ profile = 'x'; version = 1; modules = @{ 'ghost-module' = @{} } }
            { Test-WibProfile $bad } | Should -Throw
        }
    }
}
```

---

## Pester v5 vs v3 syntax cheatsheet

| v3 (forbidden) | v5 (required) |
|---|---|
| `Should Be $x` | `Should -Be $x` |
| `Should BeNullOrEmpty` | `Should -BeNullOrEmpty` |
| `Should Match 'pattern'` | `Should -Match 'pattern'` |
| `Should Throw` | `{ ... } \| Should -Throw` |
| `Mock Foo { }` | `Mock Foo { }` *(same, but inside `BeforeAll`/`InModuleScope`)* |
| `Assert-VerifiableMocks` | `Should -InvokeVerifiable` |
| `Assert-MockCalled Foo -Times 1` | `Should -Invoke Foo -Times 1` |
| `$global:` state across tests | `BeforeAll` / `AfterAll` blocks |

---

## Mocking native commands

WIB calls `reg.exe`, `dism.exe`, `takeown.exe`, `icacls.exe`. Mock them with:

```powershell
BeforeAll {
    # Redirect to no-op function so LASTEXITCODE stays 0
    function global:reg.exe { $global:LASTEXITCODE = 0 }
}
AfterAll {
    Remove-Item function:global:reg.exe -ErrorAction SilentlyContinue
}
```

> [!WARNING]
> Mocking native executables with `Mock` (Pester's built-in) does not work for
> commands called via `& program.exe`. Use the global function trick above, or
> use a wrapper function that delegates to the real binary.

---

## Tagging convention

| Tag | When to use |
|---|---|
| `smoke` | Pure logic; must pass in CI; no admin, no ISO |
| `unit` | Single function; may mock file system or registry |
| `integration` | Requires mounted image or admin; run manually |
| `regression` | Covers a bug that was fixed; include issue number in `It` description |
| `manual` | Requires a real Windows ISO or VM; never run in CI automatically |

CI runs only `-Tag 'smoke'`. Manual tests are documented but skipped automatically.

---

## Running tests

```powershell
# Smoke only (CI equivalent)
Invoke-Pester -Path tests/ -Tag smoke

# All unit tests
Invoke-Pester -Path tests/unit/ -Output Detailed

# With code coverage
Invoke-Pester -Path tests/unit/ -CodeCoverage lib/*.ps1 -CodeCoverageOutputFile coverage.xml

# Skip manual
Invoke-Pester -Path tests/ -ExcludeTag manual
```

---

## Pester configuration object (CI-friendly)

```powershell
$config = New-PesterConfiguration
$config.Run.Path = 'tests'
$config.Filter.Tag = 'smoke'
$config.Output.Verbosity = 'Detailed'
$config.TestResult.Enabled = $true
$config.TestResult.OutputFormat = 'JUnitXml'
$config.TestResult.OutputPath = 'test-results.xml'
Invoke-Pester -Configuration $config
```

Use this form in GitHub Actions to get a JUnit XML report GitHub can annotate.
