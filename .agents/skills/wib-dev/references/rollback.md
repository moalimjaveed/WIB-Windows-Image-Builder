# Rollback and Undo Journal Reference

## Overview

A core differentiator of WIB from legacy trimming tools is **reversibility**. Changes applied by WIB are tracked in an embedded **Undo Journal**, allowing adjustments and revocations both during image servicing and after deployment on live installations.

## The In-Image Undo Journal

During Stage 5 (`Apply`), every registry change made via `Set-WibTweak` captures the pre-existing state into `$Ctx.Journal`.

Before dismounting the image, the journal is written into the offline image at:
`Windows\WIB\journal.json`

### Journal Entry Format
```json
{
  "version": "1.0",
  "generatedUtc": "2026-10-03T09:00:00Z",
  "toolVersion": "0.1.0",
  "profile": "balanced",
  "entries": [
    {
      "module": "visual-effects",
      "hive": "NTUSER",
      "path": "Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\VisualEffects",
      "name": "VisualFXSetting",
      "appliedValue": 2,
      "appliedType": "DWord",
      "originalExists": true,
      "originalValue": 1,
      "originalType": "DWord"
    },
    {
      "module": "widgets-off",
      "hive": "SOFTWARE",
      "path": "Policies\\Microsoft\\Dsh",
      "name": "AllowNewsAndInterests",
      "appliedValue": 0,
      "appliedType": "DWord",
      "originalExists": false,
      "originalValue": null,
      "originalType": null
    }
  ]
}
```

## Rollback Execution

### 1. Build-Time Rollback (Failure in Pipeline)
If any fatal error occurs during `Invoke-WibApply` or `Invoke-WibVerify`:
1. Safely dismount and unload all loaded offline registry hives (`Dismount-WibHives`).
2. Dismount the Windows image discarding all uncommitted changes:
   ```powershell
   Dismount-WindowsImage -Path $Ctx.MountDir -Discard
   ```
3. The source WIM returns to its pristine state prior to module execution.

### 2. Post-Install Rollback (Live System)
On the installed Windows machine:
- The WIB Post-Install Panel or `Undo-WibTweaks.ps1` reads `C:\Windows\WIB\journal.json`.
- For each entry:
  - If `originalExists` is `true`: sets value back to `originalValue` with `originalType`.
  - If `originalExists` is `false`: removes the created registry value via `Remove-ItemProperty`.
- If an entire key was newly created and is now empty, prunes the key.

## Handling User Profile Drift

- Modifications in `NTUSER` (`Users\Default\NTUSER.DAT`) apply to newly created user accounts.
- When rolling back on an already installed system where the user has been active:
  - The script/Panel checks the current user's `HKCU` hive as well as `Users\Default\NTUSER.DAT`.
  - Informs the user of whether changes affect existing profiles or future accounts.
