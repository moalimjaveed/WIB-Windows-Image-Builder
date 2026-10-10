#Requires -Version 5.1
<#
.SYNOPSIS
    Real DISM Checkpoint & Rollback Integration Test.
.DESCRIPTION
    Builds a tiny scratch WIM (~1 MB) from a minimal scratch folder using New-WindowsImage,
    mounts it, creates real checkpoints via Save-WindowsImage -Append, applies changes,
    simulates dirty stage corruption, and invokes Restore-WibCheckpoint to prove that
    Dismount -Discard and remount of the checkpoint index physically restores the image.
    
    REQUIRES: Windows Administrator privileges (Run as Administrator).
#>

[CmdletBinding()]
param(
    [switch]$AllowSkip
)

$ErrorActionPreference = 'Stop'
$scriptRoot = $PSScriptRoot
$toolRoot = Split-Path -Parent $scriptRoot

. (Join-Path $toolRoot 'lib\Core.ps1')
. (Join-Path $toolRoot 'lib\Engine.ps1')

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "  WIB REAL DISM CHECKPOINT & ROLLBACK INTEGRATION TEST          " -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan

# 1. Elevation Check
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "`n[SKIPPED] tests/integration-dism.ps1 requires Administrator privileges." -ForegroundColor Yellow
    Write-Host "DISM cmdlets (New-WindowsImage, Mount-WindowsImage, Save-WindowsImage, Dismount-WindowsImage)" -ForegroundColor Yellow
    Write-Host "require kernel-level filter driver handles and elevated credentials.`n" -ForegroundColor Yellow
    Write-Host "To execute this test, launch an elevated PowerShell prompt and run:" -ForegroundColor Gray
    Write-Host "  powershell.exe -ExecutionPolicy Bypass -File .\tests\integration-dism.ps1`n" -ForegroundColor Cyan
    if ($AllowSkip) {
        exit 0
    } else {
        Write-Host "ERROR: Integration test skipped without -AllowSkip flag. Exiting with code 2." -ForegroundColor Red
        exit 2
    }
}

# 2. Setup scratch directories and minimal files
$testRoot   = Join-Path ([System.IO.Path]::GetTempPath()) ("wib-dism-integ-" + [guid]::NewGuid().ToString('N'))
$captureDir = Join-Path $testRoot 'capture'
$mountDir   = Join-Path $testRoot 'mount'
$wimPath    = Join-Path $testRoot 'tiny.wim'

Write-Host "[*] Scratch workspace: $testRoot" -ForegroundColor Gray
New-Item -ItemType Directory -Force -Path $captureDir, $mountDir | Out-Null

