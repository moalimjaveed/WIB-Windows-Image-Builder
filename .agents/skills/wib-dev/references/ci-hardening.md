# GitHub Actions CI Hardening — WIB Reference

WIB's CI uses GitHub Actions on `windows-latest`. The pipeline modifies Windows
images; supply-chain hygiene is critical.

---

## Minimum workflow structure

```yaml
name: CI
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

permissions:
  contents: read        # minimum required; add only what each job needs

jobs:
  test:
    runs-on: windows-latest
    permissions:
      contents: read

    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2
        with:
          persist-credentials: false

      - name: PSScriptAnalyzer
        shell: pwsh
        run: |
          Install-Module PSScriptAnalyzer -Force -Scope CurrentUser
          $results = Invoke-ScriptAnalyzer -Path . -Recurse -Severity Warning,Error
          if ($results.Count -gt 0) {
            $results | Format-Table -AutoSize
            exit 1
          }

      - name: Parse check (PS 5.1)
        shell: powershell
        run: |
          $errors = 0
          Get-ChildItem -Recurse -Filter '*.ps1' | ForEach-Object {
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
              $_.FullName, [ref]$null, [ref]$errs)
            if ($errs.Count -gt 0) {
              Write-Host "PARSE ERROR: $($_.FullName)" -ForegroundColor Red
              $errs | ForEach-Object { Write-Host "  $_" }
              $errors++
            }
          }
          if ($errors -gt 0) { exit 1 }

      - name: Smoke tests (PS 5.1)
        shell: powershell
        run: .\tests\smoke.ps1
```

---

## Action pinning rules

| Rule | Example |
|---|---|
| Pin ALL actions (including GitHub's own) to a full commit SHA | `actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683` |
| Add a comment with the human-readable version | `# v4.2.2` |
| Never use a mutable tag like `@v4` or `@main` | Taggable refs can be moved by the author |
| Review the commit before updating to a new SHA | Check the diff at `github.com/<owner>/<repo>/commit/<sha>` |

Current pinned SHAs for common actions (verify before use — these age):
- `actions/checkout@v4` → `11bd71901bbe5b1630ceea73d27597364c9af683`
- `actions/upload-artifact@v4` → `6f51ac03b9356f520e9a4f1d3ac62c5dfd99c21c`
- `actions/cache@v4` → `1bd1e32a3bdc45362d1e726936510720a7c6158d`

---

## Permissions model

```yaml
# Workflow-level: most restrictive possible
permissions:
  contents: read

jobs:
  test:
    permissions:
      contents: read      # to checkout
      # add only what this job specifically needs:
      # checks: write     # to post test results
      # pull-requests: write  # to comment on PRs
```

Never grant `write-all` or omit `permissions:` at workflow level (default is inherited
from organization settings, which may be permissive).

---

## Secret handling

```yaml
# Bad — secret visible in env at workflow level
env:
  MY_TOKEN: ${{ secrets.MY_TOKEN }}

# Good — scoped to the step that needs it
- name: Use token
  env:
    MY_TOKEN: ${{ secrets.MY_TOKEN }}
  run: do-something --token "$env:MY_TOKEN"
```

- Never echo secrets with `Write-Host`, `echo`, or `::debug::`.
- GitHub masks known secrets in logs, but do not rely on this as the only protection.

---

## GITHUB_ENV and GITHUB_OUTPUT injection

```yaml
# Dangerous — value may contain injection if it comes from user input
- run: echo "MYVAR=$untrustedInput" >> $env:GITHUB_ENV

# Safe — use a delimiter
- run: |
    $delimiter = [guid]::NewGuid().ToString()
    "MYVAR<<$delimiter" | Out-File -Append $env:GITHUB_ENV
    $untrustedInput | Out-File -Append $env:GITHUB_ENV
    $delimiter | Out-File -Append $env:GITHUB_ENV
```

For WIB, `GITHUB_ENV` injection risk is low (no PR-triggered builds that process
user-supplied ISO paths), but follow the pattern if it ever becomes relevant.

---

## Caching (Windows runners)

```yaml
- uses: actions/cache@1bd1e32a3bdc45362d1e726936510720a7c6158d  # v4
  with:
    path: |
      ~\AppData\Local\pip\Cache
      ~\.nuget\packages
    key: ${{ runner.os }}-deps-${{ hashFiles('**/requirements.txt') }}
    restore-keys: ${{ runner.os }}-deps-
```

WIB-specific cache candidates:
- `PSScriptAnalyzer` module (saves ~10s on install)
- Pester module
- oscdimg (if downloaded; cache the verified copy)

> [!TIP]
> Windows runner disk is ~14 GB free. A 25 GB work directory for a real ISO build
> cannot run on a free GitHub-hosted runner. Real-ISO CI must use self-hosted runners
> or a separate manual workflow.

---

## Concurrency and cost

```yaml
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true   # cancel older runs on the same branch
```

Windows runners cost more than Linux. Use `cancel-in-progress: true` to avoid
paying for stale runs when a PR is force-pushed.

---

## Workflow file checklist

Before adding or editing a workflow:

- [ ] All actions pinned to full commit SHA with version comment
- [ ] `permissions:` set at workflow level to `contents: read` minimum
- [ ] Per-job `permissions:` scoped to only what that job needs
- [ ] `persist-credentials: false` on `actions/checkout`
- [ ] No `pull_request_target` with code checkout (TOCTOU risk)
- [ ] Secrets scoped to steps, not workflow-level `env:`
- [ ] `cancel-in-progress: true` for PRs
- [ ] Parse check runs under `shell: powershell` (5.1), not `shell: pwsh`
- [ ] Smoke test runs under `shell: powershell` (5.1)
- [ ] No test claimed as passing unless it actually ran in this workflow
