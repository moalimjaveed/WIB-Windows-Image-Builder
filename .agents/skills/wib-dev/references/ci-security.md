# CI Security & GitHub Actions Reference

## Threat Model for Image Builder CI

WIB operates directly with low-level Windows image manipulation, DISM tooling, offline registry hives, and ISO generation. CI workflows that build or test such software must adhere to strict software supply chain security standards.

## Mandatory GitHub Actions Rules

### 1. Pin All Third-Party Actions to Immutable Commit SHAs
Tags (like `@v4` or `@main`) are mutable and can be rewritten if an upstream repository is compromised. Always pin actions to the full 40-character commit SHA with a version comment:

```yaml
# BAD
- uses: actions/checkout@v4

# GOOD
- uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2
```

### 2. Least-Privilege Permissions
Never leave workflow permissions at repository defaults (which often grant write access). Specify restrictive permissions explicitly at the top level, and grant permissions per-job only when strictly required:

```yaml
# Top-level: Deny all by default or read contents only
permissions:
  contents: read

jobs:
  test:
    runs-on: windows-latest
    permissions:
      contents: read
```

### 3. Prevent Script Injection via `${{ }}` Interpolation
GitHub Actions expands `${{ }}` expressions before invoking the shell. Never interpolate outside inputs directly into `run:` scripts:

```yaml
# BAD — Vulnerable to shell injection
- run: Write-Host "Checking out branch ${{ github.head_ref }}"

# GOOD — Pass through environment variables
- name: Safe branch check
  env:
    BRANCH_NAME: ${{ github.head_ref }}
  run: Write-Host "Checking out branch $env:BRANCH_NAME"
```

### 4. Runner Disk & Security Boundaries
- GitHub-hosted Windows runners provide approximately 14 GB of free disk space. A full Windows 11 build pipeline with offline WIM servicing requires 25+ GB of temporary storage.
- Real-ISO integration builds must not be triggered on unvetted public PRs.
- `pull_request_target` must never check out and execute code from untrusted forks.

### 5. Concurrency & Cost Optimization
Cancel redundant in-flight builds when a pull request branch receives new commits:

```yaml
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true
```

## Standard CI Pipeline Workflow (`.github/workflows/ci.yml`)

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

permissions:
  contents: read

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  lint-and-smoke:
    name: Lint & Smoke Tests
    runs-on: windows-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2
        with:
          persist-credentials: false

      - name: Cache PowerShell Modules
        uses: actions/cache@1bd1e32a3bdc45362d1e726936510720a7c6158d # v4.2.0
        with:
          path: ~\Documents\WindowsPowerShell\Modules
          key: ${{ runner.os }}-psmodules-${{ hashFiles('**/*.ps1') }}
          restore-keys: ${{ runner.os }}-psmodules-

      - name: Run PSScriptAnalyzer
        shell: pwsh
        run: |
          if (-not (Get-Module -ListAvailable PSScriptAnalyzer)) {
            Install-Module PSScriptAnalyzer -Force -Scope CurrentUser
          }
          $results = Invoke-ScriptAnalyzer -Path . -Recurse -Severity Warning, Error
          if ($results.Count -gt 0) {
            $results | Format-Table -AutoSize
            exit 1
          }

      - name: Verify PowerShell 5.1 AST Parsing
        shell: powershell
        run: |
          $errors = 0
          Get-ChildItem -Recurse -Filter '*.ps1' | ForEach-Object {
            $null = [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$parseErrors)
            if ($parseErrors.Count -gt 0) {
              Write-Host "[!] Parse error in $($_.FullName):" -ForegroundColor Red
              $parseErrors | ForEach-Object { Write-Host "    Line $($_.Extent.StartLineNumber): $($_.Message)" }
              $errors++
            }
          }
          if ($errors -gt 0) { exit 1 }

      - name: Execute Smoke Tests (Windows PowerShell 5.1)
        shell: powershell
        run: |
          & .\tests\smoke.ps1
```
