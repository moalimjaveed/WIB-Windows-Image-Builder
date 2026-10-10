# Pipeline Checkpoints Reference

## Purpose

Traditional image building scripts run as single uncheckpointed operations. If a failure occurs at stage 7 (e.g. registry error or verification failure), the entire build is discarded and must restart from scratch (preflight, copying multi-gigabyte ISO files, mounting, scanning).

WIB implements **stage-level checkpoints**, enabling the build engine to commit intermediate milestones and recover cleanly without redoing expensive I/O operations.

## Checkpoint Architecture

```
[Stage 1: Preflight]
        ↓  (Snapshot 1: Clean extracted sources)
[Stage 2: Mount]
        ↓  (Snapshot 2: Clean mounted image)
[Stage 3: Scan & Plan]
        ↓
[Stage 5: Apply Modules]
        ↓  (Checkpoint 3: Serviced offline image)
[Stage 7: Verify]
        ↓  (Checkpoint 4: Verified image)
[Stage 8: Package]
```

## Checkpoint Mechanisms in Windows WIM

### 1. Incremental WIM Snapshots (`Save-WindowsImage -Append`)

DISM allows appending an intermediate state into a new index in the WIM file using single-instance file storage. Identical files are referenced by hash without duplicating disk consumption:

```powershell
function New-WibCheckpoint {
    param(
        [string]$MountDir,
        [string]$StageName
    )

    Write-WibLog -Level INFO -Message "Creating checkpoint after stage: $StageName"
    
    # Commit changes to current mount
    Save-WindowsImage -Path $MountDir -CheckIntegrity
}
```

### 2. Differencing Hardlinks / Cow Workspaces

For fast non-destructive rollback during file removal stages:
- Storing stage markers in `$Ctx.Checkpoints` array.
- On failure of Stage $N$, discard the uncommitted mount via `Dismount-WindowsImage -Discard`.
- Return to the last known-good checkpoint index.

## Checkpoint Recovery Flow

```powershell
try {
    Invoke-StageApply -Ctx $Ctx
    New-WibCheckpoint -MountDir $Ctx.MountDir -StageName 'Apply'
}
catch {
    Write-WibLog -Level ERROR -Message "Stage Apply failed: $_. Rolling back to last checkpoint..."
    Invoke-WibRollbackCheckpoint -Ctx $Ctx -TargetStage 'Mount'
    throw
}
```

## Storage Overhead Management

- WIM single-instance storage ensures that only modified clusters consume additional disk space during checkpointing.
- Checkpoints are maintained in the temporary working directory (`work/`) and are discarded when final export creates the clean single-index target WIM during Stage 8 (`Package`).
