# Contributing to Windows Image Builder (WIB)

Thank you for your interest in contributing to Windows Image Builder! WIB is an open-source project dedicated to safe, manifest-driven, and auditable Windows 11 image customization.

---

## Code of Conduct

All contributors and participants are expected to adhere to the project's [Code of Conduct](CODE_OF_CONDUCT.md). Please treat all community members with respect and courtesy.

---

## Critical Safety Rules

> [!CAUTION]
> **No Proprietary Media or Secrets:**
> 1. **Never commit, stage, or upload Windows ISOs, WIMs, ESDs, or VHDX files.** These contain proprietary Microsoft binaries and violate intellectual property laws and GitHub terms.
> 2. **Never include secrets, product keys, plaintext passwords, or personal credentials** in pull requests, test fixtures, or issue logs.
> 3. **Sanitize logs:** Always redact local usernames, internal hostnames, and domain paths before posting diagnostic output.

---

## Coding Standards & Architectural Rules

To maintain backward compatibility and enterprise reliability, all contributions must adhere to these hard constraints:

1. **Windows PowerShell 5.1 Compatibility:**
   * All scripts in `lib/`, `modules/`, `tools/`, and `tests/` must execute without error on native Windows PowerShell 5.1 (Desktop edition).
   * **Do not use PowerShell 7+ syntax:** No ternary operators (`? :`), no null-coalescing operators (`??`), no pipeline chaining (`&&` / `||`), and no `ForEach-Object -Parallel`.
2. **Pure ASCII Encoding (Strictly Enforced by Gate G10):**
   * All `.ps1`, `.psm1`, and `.psd1` files must contain only pure ASCII characters (character code $\le 127$). Do not use smart quotes, em-dashes, or non-ASCII Unicode characters in code or comments.
3. **First-Party Tools Only:**
   * Rely only on inbox Windows binaries (`dism.exe`, `reg.exe`) and official Microsoft tools (`oscdimg.exe` from the Windows ADK). Do not add dependencies on third-party binary executables.
4. **Fail-Closed Security Design:**
   * Security functions, path containment checks, staging snapshots, and ACL verifications must fail closed (throw terminating errors) when unexpected inputs or permissions are encountered.
5. **Preserve Reversibility:**
   * Offline registry modifications must generate corresponding undo actions captured in the image rollback journal (`journal.json` / `journal.reg`).

---

## Local Development & Testing Workflow

Before opening a pull request, run the test suites locally to ensure zero regressions:

### 1. Run PowerShell Script Analyzer
Verify code syntax against our repository settings:
```powershell
Invoke-ScriptAnalyzer -Path @('build.ps1', 'lib', 'modules', 'tools', 'tests') -Settings .\PSScriptAnalyzerSettings.psd1 -Severity Warning, Error
```

### 2. Run Smoke Tests (Non-Elevated)
Every functional change must pass all smoke assertions:
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\smoke.ps1
```
*Ensure output ends with `All checks passed (<count> assertions).` with exit code `0`.*

### 3. Run Behavioral Release Gates (Non-Elevated)
Verify release gate integrity:
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\verify-gates.ps1 -Gate All
```
*Ensure output ends with `ALL_GATES_PASS` with exit code `0`.*

### 4. Lint Release Gate Ledger
Verify that `GATES.md` matches strict schema rules:
```cmd
node .\.agents\skills\unlazy\scripts\gate-lint.mjs --strict GATES.md
```

---

## Submitting Pull Requests

1. **Fork and Branch:** Create a feature branch off `main` (e.g., `git checkout -b feature/improved-paging-tuning`).
2. **Write Tests:** Add corresponding test assertions in [`tests/smoke.ps1`](tests/smoke.ps1) for every new feature or bug fix.
3. **Update Documentation:** If your change modifies CLI parameters or profile options, update [`README.md`](README.md), [`docs/GETTING_STARTED.md`](docs/GETTING_STARTED.md), and [`CHANGELOG.md`](CHANGELOG.md).
4. **Descriptive PR Title & Summary:** Clearly describe the problem solved, the implementation approach, and the exact test commands executed with their exit codes.

---

## Reporting Issues

* **Bug Reports:** Use the [Bug Report template](.github/ISSUE_TEMPLATE/bug_report.yml). Include your Windows version (`winver`), PowerShell version (`$PSVersionTable.PSVersion`), the exact command executed, and sanitized console output.
* **Feature Requests:** Use the [Feature Request template](.github/ISSUE_TEMPLATE/feature_request.yml) to explain the use case and expected benefit.
* **Security Vulnerabilities:** Follow the instructions in [`SECURITY.md`](SECURITY.md). Never submit vulnerability reports through public GitHub issues.