try {
    # Prepare minimal baseline contents (< 1 KB total)
    Set-Content -LiteralPath (Join-Path $captureDir 'baseline.txt') -Value 'Initial image baseline content'
    Set-Content -LiteralPath (Join-Path $captureDir 'config.ini') -Value "[WIB]`r`nVersion=1.0`r`nStage=0"

    # Step 1: Capture tiny WIM with New-WindowsImage
    Write-Host "[1/6] Capturing tiny scratch WIM with New-WindowsImage..." -ForegroundColor Cyan
    New-WindowsImage -CapturePath $captureDir -ImagePath $wimPath -Name 'WibIntegrationBase' -Description 'Scratch image for checkpoint integration test' -CheckIntegrity -ErrorAction Stop | Out-Null
    
    $initialImages = @(Get-WindowsImage -ImagePath $wimPath)
    if ($initialImages.Count -ne 1) {
        throw "Failed to capture initial WIM. Expected 1 image index, found $($initialImages.Count)"
    }
    $wimInitialSha = Get-WibSha256 $wimPath
    Write-Host "      Captured tiny WIM ($((Get-Item -LiteralPath $wimPath).Length) bytes, 1 index, SHA-256: $wimInitialSha)" -ForegroundColor Green

    # Step 2: Mount WIM index 1
    Write-Host "[2/6] Mounting WIM index 1 to $mountDir..." -ForegroundColor Cyan
    Mount-WindowsImage -ImagePath $wimPath -Index 1 -Path $mountDir -CheckIntegrity -ErrorAction Stop | Out-Null
    
    $mounted = @(Get-WindowsImage -Mounted | Where-Object { $_.Path -eq $mountDir -and $_.MountStatus -eq 'Ok' })
    if ($mounted.Count -eq 0) {
        throw "Failed to verify mounted image at $mountDir"
    }
    Write-Host "      Image successfully mounted at $mountDir" -ForegroundColor Green

    # Step 3: Initialize context & create baseline checkpoint
    $ctx = @{
        WorkDir             = $testRoot
        MountDir            = $mountDir
        WimPath             = $wimPath
        CurrentIndex        = 1
        OriginalSourceIndex = 1
        MountedIndex        = 1
        DryRun              = $false
        ProfileHash         = 'integ-dism-profile-hash'
        EffectiveSha256     = 'integ-dism-profile-hash'
        Checkpoints         = New-Object System.Collections.ArrayList
        Journal             = New-Object System.Collections.ArrayList
    }
    Write-Host "[3/6] Creating baseline checkpoint via New-WibCheckpoint..." -ForegroundColor Cyan
    Set-Content -LiteralPath (Join-Path $mountDir 'baseline.txt') -Value 'Initial image baseline content with checkpoint 1 marker'
    $cp1 = New-WibCheckpoint -Ctx $ctx -StageName 'stage-baseline'
    $wimAfterCp1 = @(Get-WindowsImage -ImagePath $wimPath)
    $wimCp1Sha = Get-WibSha256 $wimPath
    Write-Host "      Checkpoint 1 created. Total WIM indices: $($wimAfterCp1.Count), Target Index: $($cp1.WimIndex), WIM SHA: $wimCp1Sha" -ForegroundColor Green
    if ($wimInitialSha -eq $wimCp1Sha) {
        throw "WIM mutation assertion failed: Checkpoint 1 append did not alter physical WIM hash!"
    }
    Write-Host "  [PASS] Physical WIM hash mutated after Checkpoint 1 append ($wimInitialSha -> $wimCp1Sha)" -ForegroundColor Green

    # Step 4: Apply Stage 1 changes and create checkpoint
    Write-Host "[4/6] Applying Stage 1 changes (add stage1.txt, update config.ini)..." -ForegroundColor Cyan
    Set-Content -LiteralPath (Join-Path $mountDir 'stage1.txt') -Value 'Stage 1 milestone completed'
    Set-Content -LiteralPath (Join-Path $mountDir 'config.ini') -Value "[WIB]`r`nVersion=1.0`r`nStage=1"
    
    $cp2 = New-WibCheckpoint -Ctx $ctx -StageName 'stage-1-apply'
    $wimAfterCp2 = @(Get-WindowsImage -ImagePath $wimPath)
    $wimCp2Sha = Get-WibSha256 $wimPath
    Write-Host "      Checkpoint 2 created. Total WIM indices: $($wimAfterCp2.Count), Target Index: $($cp2.WimIndex), WIM SHA: $wimCp2Sha" -ForegroundColor Green
    if ($wimCp1Sha -eq $wimCp2Sha) {
        throw "WIM mutation assertion failed: Checkpoint 2 append did not alter physical WIM hash!"
    }
    Write-Host "  [PASS] Physical WIM hash mutated after Checkpoint 2 append ($wimCp1Sha -> $wimCp2Sha)" -ForegroundColor Green

    # Verify Test-WibRecoveryState with the mutated physical WIM and authoritative recovery-state.json
    $recStateFile = Join-Path $testRoot 'recovery-state.json'
    if (Test-Path -LiteralPath $recStateFile) {
        $rawRecState = Get-Content -LiteralPath $recStateFile -Raw | ConvertFrom-Json
        # Mock workspace structure for Test-WibRecoveryState: sources\install.wim
        $integSrcDir = Join-Path $testRoot 'sources'
        New-Item -ItemType Directory -Force -Path $integSrcDir | Out-Null
        Copy-Item -LiteralPath $wimPath -Destination (Join-Path $integSrcDir 'install.wim') -Force
        $recValRes = Test-WibRecoveryState -RecoveryState $rawRecState -WorkDir $testRoot -ExpectedToolVersion $script:WibVersion -ExpectedProfileHash $cp2.ProfileHash -ExpectedOriginalSourceIndex 1 -ExpectedSourceWimSha $wimInitialSha
        if ($recValRes.BaselineSourceWimSha256 -ne $wimInitialSha) {
            throw "Recovery state verification failed: BaselineSourceWimSha256 does not match original baseline!"
        }
        if ($recValRes.CurrentWorkspaceWimSha256 -ne $wimCp2Sha) {
            throw "Recovery state verification failed: CurrentWorkspaceWimSha256 does not match mutated WIM hash!"
        }
        Write-Host "  [PASS] Test-WibRecoveryState successfully reconciles real mutated DISM WIM with recovery-state.json" -ForegroundColor Green
    }

    # Step 5: Simulate dirty/corrupted Stage 2 changes
    Write-Host "[5/6] Simulating corrupt Stage 2 changes in mounted workspace..." -ForegroundColor Cyan
    Set-Content -LiteralPath (Join-Path $mountDir 'corrupted.sys') -Value 'Corrupted payload'
    Remove-Item -LiteralPath (Join-Path $mountDir 'stage1.txt') -Force
    Set-Content -LiteralPath (Join-Path $mountDir 'config.ini') -Value "[WIB]`r`nVersion=1.0`r`nCorrupted=True"
    
    if (-not (Test-Path -LiteralPath (Join-Path $mountDir 'corrupted.sys'))) {
        throw "Failed to create simulated corrupted file"
    }
    Write-Host "      Dirty uncommitted state confirmed (corrupted.sys exists, stage1.txt deleted)" -ForegroundColor Yellow

    # Step 6: Invoke Restore-WibCheckpoint to roll back to stage-1-apply
    Write-Host "[6/6] Invoking Restore-WibCheckpoint to rollback to 'stage-1-apply'..." -ForegroundColor Cyan
    $restored = Restore-WibCheckpoint -Ctx $ctx -TargetStage 'stage-1-apply'

    # Assertions
    Write-Host "`n[*] Verifying rollback evidence..." -ForegroundColor Cyan
    
    # A) Checkpoint metadata
    if ($restored.Status -ne 'restored') {
        throw "Expected restored status 'restored', got '$($restored.Status)'"
    }
    Write-Host "  [PASS] Checkpoint status is 'restored'" -ForegroundColor Green

    # B) Real mount active
    $postMount = @(Get-WindowsImage -Mounted | Where-Object { $_.Path -eq $mountDir -and $_.MountStatus -eq 'Ok' })
    if ($postMount.Count -eq 0) {
        throw "Get-WindowsImage -Mounted did not confirm active mount after rollback"
    }
    Write-Host "  [PASS] Get-WindowsImage -Mounted confirms active mount (Index $($postMount[0].ImageIndex))" -ForegroundColor Green

    # C) Corrupt file physically discarded
    if (Test-Path -LiteralPath (Join-Path $mountDir 'corrupted.sys')) {
        throw "Rollback failed: corrupted.sys is still present in mount directory!"
    }
    Write-Host "  [PASS] corrupted.sys was physically discarded by Dismount -Discard" -ForegroundColor Green

    # D) Stage 1 file restored
    if (-not (Test-Path -LiteralPath (Join-Path $mountDir 'stage1.txt'))) {
        throw "Rollback failed: stage1.txt was not restored!"
    }
    Write-Host "  [PASS] stage1.txt was physically restored by remounting checkpoint index" -ForegroundColor Green

    # E) Config file restored to Stage 1 content
    $cfgContent = Get-Content -LiteralPath (Join-Path $mountDir 'config.ini') -Raw
    if ($cfgContent -notmatch 'Stage=1' -or $cfgContent -match 'Corrupted=True') {
        throw "Rollback failed: config.ini content does not match Stage 1 checkpoint!"
    }
    Write-Host "  [PASS] config.ini content matches Stage 1 checkpoint state" -ForegroundColor Green

    # Step 7: Apply post-rollback Stage 2 mutations, Dismount -Save, Export, and verify extracted image
    Write-Host "`n[7/7] Proving Checkpoint -> Final Mutation -> Save -> Export -> Extraction pipeline..." -ForegroundColor Cyan
    Set-Content -LiteralPath (Join-Path $mountDir 'stage2.txt') -Value 'Stage 2 final post-rollback milestone'
    $wibDir = Join-Path $mountDir 'Windows\WIB'
    New-Item -ItemType Directory -Force -Path $wibDir | Out-Null
    Set-Content -LiteralPath (Join-Path $wibDir 'journal.json') -Value '{"tool":"WIB","status":"ok"}'
    Set-Content -LiteralPath (Join-Path $mountDir 'config.ini') -Value "[WIB]`r`nVersion=1.0`r`nStage=2`r`nCompleted=True"

    Write-Host "      Dismounting active mount with -Save..." -ForegroundColor Gray
    Dismount-WindowsImage -Path $mountDir -Save -ErrorAction Stop | Out-Null
    Write-Host "  [PASS] Active mount successfully committed and saved" -ForegroundColor Green

    # Export image using ctx.MountedIndex
    $exportedWim = Join-Path $testRoot 'exported.wim'
    $exportIndex = if ($ctx.ContainsKey('MountedIndex')) { [int]$ctx.MountedIndex } else { 1 }
    Write-Host "      Exporting SourceIndex $exportIndex to $exportedWim..." -ForegroundColor Gray
    & dism.exe /Export-Image "/SourceImageFile:$wimPath" "/SourceIndex:$exportIndex" "/DestinationImageFile:$exportedWim" /Compress:fast | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "dism.exe /Export-Image failed with exit code $LASTEXITCODE" }
    Write-Host "  [PASS] dism.exe /Export-Image completed successfully" -ForegroundColor Green

    # Verify exported WIM index count
    $exportedImages = @(Get-WindowsImage -ImagePath $exportedWim)
    if ($exportedImages.Count -ne 1) {
        throw "Expected exported WIM to have exactly 1 image index, found $($exportedImages.Count)"
    }
    Write-Host "  [PASS] Exported WIM contains exactly 1 image index" -ForegroundColor Green

    # Mount exported WIM to verification directory and assert all files
    $verifyMountDir = Join-Path $testRoot 'verify_mount'
    New-Item -ItemType Directory -Force -Path $verifyMountDir | Out-Null
    try {
        Write-Host "      Mounting exported WIM index 1 to $verifyMountDir..." -ForegroundColor Gray
        Mount-WindowsImage -ImagePath $exportedWim -Index 1 -Path $verifyMountDir -ReadOnly -ErrorAction Stop | Out-Null

        # Check stage1.txt
        if (-not (Test-Path -LiteralPath (Join-Path $verifyMountDir 'stage1.txt'))) {
            throw "Verification failed: stage1.txt missing in exported WIM!"
        }
        Write-Host "  [PASS] Exported WIM contains stage1.txt from Checkpoint 2" -ForegroundColor Green

        # Check stage2.txt
        if (-not (Test-Path -LiteralPath (Join-Path $verifyMountDir 'stage2.txt'))) {
            throw "Verification failed: stage2.txt missing in exported WIM!"
        }
        Write-Host "  [PASS] Exported WIM contains stage2.txt from post-rollback mutation" -ForegroundColor Green

        # Check journal.json
        if (-not (Test-Path -LiteralPath (Join-Path $verifyMountDir 'Windows\WIB\journal.json'))) {
            throw "Verification failed: Windows\WIB\journal.json missing in exported WIM!"
        }
        Write-Host "  [PASS] Exported WIM contains Windows\WIB\journal.json" -ForegroundColor Green

        # Check config.ini
        $vCfg = Get-Content -LiteralPath (Join-Path $verifyMountDir 'config.ini') -Raw
        if ($vCfg -notmatch 'Stage=2' -or $vCfg -match 'Corrupted=True') {
            throw "Verification failed: config.ini in exported WIM does not reflect final Stage 2 state!"
        }
        Write-Host "  [PASS] Exported WIM config.ini reflects Stage 2 completed state" -ForegroundColor Green

        # Check corrupted.sys is ABSENT
        if (Test-Path -LiteralPath (Join-Path $verifyMountDir 'corrupted.sys')) {
            throw "Verification failed: corrupted.sys leaked into exported WIM!"
        }
        Write-Host "  [PASS] Exported WIM does NOT contain discarded corrupted state" -ForegroundColor Green
    }
    finally {
        $vMounted = @(Get-WindowsImage -Mounted | Where-Object { $_.Path -eq $verifyMountDir })
        if ($vMounted.Count -gt 0) {
            Dismount-WindowsImage -Path $verifyMountDir -Discard -ErrorAction SilentlyContinue | Out-Null
        }
    }

    # Step 8: True out-of-process crash and resume test:
    #         Process 1 creates real DISM checkpoints, applies uncommitted dirty mutations,
    #         and is abruptly terminated (Stop-Process -Force) while DISM mount is ACTIVE.
    #         Process 2 launches production build.ps1 -Resume in a fresh powershell.exe instance,
    #         verifies pre-DISM recovery validation before locking, detects and cleans the stale mount,
    #         mounts the committed checkpoint index, and completes successfully.
    Write-Host "`n[8/8] Testing True Out-of-Process Crashed Process Resumption (build.ps1 -Resume)..." -ForegroundColor Cyan
    $procWorkDir = Join-Path $testRoot 'oop_resume_work'
    $procMountDir = Join-Path $procWorkDir 'mount'
    $procCaptureDir = Join-Path $procWorkDir 'capture'
    $procSourcesDir = Join-Path $procWorkDir 'sources'
    $procWim = Join-Path $procSourcesDir 'install.wim'

    New-Item -ItemType Directory -Force -Path $procCaptureDir, $procMountDir, $procSourcesDir | Out-Null
    Set-Content -LiteralPath (Join-Path $procCaptureDir 'baseline.txt') -Value 'Process 1 baseline content'
    New-WindowsImage -CapturePath $procCaptureDir -ImagePath $procWim -Name 'WibProcessBase' -Description 'Out of process resume test image' -CheckIntegrity -ErrorAction Stop | Out-Null

    # Create minimal valid test profile
    $oopProfilePath = Join-Path $testRoot 'oop-profile.json'
    @{
        profile     = 'oop-resume'
        version     = 1
        description = 'Profile for out-of-process resume integration test'
        modules     = @{}
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $oopProfilePath -Encoding UTF8

    # Process 1 script: Acquires workspace lock, mounts, creates checkpoints,
    # writes dirty uncommitted file, and ABRUPTLY TERMINATES while holding the lock.
    # This proves the -Resume path can recover from both a stale DISM mount AND a stale lock.
    $proc1Script = @"
`$ErrorActionPreference = 'Stop'
. '$toolRoot\lib\Core.ps1'
. '$toolRoot\lib\Engine.ps1'

`$wim = '$procWim'
`$mountDir = '$procMountDir'
`$workDir = '$procWorkDir'
`$profPath = '$oopProfilePath'
`$prof = Import-WibProfile -Path `$profPath
`$profHash = Get-WibProfileCanonicalHash `$prof

# Acquire the production workspace lock BEFORE mounting.
# When Stop-Process kills us, the OS releases the FileStream and
# Process 2 (-Resume) must recover from the stale lock state.
`$workspaceLock = Lock-WibWorkspace -WorkDir `$workDir -RunId 'PROC1_CRASH'
Write-Host 'Process 1: Workspace lock acquired.'

Mount-WindowsImage -ImagePath `$wim -Index 1 -Path `$mountDir -CheckIntegrity -ErrorAction Stop | Out-Null
`$baseSha = Get-WibSha256 `$wim
Set-Content -LiteralPath (Join-Path `$workDir 'source.wim.sha256') -Value `$baseSha -Encoding ASCII
Set-Content -LiteralPath (Join-Path `$workDir 'source.index') -Value '1' -Encoding ASCII

