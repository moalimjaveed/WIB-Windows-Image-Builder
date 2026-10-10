# Verification Pass Reference

## Verification Architecture

A build is never marked successful simply because a script executed without throwing an unhandled exception. WIB enforces an explicit **Verification Pass** (Stage 7) to validate that applied actions achieved their intended state and left no orphaned references.

Verification operates at two levels:
1. **Module-Specific Verification**: Declared by individual modules via `-Verify`.
2. **General Leftover Scan**: Engine-level audit of the mounted image for ghost references.

## General Leftover Scan (Stage 7)

When packages, apps, or services are uninstalled, Windows frequently leaves behind dangling entries across the registry and task scheduler. The general verification scanner inspects:

### 1. Orphaned TaskCache Entries
When scheduled tasks are deleted from the disk (`Windows\System32\Tasks\...`), their registrations in the registry often remain:
- `HKLM\wib_SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree`
- `HKLM\wib_SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tasks`

The verifier iterates all tasks listed in `TaskCache\Tree` and confirms their backing XML file exists on disk. Any task with a missing XML file is flagged as an orphaned task warning.

### 2. Ghost AppX Registry References
When provisioned AppX packages are removed with `Remove-AppxProvisionedPackage`, check that:
- Removed package IDs no longer appear in `Get-AppxProvisionedPackage -Path $mountDir`.
- Package family names do not remain in:
  `HKLM\wib_SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Applications`

### 3. Edge and OneDrive Run Remnants
- Check `HKLM\wib_SOFTWARE\Microsoft\Windows\CurrentVersion\Run`
- Check `HKLM\wib_NTUSER\Software\Microsoft\Windows\CurrentVersion\Run`
- Confirm removed browser or sync client startup launchers have been cleared.

## Verification Result Object

Verification checks return structured `New-WibResult` objects:

```powershell
function New-WibResult {
    param(
        [string]$Module,
        [ValidateSet('pass', 'warn', 'fail')]
        [string]$Status,
        [string]$Message,
        [string]$Target = ''
    )

    [PSCustomObject]@{
        Module  = $Module
        Status  = $Status
        Message = $Message
        Target  = $Target
    }
}
```

## Verification Failure Gate

- `pass`: The expected file, key, value, or capability state was confirmed.
- `warn`: Non-fatal inconsistency (e.g. leftover benign registry key); recorded in manifest and report.
- `fail`: Critical failure (e.g. tweak failed to write, key missing, service in invalid state).
  * Build status marked `failed`.
  * ISO packaging is halted.
