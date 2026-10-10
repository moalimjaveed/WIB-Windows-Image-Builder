## Description

<!-- Describe your changes in detail. What problem does this PR solve or what capability does it add? -->

## Related Issue

<!-- Fixes #ISSUE_NUMBER or Relates to #ISSUE_NUMBER -->

## Type of Change

- [ ] Bug fix (non-breaking change fixing an issue)
- [ ] New feature (non-breaking change adding functionality)
- [ ] Breaking change (fix or feature causing existing behavior to change)
- [ ] Documentation update
- [ ] Test enhancement or refactoring

## Compatibility & Quality Checklist

- [ ] **Windows PowerShell 5.1 Compatible:** Code runs cleanly on PowerShell 5.1 without PS 7+ exclusive syntax (no ternary `?:`, no null-coalescing `??`, no pipeline chain `&&`/`||`).
- [ ] **Pure ASCII:** All `.ps1`, `.psm1`, and `.psd1` files contain only ASCII characters (codes 1-127) per Gate G10 requirements.
- [ ] **First-Party Toolchain:** Uses only native Windows tooling (`dism.exe`, `oscdimg.exe`, offline registry mounting). No third-party binaries introduced.
- [ ] **Fail-Closed Security:** File operations verify handle identity, validate destination DACLs, and reject unowned path substitutions.
- [ ] **Reversibility Preserved:** Any offline registry modifications generate corresponding entries in the in-image undo journal (WibPanel / JSON / reg).

## Verification Evidence

- [ ] Smoke tests run and passed (`powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\smoke.ps1`)
- [ ] Release gates run and passed (`powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\verify-gates.ps1 -Gate All`)
- [ ] Gate lint run and passed (`node .\.agents\skills\unlazy\scripts\gate-lint.mjs --strict GATES.md`)
- [ ] New/updated tests included covering the modified code paths

## Public Release Safety Checklist

- [ ] No `.iso`, `.wim`, `.esd`, `.vhd`, or `.vhdx` files included in this commit
- [ ] No credentials, product keys, certificates, or secrets committed
- [ ] No local machine paths, usernames, or internal network identifiers hardcoded in public files