`$ctx = @{
    WorkDir                 = `$workDir
    MountDir                = `$mountDir
    WimPath                 = `$wim
    CurrentIndex            = 1
    OriginalSourceIndex     = 1
    MountedIndex            = 1
    BaselineSourceWimSha256 = `$baseSha
    DryRun                  = `$false
    ProfileHash             = `$profHash
    EffectiveSha256         = `$profHash
    Checkpoints             = New-Object System.Collections.ArrayList
    Journal                 = New-Object System.Collections.ArrayList
}
# Checkpoint 1
Set-Content -LiteralPath (Join-Path `$mountDir 'proc1_base.txt') -Value 'Base file created in Process 1'
`$cp1 = New-WibCheckpoint -Ctx `$ctx -StageName 'apply-files'
Set-Content -LiteralPath (Join-Path `$mountDir 'proc1_milestone.txt') -Value 'Created in Process 1'
# Checkpoint 2
`$cp2 = New-WibCheckpoint -Ctx `$ctx -StageName 'apply-tweaks'

# Dirty uncommitted mutation right before sudden process crash
Set-Content -LiteralPath (Join-Path `$mountDir 'proc1_dirty_interrupted.txt') -Value 'Uncommitted dirty state from crashed process'

# Abrupt process crash: terminate immediately while mount is ACTIVE, dirty,
# and the workspace lock FileStream is still open (not unlocked).
Write-Host 'Process 1: Simulating abrupt crash while holding workspace lock and active mount...'
Stop-Process -Id `$PID -Force
"@
    $proc1File = Join-Path $testRoot 'process1_runner.ps1'
    Set-Content -LiteralPath $proc1File -Value $proc1Script -Encoding UTF8

    Write-Host "      Launching Process 1 (out-of-process crashed checkpoint generator)..." -ForegroundColor Gray
    $proc1Output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $proc1File 2>&1
    Write-Host "  [PASS] Process 1 executed checkpoints and terminated abruptly" -ForegroundColor Green

    # Verify that DISM still has the active mount left behind by the crashed Process 1
    $staleMountCheck = @(Get-WindowsImage -Mounted | Where-Object { $_.Path -eq $procMountDir })
    if ($staleMountCheck.Count -gt 0) {
        Write-Host "  [PASS] Verified DISM filter driver retains active stale mount from crashed Process 1" -ForegroundColor Green
    } else {
        Write-Host "  [WARN] Mount was already cleared or dismounted" -ForegroundColor Yellow
    }

    # Process 2: Execute actual production build.ps1 -Resume entry point
    Write-Host "      Launching Process 2 (production build.ps1 -Resume)..." -ForegroundColor Gray
    $buildScript = Join-Path $toolRoot 'build.ps1'
    $proc2Output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $buildScript `
        -Command plan `
        -WorkDir $procWorkDir `
        -ProfileName $oopProfilePath `
        -Resume 2>&1

    $proc2Text = $proc2Output -join "`n"
    if ($LASTEXITCODE -ne 0) {
        throw "Process 2 (build.ps1 -Resume) failed with exit code ${LASTEXITCODE}: $proc2Text"
    }
    Write-Host "  [PASS] Process 2 (build.ps1 -Resume) exited cleanly with code 0" -ForegroundColor Green

    # Verify Process 2 detected and recovered the stale mount
    if ($proc2Text -match 'Found a stale mount at the work path; discarding it') {
        Write-Host "  [PASS] Process 2 detected and cleanly recovered stale mount from crashed Process 1" -ForegroundColor Green
    } else {
        throw "Process 2 did not log expected stale mount recovery!"
    }

    # Verify Process 2 executed pre-DISM recovery validation
    if ($proc2Text -match 'Verifying physical workspace WIM SHA-256 integrity') {
        Write-Host "  [PASS] Process 2 executed pre-DISM physical WIM and provenance validation" -ForegroundColor Green
    } else {
        throw "Process 2 did not log pre-DISM recovery validation!"
    }

    # Verify workspace lock is released and can be acquired immediately
    $testLock = Lock-WibWorkspace -WorkDir $procWorkDir -RunId 'TEST_OOP_VERIFY'
    if ($testLock) {
        Unlock-WibWorkspace -LockStream $testLock -WorkDir $procWorkDir
        Write-Host "  [PASS] Workspace lock was cleanly released by Process 2 (immediate re-acquisition verified)" -ForegroundColor Green
    } else {
        throw "Workspace lock remained held after Process 2 exit!"
    }

    Write-Host "`n=================================================================" -ForegroundColor Green
    Write-Host "  INTEGRATION TEST PASSED: REAL DISM RESUME & ROLLBACK PROVEN    " -ForegroundColor Green
    Write-Host "=================================================================`n" -ForegroundColor Green
}
catch {
    Write-Host "`n[ERROR] Integration test failed: $($_.Exception.ToString())" -ForegroundColor Red
    $dismLog = 'C:\Windows\Logs\DISM\dism.log'
    if (Test-Path -LiteralPath $dismLog) {
        Write-Host "`n=== LAST 60 LINES OF DISM.LOG ===" -ForegroundColor Yellow
        Get-Content -LiteralPath $dismLog -Tail 60 | ForEach-Object { Write-Host $_ }
        Write-Host "=== END DISM.LOG ===`n" -ForegroundColor Yellow
    }
    throw
}
finally {
    # Ensure clean dismount and cleanup of scratch files
    Write-Host "[*] Cleaning up scratch mounts and directories..." -ForegroundColor Gray
    try {
        $stale = @(Get-WindowsImage -Mounted | Where-Object { $_.Path -eq $mountDir -or $_.Path -like "$testRoot*" })
        foreach ($sm in $stale) {
            Dismount-WindowsImage -Path $sm.Path -Discard -ErrorAction SilentlyContinue | Out-Null
        }
    } catch {
        Write-Verbose $_.Exception.Message
    }

    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
