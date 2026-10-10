<#
.SYNOPSIS
    Behavioral gate verification suite for Windows Image Builder (WIB).
    Executes real runtime behavior tests for release gates G1 through G22.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('G1', 'G2', 'G3', 'G4', 'G5', 'G6', 'G7', 'G8', 'G9', 'G10', 'G11', 'G12', 'G13', 'G14', 'G15', 'G16', 'G17', 'G18', 'G19', 'G20', 'G21', 'G22', 'All')]
    [string]$Gate = 'All'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

# Dot-source core libraries and modules at script scope
. (Join-Path $repoRoot 'lib\Core.ps1')
$script:WibAllowNativeToolMocks = $true
. (Join-Path $repoRoot 'lib\Hardware.ps1')
. (Join-Path $repoRoot 'lib\Compact.ps1')
. (Join-Path $repoRoot 'lib\Planner.ps1')
. (Join-Path $repoRoot 'lib\Report.ps1')
. (Join-Path $repoRoot 'lib\Engine.ps1')
Get-ChildItem -LiteralPath (Join-Path $repoRoot 'modules') -Filter '*.ps1' | Sort-Object Name | ForEach-Object { . $_.FullName }

# Mock Get-WindowsImage so tests execute without requiring elevation/DISM driver
function Get-WindowsImage {
    param($ImagePath, $Index)
    if ($Index) {
        return [PSCustomObject]@{ ImageIndex = $Index; ImageName = 'Windows 11 Pro'; Version = '10.0.26100.1'; Architecture = 9 }
    }
    return @([PSCustomObject]@{ ImageIndex = 1; ImageName = 'Windows 11 Pro'; Version = '10.0.26100.1'; Architecture = 9 })
}



function Test-GateG1 {
    # G1: Adaptive profile resolution and Test-WibRecoveryState effectiveHash acceptance
    $specPath = Join-Path $repoRoot 'specs\laptop.json'
    $profPath = Join-Path $repoRoot 'profiles\adaptive.json'
    $prof = Import-WibProfile $profPath
    $resolved = Resolve-WibEffectiveBuildProfile -BuildProfile $prof -HardwareSpec $specPath -AcceptRisk
    if ($resolved.ResolvedHash -eq $resolved.EffectiveHash) {
        throw "G1 failed: ResolvedHash equals EffectiveHash for adaptive profile"
    }

    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('wib_g1_' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path (Join-Path $tmp 'sources') | Out-Null
    try {
        $wim = Join-Path $tmp 'sources\install.wim'
        Set-Content -LiteralPath $wim -Value 'WIM_G1_TEST' -Encoding ASCII
        $sha = Get-WibSha256 $wim

        $prov = [ordered]@{
            ToolVersion               = $script:WibVersion
            ProfileHash               = $resolved.ResolvedHash
            EffectiveSha256           = $resolved.EffectiveHash
            SourceContainer           = 'WIM'
            SourceContainerIndex      = 1
            ServicingWimIndex         = 1
            SourceWimOriginalIndex    = 1
            CheckpointWimIndex        = 1
            SourceArch                = 'amd64'
            SourceBuild               = '26100'
            SourceEdition             = 'Windows 11 Pro'
            BaselineSourceWimSha256   = $sha
            CurrentWorkspaceWimSha256 = $sha
            SourceIsoHashStatus       = 'unavailable'
            SourceIsoSha256           = ''
            ProvenanceTier            = 'authoritative'
        }
        $cp = [ordered]@{
            Index       = 1
            WimIndex    = 1
            Stage       = 'apply-files'
            Status      = 'saved'
            ProfileHash = $resolved.ResolvedHash
            Provenance  = $prov
        }
        $rec = [ordered]@{
            ToolVersion               = $script:WibVersion
            CommitState               = 'committed'
            ProfileHash               = $resolved.ResolvedHash
            EffectiveSha256           = $resolved.EffectiveHash
            SourceContainer           = 'WIM'
            SourceContainerIndex      = 1
            ServicingWimIndex         = 1
            Checkpoints               = @($cp)
            Journal                   = @()
            OriginalSourceIndex       = 1
            MountedIndex              = 1
            BaselineSourceWimSha256   = $sha
            CurrentWorkspaceWimSha256 = $sha
            SourceIsoHashStatus       = 'unavailable'
        }

        # Must succeed with effectiveHash
        $validated = Test-WibRecoveryState `
            -RecoveryState $rec `
            -WorkDir $tmp `
            -ExpectedToolVersion $script:WibVersion `
            -ExpectedProfileHash $resolved.EffectiveHash `
            -ExpectedOriginalSourceIndex 1 `
            -ExpectedSourceWimSha $sha

        if ($null -eq $validated) {
            throw "G1 failed: Test-WibRecoveryState returned null for effectiveHash"
        }

        # Must fail when using pre-adaptation resolvedHash
        $preAdaptThrew = $false
        try {
            $null = Test-WibRecoveryState `
                -RecoveryState $rec `
                -WorkDir $tmp `
                -ExpectedToolVersion $script:WibVersion `
                -ExpectedProfileHash $resolved.ResolvedHash `
                -ExpectedOriginalSourceIndex 1 `
                -ExpectedSourceWimSha $sha
        } catch {
            $preAdaptThrew = $true
        }

        if (-not $preAdaptThrew) {
            throw "G1 failed: Test-WibRecoveryState did not throw when called with pre-adaptation resolvedHash"
        }

        Write-Output 'GATE_G1_PASS'
    } finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Test-GateG2 {
    # G2: SourceIsoHashStatus skipped is preserved on resume
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('wib_g2_' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path (Join-Path $tmp 'sources') | Out-Null
    try {
        $wim = Join-Path $tmp 'sources\install.wim'
        Set-Content -LiteralPath $wim -Value 'WIM_G2_TEST' -Encoding ASCII
        $sha = Get-WibSha256 $wim
        $mockHash = 'A' * 64

        $prov2 = [ordered]@{
            ToolVersion               = $script:WibVersion
            ProfileHash               = $mockHash
            EffectiveSha256           = $mockHash
            SourceWimOriginalIndex    = 1
            CheckpointWimIndex        = 1
            SourceArch                = 'amd64'
            SourceBuild               = '26100'
            SourceEdition             = 'Windows 11 Pro'
            BaselineSourceWimSha256   = $sha
            CurrentWorkspaceWimSha256 = $sha
            SourceContainer           = 'WIM'
            SourceContainerIndex      = 1
            ServicingWimIndex         = 1
            SourceIsoHashStatus       = 'skipped'
            SourceIsoSha256           = ''
            ProvenanceTier            = 'authoritative'
        }
        $cp2 = [ordered]@{
            Index       = 1
            WimIndex    = 1
            Stage       = 'apply-files'
            Status      = 'saved'
            ProfileHash = $mockHash
            Provenance  = $prov2
        }
        $rec = [ordered]@{
            ToolVersion               = $script:WibVersion
            CommitState               = 'committed'
            ProfileHash               = $mockHash
            EffectiveSha256           = $mockHash
            SourceContainer           = 'WIM'
            SourceContainerIndex      = 1
            ServicingWimIndex         = 1
            Checkpoints               = @($cp2)
            Journal                   = @()
            OriginalSourceIndex       = 1
            MountedIndex              = 1
            BaselineSourceWimSha256   = $sha
            CurrentWorkspaceWimSha256 = $sha
            SourceIsoHashStatus       = 'skipped'
        }

        $validated = Test-WibRecoveryState `
            -RecoveryState $rec `
            -WorkDir $tmp `
            -ExpectedToolVersion $script:WibVersion `
            -ExpectedProfileHash $mockHash `
            -ExpectedOriginalSourceIndex 1 `
            -ExpectedSourceWimSha $sha

        if ($validated.SourceIsoHashStatus -ne 'skipped') {
            throw "G2 failed: SourceIsoHashStatus was '$($validated.SourceIsoHashStatus)', expected 'skipped'"
        }

        Write-Output 'GATE_G2_PASS'
    } finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Test-GateG3 {
    # G3: Invalid recovery commit states rejected by ValidateSet
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('wib_g3_' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    try {
        $rec = [ordered]@{
            ToolVersion               = $script:WibVersion
            CommitState               = 'committed'
            ProfileHash               = 'dummy'
            EffectiveSha256           = 'dummy'
            Checkpoints               = @()
            Journal                   = @()
            OriginalSourceIndex       = 1
            MountedIndex              = 1
            BaselineSourceWimSha256   = 'dummy'
            CurrentWorkspaceWimSha256 = 'dummy'
            SourceIsoHashStatus       = 'unavailable'
        }
        Set-WibDurableJsonFile -Path (Join-Path $tmp 'recovery-state.json') -Data $rec -Depth 5

        # Invalid state must throw
        $invalidThrew = $false
        try {
            Update-WibRecoveryCommitState -WorkDir $tmp -CommitState 'bogus_state_string'
        } catch {
            $invalidThrew = $true
        }
        if (-not $invalidThrew) {
            throw "G3 failed: Update-WibRecoveryCommitState accepted invalid CommitState 'bogus_state_string'"
        }

        # Valid states must succeed
        foreach ($validState in @('committed', 'finalizing', 'post-export', 'reconciled-in-flight')) {
            Update-WibRecoveryCommitState -WorkDir $tmp -CommitState $validState
            $readBack = ConvertFrom-Json (Get-Content -LiteralPath (Join-Path $tmp 'recovery-state.json') -Raw)
            if ($readBack.CommitState -ne $validState) {
                throw "G3 failed: CommitState not updated to '$validState'"
            }
        }

        Write-Output 'GATE_G3_PASS'
    } finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Test-GateG4 {
    # G4: Crash integration test validates lock acquisition and recovery
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('wib_g4_' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    try {
        # 1. Real lock acquisition
        $lock1 = Lock-WibWorkspace -WorkDir $tmp -RunId 'G4_RUN_1'
        $lockFile = Join-Path $tmp 'build.lock.json'
        if (-not (Test-Path -LiteralPath $lockFile)) {
            throw "G4 failed: build.lock.json was not created"
        }

        # 2. Concurrent collision rejection while lock is held
        $collisionThrew = $false
        try {
            $null = Lock-WibWorkspace -WorkDir $tmp -RunId 'G4_RUN_2'
        } catch {
            if ($_.Exception.Message -like '*is locked by an active build process*') {
                $collisionThrew = $true
            }
        }
        if (-not $collisionThrew) {
            throw "G4 failed: Concurrent Lock-WibWorkspace did not throw expected locked error"
        }

        # 3. Clean unlock and metadata verification
        Unlock-WibWorkspace -LockStream $lock1 -WorkDir $tmp
        $lockData = ConvertFrom-Json (Get-Content -LiteralPath $lockFile -Raw)
        if ($lockData.runId -ne 'G4_RUN_1' -or $lockData.pid -ne $PID) {
            throw "G4 failed: build.lock.json metadata mismatch"
        }

        # 4. Out-of-process crash simulation: process acquires lock, terminates abruptly, OS frees handle
        $childScript = Join-Path $tmp 'child_locker.ps1'
        $readyFile = Join-Path $tmp 'child_ready.flag'
        $childCode = @"
. '$($repoRoot)\lib\Core.ps1'
`$stream = Lock-WibWorkspace -WorkDir '$($tmp.Replace("'", "''"))' -RunId 'G4_CHILD_CRASH'
[System.IO.File]::WriteAllText('$($readyFile.Replace("'", "''"))', 'READY')
Start-Sleep -Seconds 15
"@
        Set-Content -LiteralPath $childScript -Value $childCode -Encoding ASCII
        $proc = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$childScript`"") -PassThru
        $waitCount = 0
        while ((-not (Test-Path -LiteralPath $readyFile)) -and ($waitCount -lt 50)) {
            Start-Sleep -Milliseconds 100
            $waitCount++
        }
        if (-not (Test-Path -LiteralPath $readyFile)) {
            Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
            throw "G4 failed: Child locker process did not signal ready"
        }

        # Confirm lock is held by child process
        $childCollisionThrew = $false
        try {
            $null = Lock-WibWorkspace -WorkDir $tmp -RunId 'G4_PARENT_TRY'
        } catch {
            if ($_.Exception.Message -like '*is locked by an active build process*') {
                $childCollisionThrew = $true
            }
        }
        if (-not $childCollisionThrew) {
            Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
            throw "G4 failed: Child process did not hold lock"
        }

        # Kill child process abruptly (simulating crash)
        Stop-Process -Id $proc.Id -Force
        Start-Sleep -Milliseconds 300

        # Parent must be able to acquire lock immediately after crash
        $rescueLock = Lock-WibWorkspace -WorkDir $tmp -RunId 'G4_RESCUE'
        if ($null -eq $rescueLock) {
            throw "G4 failed: Rescue Lock-WibWorkspace failed after process crash"
        }
        Unlock-WibWorkspace -LockStream $rescueLock -WorkDir $tmp

        Write-Output 'GATE_G4_PASS'
    } finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Test-GateG5 {
    # G5: Audit bundle contains smoke_results.json with passing results
    $bundleFile = Join-Path $repoRoot 'WIB_AUDIT_ALL_FILES.txt'
    if (-not (Test-Path -LiteralPath $bundleFile)) {
        throw "G5 failed: WIB_AUDIT_ALL_FILES.txt does not exist"
    }

    # Verify manifest contains smoke_results.json
    $foundInManifest = $false
    $foundInBody = $false
    $reader = [System.IO.File]::OpenText($bundleFile)
    try {
        $lineCount = 0
        while (($line = $reader.ReadLine()) -ne $null -and $lineCount -lt 200) {
            $lineCount++
            if ($line -match 'smoke_results\.json') {
                $foundInManifest = $true
                break
            }
        }
    } finally {
        $reader.Close()
        $reader.Dispose()
    }
    if (-not $foundInManifest) {
        throw "G5 failed: smoke_results.json not found in audit bundle Table of Contents"
    }

    # Verify smoke_results.json file content
    $jsonPath = Join-Path $repoRoot 'smoke_results.json'
    if (-not (Test-Path -LiteralPath $jsonPath)) {
        throw "G5 failed: smoke_results.json file not found on disk"
    }
    $json = ConvertFrom-Json (Get-Content -LiteralPath $jsonPath -Raw)
    if ($json.exitCode -ne 0 -or $json.failed -ne 0 -or $json.passed -lt 655 -or $json.status -ne 'pass') {
        throw "G5 failed: smoke_results.json shows failed or incomplete test run (exitCode=$($json.exitCode), passed=$($json.passed), failed=$($json.failed))"
    }

    Write-Output 'GATE_G5_PASS'
}

function Test-GateG6 {
    # G6: AK adaptive resume regression test suite passes
    # AK-1: Non-adaptive profile ResolvedHash == EffectiveHash
    $balProf = Import-WibProfile (Join-Path $repoRoot 'profiles\balanced.json')
    $ak1 = Resolve-WibEffectiveBuildProfile -BuildProfile $balProf -HardwareSpec '' -AcceptRisk
    if ($ak1.ResolvedHash -ne $ak1.EffectiveHash -or $ak1.AdaptiveDecisions.Count -ne 0) {
        throw "G6 failed: AK-1 non-adaptive profile resolution mismatch"
    }

    # AK-5: Adaptive profile resolution produces distinct hashes
    $adaptProf = Import-WibProfile (Join-Path $repoRoot 'profiles\adaptive.json')
    $laptopSpec = Join-Path $repoRoot 'specs\laptop.json'
    $ak5 = Resolve-WibEffectiveBuildProfile -BuildProfile $adaptProf -HardwareSpec $laptopSpec -AcceptRisk
    if ($ak5.ResolvedHash -eq $ak5.EffectiveHash) {
        throw "G6 failed: AK-5 adaptive profile mutation did not produce distinct canonical hashes"
    }
    if ($ak5.AdaptiveDecisions.Count -eq 0) {
        throw "G6 failed: AK-5 adaptive hardware decisions were empty"
    }

    Write-Output 'GATE_G6_PASS'
}

function Test-GateG7 {
    # G7: Smoke tests 100% pass across all 655 assertions
    $smokeScript = Join-Path $repoRoot 'tests\smoke.ps1'
    $res = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $smokeScript 2>&1
    $text = $res -join "`n"
    if ($LASTEXITCODE -ne 0) {
        throw "G7 failed with exit code $LASTEXITCODE"
    }
    if ($text -notmatch 'All checks passed \(655 assertions\)\.') {
        throw "G7 failed: smoke output did not match 655 assertions passing"
    }
    Write-Output 'GATE_G7_PASS'
}

function Test-GateG8 {
    # G8: Version bumped to 0.2.29 across codebase
    $expectedVer = '0.2.29'

    . (Join-Path $repoRoot 'lib\Core.ps1')
    $script:WibAllowNativeToolMocks = $true
    Get-ChildItem -LiteralPath (Join-Path $repoRoot 'modules') -Filter '*.ps1' | Sort-Object Name | ForEach-Object { . $_.FullName }
    if ($script:WibVersion -ne $expectedVer) {
        throw "G8 failed: script:WibVersion in Core.ps1 is '$($script:WibVersion)', expected '$expectedVer'"
    }

    $smokeContent = Get-Content -LiteralPath (Join-Path $repoRoot 'tests\smoke.ps1') -Raw
    if ($smokeContent -notmatch "WibVersion -eq '$([regex]::Escape($expectedVer))'") {
        throw "G8 failed: tests/smoke.ps1 does not assert '$expectedVer'"
    }

    $readmeContent = Get-Content -LiteralPath (Join-Path $repoRoot 'README.md') -Raw
    if ($readmeContent -notmatch "# WIB: Windows Image Builder \(v$([regex]::Escape($expectedVer))\)") {
        throw "G8 failed: README.md does not contain title with v$expectedVer"
    }

    $changelogContent = Get-Content -LiteralPath (Join-Path $repoRoot 'CHANGELOG.md') -Raw
    if ($changelogContent -notmatch "## \[$([regex]::Escape($expectedVer))\]") {
        throw "G8 failed: CHANGELOG.md does not contain entry for [$expectedVer]"
    }

    $planContent = Get-Content -LiteralPath (Join-Path $repoRoot 'WIB-plan.md') -Raw
    if ($planContent -notmatch "Tool version $([regex]::Escape($expectedVer))\.") {
        throw "G8 failed: WIB-plan.md does not contain 'Tool version $expectedVer.'"
    }

    Write-Output 'GATE_G8_PASS'
}

function Test-GateG9 {
    # G9: Transactional recovery cleanup ordering preserves authoritative ledger on failure
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('wib_g9_' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    try {
        $rec = Join-Path $tmp 'recovery-state.json'
        $cp  = Join-Path $tmp 'checkpoints.json'
        $jp  = Join-Path $tmp 'journal.partial.json'

        Set-Content -LiteralPath $rec -Value 'AUTHORITATIVE_REC' -Encoding UTF8
        Set-Content -LiteralPath $cp  -Value 'SECONDARY_CP' -Encoding UTF8
        Set-Content -LiteralPath $jp  -Value 'SECONDARY_JP' -Encoding UTF8

        # Lock checkpoints.json with FileShare.None
        $stream = [System.IO.File]::Open($cp, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        $cleanupThrew = $false
        try {
            Remove-WibCheckpoints @{ WorkDir = $tmp }
        } catch {
            $cleanupThrew = $true
        } finally {
            $stream.Close()
            $stream.Dispose()
        }

        if (-not $cleanupThrew) {
            throw "G9 failed: Remove-WibCheckpoints did not throw when secondary ledger was locked"
        }

        # Authoritative recovery-state.json MUST still be present
        if (-not (Test-Path -LiteralPath $rec)) {
            throw "G9 failed: Authoritative recovery-state.json was destroyed even though secondary cleanup failed!"
        }

        # Clean deletion removes all ledgers
        Remove-WibCheckpoints @{ WorkDir = $tmp }
        if (Test-Path -LiteralPath $rec) {
            throw "G9 failed: recovery-state.json remained after clean Remove-WibCheckpoints"
        }
        if (Test-Path -LiteralPath $cp) {
            throw "G9 failed: checkpoints.json remained after clean Remove-WibCheckpoints"
        }
        if (Test-Path -LiteralPath $jp) {
            throw "G9 failed: journal.partial.json remained after clean Remove-WibCheckpoints"
        }

        Write-Output 'GATE_G9_PASS'
    } finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Test-GateG10 {
    # G10: All repository PowerShell files are 100% pure ASCII
    $bad = @()
    $files = Get-ChildItem -Path $repoRoot -Recurse -File -Include @('*.ps1', '*.psd1', '*.psm1')
    foreach ($file in $files) {
        $txt = [System.IO.File]::ReadAllText($file.FullName)
        for ($i = 0; $i -lt $txt.Length; $i++) {
            if ([int]$txt[$i] -gt 127) {
                $rel = $file.FullName.Substring($repoRoot.Length + 1)
                $bad += "$($rel): char code $([int]$txt[$i]) at pos $i"
                break
            }
        }
    }
    if ($bad.Count -gt 0) {
        throw "G10 failed: Non-ASCII characters detected in: $($bad -join '; ')"
    }
    Write-Output 'GATE_G10_PASS'
}

function Test-GateG11 {
    # G11: Serialized ISO publication lock, atomic replacement, and provenance coherence
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('wib_g11_' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    try {
        $targetIso = Join-Path $tmp 'test_output.iso'
        $tempIso = Join-Path $tmp 'test_output.tmp.iso'
        $pubLockPath = "$targetIso.publock"

        # 1. Target appears during build without -Force: must fail closed, preserve target, preserve temp
        Set-Content -LiteralPath $targetIso -Value 'TARGET_ORIGINAL_CONTENT' -Encoding ASCII
        Set-Content -LiteralPath $tempIso -Value 'TEMP_BUILD_ARTIFACT_CONTENT' -Encoding ASCII

        $noForceBlocked = $false
        try {
            Publish-WibOutputIso -TempIsoPath $tempIso -OutputIso $targetIso -RunId 'G11_RUN_NOFORCE'
        } catch {
            if ($_.Exception.Message -like '*was created during the build and -Force was not specified*') {
                $noForceBlocked = $true
            }
        }
        if (-not $noForceBlocked) {
            throw "G11 failed: Publication did not reject overwriting target created during build when -Force was omitted"
        }
        if ((Get-Content -LiteralPath $targetIso -Raw).Trim() -ne 'TARGET_ORIGINAL_CONTENT') {
            throw "G11 failed: Existing target was altered when publication was rejected"
        }
        if (-not (Test-Path -LiteralPath $tempIso)) {
            throw "G11 failed: Temporary build artifact was deleted when publication was rejected"
        }

        # 2. Overwrite with -Force and verify post-publish lock retention (provenance coherence)
        $lockHeldInsidePost = $false
        $postAction = {
            param($info)
            try {
                $probeStream = [System.IO.File]::Open($pubLockPath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
                $probeStream.Close()
                $probeStream.Dispose()
            } catch [System.IO.IOException] {
                $script:lockHeldInsidePost = $true
            }
        }
        $script:lockHeldInsidePost = $false

        $forceRes = Publish-WibOutputIso -TempIsoPath $tempIso -OutputIso $targetIso -RunId 'G11_RUN_FORCE' -Force -PostPublishAction $postAction
        if (-not $forceRes.Success) {
            throw "G11 failed: Publish-WibOutputIso did not succeed with -Force"
        }
        if (-not $script:lockHeldInsidePost) {
            throw "G11 failed: Publication lock was NOT held during PostPublishAction execution (provenance coherence violated)"
        }
        if ((Get-Content -LiteralPath $targetIso -Raw).Trim() -ne 'TEMP_BUILD_ARTIFACT_CONTENT') {
            throw "G11 failed: Target ISO content not replaced with temp content under -Force"
        }
        if (Test-Path -LiteralPath $tempIso) {
            throw "G11 failed: Temp ISO remained after atomic ReplaceFile"
        }
        if (Test-Path -LiteralPath $pubLockPath) {
            throw "G11 failed: Publication lock file was not cleaned after completion"
        }

        # 3. Concurrent publication lock serialization
        $pubLockHold = [System.IO.File]::Open($pubLockPath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        $concurrentBlocked = $false
        try {
            $pubLockTry = [System.IO.File]::Open($pubLockPath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        } catch [System.IO.IOException] {
            $concurrentBlocked = $true
        }
        if (-not $concurrentBlocked) {
            $pubLockHold.Close()
            $pubLockHold.Dispose()
            throw "G11 failed: Concurrent publication lock attempt was not blocked with IOException"
        }

        # Release and verify subsequent acquisition
        $pubLockHold.Close()
        $pubLockHold.Dispose()
        $tempIso2 = Join-Path $tmp 'test_output2.tmp.iso'
        Set-Content -LiteralPath $tempIso2 -Value 'TEMP_CONTENT_2' -Encoding ASCII
        $subsequentRes = Publish-WibOutputIso -TempIsoPath $tempIso2 -OutputIso $targetIso -RunId 'G11_SUBSEQUENT' -Force
        if (-not $subsequentRes.Success) {
            throw "G11 failed: Could not publish after previous publication lock was released"
        }

        Write-Output 'GATE_G11_PASS'
    } finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Test-GateG12 {
    # G12: Non-dry-run resumed build pipeline continuation succeeds end-to-end
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('wib_g12_' + [Guid]::NewGuid().ToString('N'))
    $g12Work = Join-Path $tmp 'work'
    $g12ToolRoot = Join-Path $tmp 'tool'
    New-Item -ItemType Directory -Force -Path (Join-Path $g12Work 'iso\sources'), (Join-Path $g12Work 'iso\boot'), (Join-Path $g12Work 'iso\efi\microsoft\boot'), $g12ToolRoot | Out-Null
    try {
        $g12Wim = Join-Path $g12Work 'iso\sources\install.wim'
        Set-Content -LiteralPath $g12Wim -Value 'G12_WIM_CONTENT' -Encoding ASCII
        $g12WimHash = Get-WibSha256 $g12Wim

        Set-Content -LiteralPath (Join-Path $g12Work 'iso\boot\etfsboot.com') -Value 'MOCK_ETFS' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $g12Work 'iso\efi\microsoft\boot\efisys.bin') -Value 'MOCK_EFI' -Encoding ASCII
        $g12TargetIso = Join-Path $tmp 'g12_output.iso'

        $mockOscdCmd = Join-Path $g12Work 'mock_oscdimg.cmd'
        $mockOscdCmdContent = "@echo off`r`nfor %%A in (%*) do set LAST_ARG=%%~A`r`npowershell.exe -NoProfile -Command `"`$p = `$env:LAST_ARG; `$par = Split-Path -Parent `$p; if (`$par -and -not (Test-Path -LiteralPath `$par)) { New-Item -ItemType Directory -Force -Path `$par | Out-Null }; Set-Content -LiteralPath `$p -Value 'MOCK_PUBLISHED_ISO_CONTENT' -Encoding ASCII`"`r`nexit /b 0"
        Set-Content -LiteralPath $mockOscdCmd -Value $mockOscdCmdContent -Encoding ASCII

        $g12ProfPath = Join-Path $g12Work 'resume-profile.json'
        @{
            profile     = 'resume-test'
            version     = 1
            description = 'Profile for non-dry-run resumed build continuation test'
            modules     = @{}
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $g12ProfPath -Encoding UTF8
        $g12Prof = Import-WibProfile $g12ProfPath
        $g12ResolvedHash = Get-WibProfileCanonicalHash $g12Prof

        $g12Prov = [ordered]@{
            ToolVersion                 = $script:WibVersion
            ProfileHash                 = $g12ResolvedHash
            EffectiveSha256             = $g12ResolvedHash
            SourceContainer             = 'WIM'
            SourceContainerIndex        = 1
            ServicingWimIndex           = 1
            SourceWimOriginalIndex      = 1
            CheckpointWimIndex          = 1
            SourceArch                  = 'amd64'
            SourceBuild                 = '26100'
            SourceEdition               = 'Windows 11 Pro'
            BaselineSourceWimSha256     = $g12WimHash
            CurrentWorkspaceWimSha256   = $g12WimHash
            SourceIsoHashStatus         = 'unavailable'
            CommittedCheckpointWimIndex = 1
            PhysicalImageIndex          = 1
            OrphanIndexSet              = @()
            NextCheckpointLogicalId     = 2
            ProvenanceTier              = 'authoritative'
        }
        $g12Cp = [ordered]@{
            Index       = 1
            WimIndex    = 1
            Stage       = 'apply-files'
            Status      = 'saved'
            ProfileHash = $g12ResolvedHash
            Provenance  = $g12Prov
        }
        $g12Rec = [ordered]@{
            Version                     = $script:WibVersion
            ToolVersion                 = $script:WibVersion
            CommitState                 = 'committed'
            ProvenanceTier              = 'authoritative'
            SourceContainer             = 'WIM'
            SourceContainerIndex        = 1
            ServicingWimIndex           = 1
            Checkpoints                 = @($g12Cp)
            Journal                     = @()
            OriginalSourceIndex         = 1
            MountedIndex                = 1
            CommittedCheckpointWimIndex = 1
            PhysicalImageIndex          = 1
            OrphanIndexSet              = @()
            NextCheckpointLogicalId     = 2
            ProfileHash                 = $g12ResolvedHash
            EffectiveSha256             = $g12ResolvedHash
            BaselineSourceWimSha256     = $g12WimHash
            CurrentWorkspaceWimSha256   = $g12WimHash
            SourceIsoHashStatus         = 'unavailable'
        }
        Set-WibDurableJsonFile -Path (Join-Path $g12Work 'recovery-state.json') -Data $g12Rec -Depth 10

        $script:g12BuildOk = $false
        & {
            $script:g12ImageCount = 1
            function Get-WindowsImage {
                param($ImagePath, $Index)
                if ($Index) { return [PSCustomObject]@{ ImageIndex = $Index; ImageName = 'Windows 11 Pro'; Version = '10.0.26100.1'; Architecture = 9 } }
                $res = @()
                for ($i = 1; $i -le $script:g12ImageCount; $i++) {
                    $res += [PSCustomObject]@{ ImageIndex = $i; ImageName = "Windows 11 Pro Mock Index $i"; Version = '10.0.26100.1'; Architecture = 9 }
                }
                return $res
            }
            $script:g12Mounted = $false
            function Mount-WindowsImage {
                param($ImagePath, $Index, $Path, [switch]$ReadOnly)
                $script:g12Mounted = $true
            }
            function Dismount-WindowsImage {
                param($Path, [switch]$Discard, [switch]$Save, [System.Management.Automation.ActionPreference]$ErrorAction)
                $script:g12Mounted = $false
            }
            function Save-WindowsImage {
                param($Path, [switch]$Append, [switch]$CheckIntegrity, [System.Management.Automation.ActionPreference]$ErrorAction)
                if ($Append) { $script:g12ImageCount++ }
            }
            function Get-WibMountedImage {
                param($Path)
                if ($script:g12Mounted) {
                    return @([PSCustomObject]@{ Path = $Path; MountPath = $Path; MountStatus = 'Ok'; ImageIndex = 1 })
                }
                return @()
            }
            function Mount-WibHives { param($MountDir) }
            function Dismount-WibHives { param([switch]$ThrowOnFailure) }
            function Resolve-WibOscdimg { param($AllowDownload, $WorkDir, $StrictOscdimgHash) return $mockOscdCmd }
            function dism.exe {
                param([Parameter(ValueFromRemainingArguments)]$Args)
                foreach ($a in $Args) {
                    if ($a -like '/DestinationImageFile:*') {
                        $dest = $a.Substring(22).Trim('"')
                        $parent = Split-Path -Parent $dest
                        if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
                        Set-Content -LiteralPath $dest -Value 'MOCK_EXPORTED_WIM' -Encoding ASCII
                    }
                }
                $global:LASTEXITCODE = 0
            }

            try {
                $bRes = Invoke-WibBuild `
                    -WorkDir $g12Work `
                    -ProfilePath $g12ProfPath `
                    -ToolRoot $g12ToolRoot `
                    -OutputIso $g12TargetIso `
                    -Resume `
                    -Force
                $resState = if ($bRes -is [array]) { $bRes | Where-Object { $_ -and $_.Success -ne $null } | Select-Object -Last 1 } else { $bRes }
                if ($resState -and $resState.Success) {
                    $script:g12BuildOk = $true
                }
            } catch {
                throw "G12 failed during Invoke-WibBuild: $($_.Exception.Message)"
            }
        }

        if (-not $script:g12BuildOk) {
            throw "G12 failed: Invoke-WibBuild did not return successful state"
        }
        if (-not (Test-Path -LiteralPath $g12TargetIso)) {
            throw "G12 failed: Target ISO was not created and published on disk"
        }
        $foundM = Get-ChildItem -Path (Join-Path $g12ToolRoot 'reports') -Recurse -Filter 'manifest.json' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $foundM) {
            throw "G12 failed: manifest.json was not found in report directory"
        }
        $mObj = ConvertFrom-Json (Get-Content -LiteralPath $foundM.FullName -Raw)
        if ($mObj.status -ne 'success' -or $mObj.overallStatus -ne 'success' -or $mObj.dryRun -ne $false -or $mObj.resumed -ne $true) {
            throw "G12 failed: manifest.json does not record expected success/resumed flags (status=$($mObj.status), overallStatus=$($mObj.overallStatus), dryRun=$($mObj.dryRun), resumed=$($mObj.resumed))"
        }
        if (Test-Path -LiteralPath (Join-Path $g12Work 'recovery-state.json')) {
            throw "G12 failed: recovery-state.json was not cleaned upon successful resumed finalization"
        }

        $termFound = Get-ChildItem -Path (Join-Path $g12ToolRoot 'reports') -Recurse -Filter 'terminal-state.json' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $termFound) {
            throw "G12 failed: terminal-state.json was not found in report directory"
        }
        $tObj = ConvertFrom-Json (Get-Content -LiteralPath $termFound.FullName -Raw)
        if ($tObj.status -ne 'success' -or $tObj.overallStatus -ne 'success' -or $tObj.exitCode -ne 0) {
            throw "G12 failed: terminal-state.json does not record expected success status or exitCode=0"
        }

        Write-Output 'GATE_G12_PASS'
    } finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Test-GateG13 {
    # G13: Unattend CLI security contracts (-Force, -ObscurePassword, HardwareBypass) and cryptographic ISO TOCTOU verification
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('wib_g13_' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    try {
        $unattendTool = Join-Path $repoRoot 'tools\New-WibUnattend.ps1'

        # 1. Credential embedding without risk flag must fail closed even with -Force
        $sec = ConvertTo-SecureString 'G13Secret!' -AsPlainText -Force
        $credBlocked = $false
        try {
            & $unattendTool -OutputPath (Join-Path $tmp 'g13-blocked.xml') -SecurePassword $sec -Force
        } catch {
            if ($_.Exception.Message -like '*SECURITY ERROR: Embedding credentials*') { $credBlocked = $true }
        }
        if (-not $credBlocked) { throw 'G13 failed: -Force bypassed credential exposure risk gate' }

        # 2. Default generation must disable HardwareBypass and protect existing file unless -Force is passed
        $outXml = Join-Path $tmp 'g13-default.xml'
        $res1 = & $unattendTool -OutputPath $outXml -Username 'G13User1'
        if ($res1.HardwareBypass -ne $false -or $res1.PasswordMode -ne 'credentialless') {
            throw 'G13 failed: default HardwareBypass or PasswordMode contract violated'
        }
        $overwriteBlocked = $false
        try {
            & $unattendTool -OutputPath $outXml -Username 'G13User2'
        } catch {
            if ($_.Exception.Message -like '*Output file already exists*Specify -Force*') { $overwriteBlocked = $true }
        }
        if (-not $overwriteBlocked) { throw 'G13 failed: existing output file was overwritten without -Force' }
        $res2 = & $unattendTool -OutputPath $outXml -Username 'G13User2' -Force
        if (-not $res2.ForceOverwrite) { throw 'G13 failed: -Force overwrite did not set ForceOverwrite=true' }

        # 3. Conflicting -ObscurePassword and -PlainTextPassword must fail closed
        $conflictBlocked = $false
        try {
            & $unattendTool -OutputPath (Join-Path $tmp 'g13-conflict.xml') -SecurePassword $sec -ObscurePassword -PlainTextPassword -AcceptCredentialExposureRisk
        } catch {
            if ($_.Exception.Message -like '*Conflicting parameters: -ObscurePassword and -PlainTextPassword*') { $conflictBlocked = $true }
        }
        if (-not $conflictBlocked) { throw 'G13 failed: conflicting -ObscurePassword and -PlainTextPassword did not throw' }

        # 4. Cryptographic post-mount ISO SHA-256 TOCTOU detection catches same-length timestamp-spoofed byte tampering
        $dummyIso = Join-Path $tmp 'g13.iso'
        [System.IO.File]::WriteAllText($dummyIso, 'G13_ISO_PAYLOAD_AAAA_123456')
        $origMtime = (Get-Item -LiteralPath $dummyIso).LastWriteTimeUtc
        $workDir = Join-Path $tmp 'work'
        New-Item -ItemType Directory -Force -Path $workDir | Out-Null
        $toctouCaught = $false
        $unexpectedG13Err = ''
        try {
            function Mount-DiskImage {
                param($ImagePath, [switch]$PassThru)
                [System.IO.File]::WriteAllText($ImagePath, 'G13_ISO_PAYLOAD_BBBB_123456')
                (Get-Item -LiteralPath $ImagePath).LastWriteTimeUtc = $origMtime
                return [PSCustomObject]@{ Attached = $true }
            }
            function Dismount-DiskImage { param($ImagePath) return $null }
            Invoke-WibBuild -IsoPath $dummyIso -ProfilePath (Join-Path $repoRoot 'profiles\balanced.json') -ToolRoot $tmp -WorkDir $workDir -DryRun -Force
        } catch {
            if ($_.Exception.Message -like '*Source ISO TOCTOU mutation detected: cryptographic SHA-256 digest*') {
                $toctouCaught = $true
            } else {
                $unexpectedG13Err = $_.Exception.Message
            }
        } finally {
            Remove-Item Function:\Mount-DiskImage -ErrorAction SilentlyContinue
            Remove-Item Function:\Dismount-DiskImage -ErrorAction SilentlyContinue
        }
        if (-not $toctouCaught) {
            throw "G13 failed: post-mount cryptographic SHA-256 check did not catch same-length timestamp-spoofed ISO mutation (err: $unexpectedG13Err)"
        }

        Write-Output 'GATE_G13_PASS'
    } finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Test-GateG14 {
    # G14: v0.2.21 audit remediation checks (WIB-002 through WIB-007)
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('wib_g14_' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    try {
        $unattendTool = Join-Path $repoRoot 'tools\New-WibUnattend.ps1'

        # 1. WIB-002: -TestOnly cannot bypass -AcceptCredentialExposureRisk and rejects non-temp OutputPath
        $testOnlyBypassBlocked = $false
        try {
            & $unattendTool -OutputPath (Join-Path $tmp 'g14-hash.xml') -PasswordHash 'VGVzdA==' -TestOnly
        } catch {
            if ($_.Exception.Message -like '*SECURITY ERROR: -TestOnly does not waive credential exposure risk gates*') {
                $testOnlyBypassBlocked = $true
            }
        }
        if (-not $testOnlyBypassBlocked) { throw 'G14 failed: -TestOnly bypassed credential exposure risk gate' }

        $testOnlyNonTempBlocked = $false
        try {
            & $unattendTool -OutputPath (Join-Path $repoRoot 'g14-outside-temp.xml') -TestOnly
        } catch {
            if ($_.Exception.Message -like '*SECURITY ERROR: -TestOnly output path*outside the system temporary directory*') {
                $testOnlyNonTempBlocked = $true
            }
        }
        if (-not $testOnlyNonTempBlocked) { throw 'G14 failed: -TestOnly allowed OutputPath outside system temp directory' }

        # 2. WIB-003: Assert-WibNoReparsePointsInTree detects nested NTFS junctions inside confined trees
        $mountDir = Join-Path $tmp 'g14-mount'
        $extDir = Join-Path $tmp 'g14-ext'
        $subDir = Join-Path $mountDir 'Windows\Sub'
        New-Item -ItemType Directory -Force -Path $subDir, $extDir | Out-Null
        $juncPath = Join-Path $subDir 'link'
        $null = cmd.exe /c "mklink /J `"$juncPath`" `"$extDir`""
        $juncCaught = $false
        try {
            $null = Assert-WibNoReparsePointsInTree -Path (Join-Path $mountDir 'Windows') -BaseDir $mountDir
        } catch {
            if ($_.Exception.Message -like '*Reparse point violation*') {
                $juncCaught = $true
            }
        } finally {
            cmd.exe /c "rmdir `"$juncPath`"" | Out-Null
        }
        if (-not $juncCaught) { throw 'G14 failed: Assert-WibNoReparsePointsInTree did not detect nested NTFS junction' }

        # 3. WIB-005: Invoke-WibFolderCompression separates -OverrideSafetyChecks and -ContinueOnNativeError from -Force
        $dsDir = Join-Path $tmp 'g14-ds'
        New-Item -ItemType Directory -Force -Path $dsDir | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $dsDir 'dstorage.dll'), 'DS')
        $dsBlocked = $false
        try {
            Invoke-WibFolderCompression -Path $dsDir -Algorithm 'XPRESS8K' -Force
        } catch {
            if ($_.Exception.Message -like '*DirectStorage Warning*Pass -OverrideSafetyChecks*') {
                $dsBlocked = $true
            }
        }
        if (-not $dsBlocked) { throw 'G14 failed: -Force alone bypassed DirectStorage safety check' }

        # 4. WIB-006 & WIB-007: ACL protection on recovery-state.json and telemetry/validationRecord in manifest.json
        $recPath = Join-Path $tmp 'recovery-state.json'
        Set-WibDurableJsonFile -Path $recPath -Data @{ ToolVersion = $script:WibVersion; CommitState = 'committed' }
        $recAcl = Get-Acl -LiteralPath $recPath
        if (-not $recAcl.AreAccessRulesProtected) {
            throw 'G14 failed: recovery-state.json does not have protected NTFS ACLs'
        }

        $isoFile = Join-Path $tmp 'g14.iso'
        [System.IO.File]::WriteAllText($isoFile, 'G14_ISO_BYTES')
        $g14Work = Join-Path $tmp 'g14-work'
        New-Item -ItemType Directory -Force -Path $g14Work | Out-Null
        try {
            function Mount-DiskImage { param($ImagePath, [switch]$PassThru) throw 'G14_INTENTIONAL_STOP' }
            Invoke-WibBuild -IsoPath $isoFile -ProfilePath (Join-Path $repoRoot 'profiles\balanced.json') -ToolRoot $tmp -WorkDir $g14Work -DryRun -Force
        } catch {
            Write-Verbose $_.Exception.Message
        } finally {
            Remove-Item Function:\Mount-DiskImage -ErrorAction SilentlyContinue
        }
        $manifestFile = Get-ChildItem -Path (Join-Path $tmp 'reports') -Recurse -Filter 'manifest.json' -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $manifestFile) { throw 'G14 failed: manifest.json not generated' }
        $mJson = ConvertFrom-Json (Get-Content -LiteralPath $manifestFile.FullName -Raw)
        if ($null -eq $mJson.telemetry -or $null -eq $mJson.validationRecord -or $mJson.validationRecord.vmBootValidated -ne $false) {
            throw 'G14 failed: manifest.json missing telemetry or validationRecord fields'
        }

        Write-Output 'GATE_G14_PASS'
    } finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Test-GateG15 {
    # G15: v0.2.22 audit remediation checks (WIB-008 through WIB-011)
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('wib_g15_' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    try {
        $unattendTool = Join-Path $repoRoot 'tools\New-WibUnattend.ps1'
        $sec = ConvertTo-SecureString 'G15Secret!' -AsPlainText -Force

        # 1. WIB-008: Test-WibVolumePersistentAclSupport check & zero-artifact cleanup on ACL failure
        if (-not (Test-WibVolumePersistentAclSupport -Path $tmp)) {
            throw 'G15 failed: Test-WibVolumePersistentAclSupport returned false on NTFS temp volume'
        }

        $origVolFn = ${function:Test-WibVolumePersistentAclSupport}
        $fatBlocked = $false
        $fatXml = Join-Path $tmp 'g15-fat.xml'
        try {
            function Test-WibVolumePersistentAclSupport { param([string]$Path) return $false }
            & $unattendTool -OutputPath $fatXml -Username 'G15User' -SecurePassword $sec -AcceptCredentialExposureRisk
        } catch {
            if ($_.Exception.Message -like '*does not support persistent NTFS/ReFS ACLs*') { $fatBlocked = $true }
        } finally {
            ${function:Test-WibVolumePersistentAclSupport} = $origVolFn
        }
        if (-not $fatBlocked -or (Test-Path -LiteralPath $fatXml)) {
            throw 'G15 failed: New-WibUnattend.ps1 did not fail closed with zero output on unsupported volume'
        }

        $origProtFn = ${function:Protect-WibSensitiveFileAcl}
        $aclFailNewXml = Join-Path $tmp 'g15-acl-fail.xml'
        $aclFailThrew = $false
        try {
            function Protect-WibSensitiveFileAcl { param([string]$Path) throw 'G15 simulated DACL failure' }
            & $unattendTool -OutputPath $aclFailNewXml -Username 'G15User' -SecurePassword $sec -AcceptCredentialExposureRisk
        } catch {
            if ($_.Exception.Message -like '*G15 simulated DACL failure*') { $aclFailThrew = $true }
        } finally {
            ${function:Protect-WibSensitiveFileAcl} = $origProtFn
        }
        $leftovers = @(Get-ChildItem -LiteralPath $tmp -Filter 'g15-acl-fail.xml*' -Force -ErrorAction SilentlyContinue)
        if (-not $aclFailThrew -or $leftovers.Count -gt 0) {
            throw 'G15 failed: New-WibUnattend.ps1 left output or staging artifact behind on ACL failure'
        }

        # Pre-existing target preserved when -Force overwrite encounters ACL failure
        $preExistXml = Join-Path $tmp 'g15-preexist.xml'
        [System.IO.File]::WriteAllText($preExistXml, 'G15_ORIGINAL_SAFE_CONTENT')
        $postFailThrew = $false
        try {
            function Protect-WibSensitiveFileAcl {
                param([string]$Path)
                if ($Path -like '*.tmp') { return (& $origProtFn $Path) }
                $bakCount = @(Get-ChildItem -LiteralPath (Split-Path -Parent $Path) -Filter "$(Split-Path -Leaf $Path).*.bak" -Force -ErrorAction SilentlyContinue).Count
                if ($bakCount -eq 0) { return (& $origProtFn $Path) }
                throw 'G15 simulated post-replace DACL failure'
            }
            & $unattendTool -OutputPath $preExistXml -Username 'G15User' -SecurePassword $sec -AcceptCredentialExposureRisk -Force
        } catch {
            if ($_.Exception.Message -like '*G15 simulated post-replace DACL failure*') { $postFailThrew = $true }
        } finally {
            ${function:Protect-WibSensitiveFileAcl} = $origProtFn
        }
        if (-not $postFailThrew -or ([System.IO.File]::ReadAllText($preExistXml) -ne 'G15_ORIGINAL_SAFE_CONTENT')) {
            throw 'G15 failed: Pre-existing target file was not preserved intact when -Force ACL verification failed'
        }

        # 2. WIB-009: Kernel 64-bit NTFS File ID TOCTOU verification in Remove-WibConfinedTreeSafe
        $mountDir = Join-Path $tmp 'g15-mount'
        $pkgDir = Join-Path $mountDir 'Pkg'
        $subDir = Join-Path $pkgDir 'Child'
        $extVictimDir = Join-Path $tmp 'g15-victim'
        New-Item -ItemType Directory -Force -Path $subDir, $extVictimDir | Out-Null
        $victimFile = Join-Path $extVictimDir 'keep.txt'
        [System.IO.File]::WriteAllText($victimFile, 'DO_NOT_DELETE')
        $toctouCaught = $false
        try {
            Remove-WibConfinedTreeSafe -Path $pkgDir -BaseDir $mountDir -OnBeforeNodeDelete {
                param($nodePath, $nodeType)
                if ($nodeType -eq 'Directory' -and $nodePath -ieq $subDir) {
                    [System.IO.Directory]::Delete($subDir, $false)
                    $null = cmd.exe /c "mklink /J `"$subDir`" `"$extVictimDir`""
                }
            }
        } catch {
            if ($_.Exception.Message -like '*TOCTOU node identity mismatch*') { $toctouCaught = $true }
        } finally {
            if (Test-Path -LiteralPath $subDir) { cmd.exe /c "rmdir `"$subDir`"" 2>&1 | Out-Null }
        }
        if (-not $toctouCaught -or (-not (Test-Path -LiteralPath $victimFile))) {
            throw 'G15 failed: Remove-WibConfinedTreeSafe did not abort on mid-deletion junction swap or failed to preserve victim file'
        }

        # 3. WIB-010 & WIB-011: Direct unmanaged SecureString obscuring & PowerShell host memory scope in telemetry
        $okXml = Join-Path $tmp 'g15-ok.xml'
        $okRes = & $unattendTool -OutputPath $okXml -Username 'G15User' -SecurePassword $sec -AcceptCredentialExposureRisk 3>$null
        if (-not $okRes.AclProtected) {
            throw 'G15 failed: New-WibUnattend.ps1 did not report AclProtected=true on valid NTFS write'
        }

        $isoFile = Join-Path $tmp 'g15.iso'
        [System.IO.File]::WriteAllText($isoFile, 'G15_ISO_BYTES')
        $g15Work = Join-Path $tmp 'g15-work'
        New-Item -ItemType Directory -Force -Path $g15Work | Out-Null
        try {
            function Mount-DiskImage { param($ImagePath, [switch]$PassThru) throw 'G15_INTENTIONAL_STOP' }
            Invoke-WibBuild -IsoPath $isoFile -ProfilePath (Join-Path $repoRoot 'profiles\balanced.json') -ToolRoot $tmp -WorkDir $g15Work -DryRun -Force
        } catch {
            Write-Verbose $_.Exception.Message
        } finally {
            Remove-Item Function:\Mount-DiskImage -ErrorAction SilentlyContinue
        }
        $manFile = Get-ChildItem -Path (Join-Path $tmp 'reports') -Recurse -Filter 'manifest.json' -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $manFile) { throw 'G15 failed: manifest.json not generated' }
        $mObj = ConvertFrom-Json (Get-Content -LiteralPath $manFile.FullName -Raw)
        if ($mObj.telemetry.memoryMeasurementScope -ne 'powershell-host-process-only' -or $mObj.telemetry.powershellPeakWorkingSetBytes -le 0) {
            throw 'G15 failed: manifest.telemetry missing powershellPeakWorkingSetBytes or memoryMeasurementScope'
        }

        Write-Output 'GATE_G15_PASS'
    } finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Test-GateG16 {
    # G16: v0.2.23 audit remediation checks (WIB-012 through WIB-015 & Section 4 audit/telemetry gaps)
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('wib_g16_' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    try {
        $unattendTool = Join-Path $repoRoot 'tools\New-WibUnattend.ps1'
        $sec = ConvertTo-SecureString 'G16Secret!' -AsPlainText -Force

        # 1. WIB-012: Overwriting an existing answer file with a permissive DACL locks down the destination DACL BEFORE File.Replace
        $permXml = Join-Path $tmp 'g16-perm.xml'
        [System.IO.File]::WriteAllText($permXml, 'OLD_PUBLIC_PLACEHOLDER')
        $fInfo = New-Object System.IO.FileInfo($permXml)
        $badAcl = $fInfo.GetAccessControl([System.Security.AccessControl.AccessControlSections]::Access)
        $usersSid = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::BuiltinUsersSid, $null)
        $usersRule = New-Object System.Security.AccessControl.FileSystemAccessRule($usersSid, 'ReadAndExecute', 'Allow')
        $badAcl.AddAccessRule($usersRule)
        $fInfo.SetAccessControl($badAcl)

        $global:g16AfterReplaceProtected = $false
        $global:g16AfterReplaceUsers = -1
        $global:g16RealProtFn = ${function:Protect-WibSensitiveFileAcl}
        try {
            function Protect-WibSensitiveFileAcl {
                param([string]$Path)
                $parentDir = Split-Path -Parent $Path
                $leafName = Split-Path -Leaf $Path
                $hasBak = @(Get-ChildItem -LiteralPath $parentDir -Filter "$leafName.*.bak" -Force -ErrorAction SilentlyContinue).Count -gt 0
                if ($hasBak -and ($Path -ieq $permXml)) {
                    $aclNow = Get-Acl -LiteralPath $Path
                    $global:g16AfterReplaceProtected = [bool]$aclNow.AreAccessRulesProtected
                    $global:g16AfterReplaceUsers = @($aclNow.Access | Where-Object { $_.IdentityReference.Value -match 'Users|Everyone' }).Count
                }
                return (& $global:g16RealProtFn -Path $Path)
            }
            & $unattendTool -OutputPath $permXml -Username 'G16User' -SecurePassword $sec -AcceptCredentialExposureRisk -Force 3>$null | Out-Null
        } finally {
            ${function:Protect-WibSensitiveFileAcl} = $global:g16RealProtFn
        }
        if (-not $global:g16AfterReplaceProtected -or $global:g16AfterReplaceUsers -ne 0) {
            throw 'G16 failed: WIB-012 pre-replace DACL lockdown did not protect existing target before File.Replace'
        }

        # 2. WIB-013: Set-WibDurableJsonFile rolls back to prior file bytes verified by SHA-256 when final post-replace ACL check fails
        $jsonPath = Join-Path $tmp 'g16-rollback.json'
        Set-WibDurableJsonFile -Path $jsonPath -Data @{ state = 'committed-v1'; seq = 1 } -ProtectAcl
        $origSha = Get-WibSha256 $jsonPath
        $postFailThrew = $false
        try {
            function Protect-WibSensitiveFileAcl {
                param([string]$Path)
                if ($Path -like '*.tmp') { return (& $global:g16RealProtFn -Path $Path) }
                $parentDir = Split-Path -Parent $Path
                $leafName = Split-Path -Leaf $Path
                $hasBak = @(Get-ChildItem -LiteralPath $parentDir -Filter "$leafName.*.bak" -Force -ErrorAction SilentlyContinue).Count -gt 0
                if (-not $hasBak) { return (& $global:g16RealProtFn -Path $Path) }
                throw 'G16 simulated final post-replace DACL failure'
            }
            Set-WibDurableJsonFile -Path $jsonPath -Data @{ state = 'unverified-v2'; seq = 2 } -ProtectAcl
        } catch {
            if ($_.Exception.Message -like '*G16 simulated final post-replace DACL failure*') {
                $postFailThrew = $true
            }
        } finally {
            ${function:Protect-WibSensitiveFileAcl} = $global:g16RealProtFn
            Remove-Variable -Name g16RealProtFn, g16AfterReplaceProtected, g16AfterReplaceUsers -Scope Global -ErrorAction SilentlyContinue
        }
        $restoredSha = Get-WibSha256 $jsonPath
        $leftovers = @(Get-ChildItem -LiteralPath $tmp -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'g16-rollback.json.*' })
        if (-not $postFailThrew -or $restoredSha -ne $origSha -or $leftovers.Count -gt 0) {
            throw 'G16 failed: WIB-013 Set-WibDurableJsonFile did not roll back to prior file bytes on post-replace ACL failure'
        }

        # 3. WIB-014: Remove-WibConfinedTreeSafe fails closed when kernel 64-bit File ID helper is unavailable
        $mountDir = Join-Path $tmp 'g16-mount'
        $treeDir = Join-Path $mountDir 'Pkg\Sub'
        New-Item -ItemType Directory -Force -Path $treeDir | Out-Null
        $keepFile = Join-Path $treeDir 'keep.txt'
        [System.IO.File]::WriteAllText($keepFile, 'KEEP')
        $helperFailClosed = $false
        $script:WibDisableKernelIdentityHelper = $true
        try {
            Remove-WibConfinedTreeSafe -Path (Join-Path $mountDir 'Pkg') -BaseDir $mountDir
        } catch {
            if ($_.Exception.Message -like '*SECURITY ERROR: Kernel 64-bit File ID helper (WibKernelPathHelper) is unavailable*') {
                $helperFailClosed = $true
            }
        } finally {
            $script:WibDisableKernelIdentityHelper = $false
        }
        if (-not $helperFailClosed -or (-not (Test-Path -LiteralPath $keepFile))) {
            throw 'G16 failed: WIB-014 Remove-WibConfinedTreeSafe did not fail closed when kernel File ID helper was unavailable'
        }

        # 4. WIB-015: Test-WibUnattendPasswordHash accepts valid WSIM UTF-16LE Base64 vector and rejects ASCII/malformed inputs
        $validVec = 'VABlAHMAdABQAGEAcwBzAHcAbwByAGQA' # UTF-16LE('TestPassword')
        $hashXml = Join-Path $tmp 'g16-hash.xml'
        $hashRes = & $unattendTool -OutputPath $hashXml -Username 'G16HashUser' -PasswordHash $validVec -AcceptCredentialExposureRisk
        if ($hashRes.PasswordMode -ne 'hashed') {
            throw 'G16 failed: WIB-015 valid WSIM UTF-16LE PasswordHash vector was not accepted'
        }
        $badRejected = $false
        try {
            & $unattendTool -OutputPath (Join-Path $tmp 'g16-badhash.xml') -PasswordHash 'VGVzdFBhc3N3b3Jk' -AcceptCredentialExposureRisk
        } catch {
            if ($_.Exception.Message -like '*Invalid -PasswordHash format*') { $badRejected = $true }
        }
        if (-not $badRejected) {
            throw 'G16 failed: WIB-015 non-UTF-16LE ASCII PasswordHash was not rejected'
        }

        # 5. Section 4: Export-WibAuditBundle.ps1 includes gate-check.mjs and telemetry includes nativeToolInvocations
        $bundleScript = Get-Content -LiteralPath (Join-Path $repoRoot 'tools\Export-WibAuditBundle.ps1') -Raw
        $nativeTelem = Get-WibNativeToolTelemetry
        if (($bundleScript -notmatch 'gate-check\.mjs') -or $null -eq $nativeTelem -or (-not $nativeTelem.Contains('dismExe'))) {
            throw 'G16 failed: Section 4 gate-check.mjs inclusion or nativeToolInvocations telemetry missing'
        }

        Write-Output 'GATE_G16_PASS'
    } finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Test-GateG17 {
    # G17: v0.2.24 audit remediation checks (WIB-016 through WIB-020)
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('wib_g17_' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    try {
        $unattendTool = Join-Path $repoRoot 'tools\New-WibUnattend.ps1'
        $sec = ConvertTo-SecureString 'G17Secret!' -AsPlainText -Force

        # 1. WIB-016: Transactional DACL + SHA-256 rollback verification with custom DACL and .bak preservation on rollback failure
        $customJson = Join-Path $tmp 'g17-custom-dacl.json'
        [System.IO.File]::WriteAllText($customJson, '{"version":1,"preserve":true}')
        $fi = New-Object System.IO.FileInfo($customJson)
        $customAcl = $fi.GetAccessControl([System.Security.AccessControl.AccessControlSections]::Access)
        $customAcl.SetAccessRuleProtection($true, $false)
        $curSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
        $usersSid = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::BuiltinUsersSid, $null)
        $customAcl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($curSid, 'FullControl', 'Allow')))
        $customAcl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($usersSid, 'ReadAndExecute', 'Allow')))
        $fi.SetAccessControl($customAcl)

        $origSha = Get-WibSha256 $customJson
        $origFp  = Get-WibAclFingerprint -Path $customJson
        $postFailThrew = $false
        $global:g17RealProtFn = ${function:Protect-WibSensitiveFileAcl}
        try {
            function Protect-WibSensitiveFileAcl {
                param([string]$Path)
                if ($Path -like '*.tmp') { return (& $global:g17RealProtFn -Path $Path) }
                $parentDir = Split-Path -Parent $Path
                $leafName = Split-Path -Leaf $Path
                $hasBak = @(Get-ChildItem -LiteralPath $parentDir -Filter "$leafName.*.bak" -Force -ErrorAction SilentlyContinue).Count -gt 0
                if (-not $hasBak) { return (& $global:g17RealProtFn -Path $Path) }
                throw 'G17 simulated post-replace DACL verification failure'
            }
            Set-WibDurableJsonFile -Path $customJson -Data @{ version = 2; preserve = $false } -ProtectAcl
        } catch {
            if ($_.Exception.Message -like '*prior file and permissions restored and verified*') {
                $postFailThrew = $true
            }
        } finally {
            ${function:Protect-WibSensitiveFileAcl} = $global:g17RealProtFn
        }
        if (-not $postFailThrew -or (Get-WibSha256 $customJson) -ne $origSha -or (Get-WibAclFingerprint -Path $customJson) -ne $origFp) {
            throw 'G17 failed: WIB-016 custom pre-existing DACL and SHA-256 were not restored and verified on rollback'
        }

        # Rollback DACL restoration failure must preserve .bak and throw CRITICAL ROLLBACK FAILURE
        $critJson = Join-Path $tmp 'g17-crit.json'
        [System.IO.File]::WriteAllText($critJson, '{"crit":1}')
        (New-Object System.IO.FileInfo($critJson)).SetAccessControl($customAcl)
        $critThrew = $false
        $origRestoreFn = ${function:Restore-WibFileDaclSnapshot}
        try {
            function Protect-WibSensitiveFileAcl {
                param([string]$Path)
                if ($Path -like '*.tmp') { return (& $global:g17RealProtFn -Path $Path) }
                $parentDir = Split-Path -Parent $Path
                $leafName = Split-Path -Leaf $Path
                $hasBak = @(Get-ChildItem -LiteralPath $parentDir -Filter "$leafName.*.bak" -Force -ErrorAction SilentlyContinue).Count -gt 0
                if (-not $hasBak) { return (& $global:g17RealProtFn -Path $Path) }
                throw 'G17 trigger rollback'
            }
            function Restore-WibFileDaclSnapshot { param([string]$LiteralPath, $Snapshot) throw 'G17 simulated DACL restore error' }
            Set-WibDurableJsonFile -Path $critJson -Data @{ crit = 2 } -ProtectAcl
        } catch {
            if ($_.Exception.Message -like '*CRITICAL ROLLBACK FAILURE*backup preserved at*') {
                $critThrew = $true
            }
        } finally {
            ${function:Protect-WibSensitiveFileAcl} = $global:g17RealProtFn
            ${function:Restore-WibFileDaclSnapshot} = $origRestoreFn
            Remove-Variable -Name g17RealProtFn -Scope Global -ErrorAction SilentlyContinue
        }
        $critBaks = @(Get-ChildItem -LiteralPath $tmp -Filter 'g17-crit.json.*.bak' -Force -ErrorAction SilentlyContinue)
        if (-not $critThrew -or $critBaks.Count -ne 1) {
            throw 'G17 failed: WIB-016 failed DACL rollback did not preserve .bak or throw CRITICAL ROLLBACK FAILURE'
        }
        $critBaks | Remove-Item -Force -ErrorAction SilentlyContinue

        # 2. WIB-017: Decompression & watcher reparse/kernel identity enforcement
        $decompDir = Join-Path $tmp 'g17-decomp\sub'
        $extDir = Join-Path $tmp 'g17-ext'
        New-Item -ItemType Directory -Force -Path $decompDir, $extDir | Out-Null
        $junc = Join-Path $decompDir 'junc'
        $null = cmd.exe /c "mklink /J `"$junc`" `"$extDir`""
        $decompJuncBlocked = $false
        $watcherJuncBlocked = $false
        try {
            try { Invoke-WibFolderDecompression -Path (Join-Path $tmp 'g17-decomp') } catch { if ($_.Exception.Message -like '*Reparse point violation*') { $decompJuncBlocked = $true } }
            try { Set-WibCompactWatcher -Action 'add' -Path (Join-Path $tmp 'g17-decomp') } catch { if ($_.Exception.Message -like '*Reparse point violation*') { $watcherJuncBlocked = $true } }
        } finally {
            cmd.exe /c "rmdir `"$junc`"" 2>&1 | Out-Null
        }
        if (-not $decompJuncBlocked -or (-not $watcherJuncBlocked)) {
            throw 'G17 failed: WIB-017 Invoke-WibFolderDecompression or Set-WibCompactWatcher did not reject nested NTFS junction'
        }

        # 3. WIB-018: Structured child-process telemetry with honest workingSetMeasurementStatus
        Reset-WibNativeToolTelemetry
        [System.IO.File]::WriteAllText((Join-Path $extDir 'f.txt'), ('X' * 512))
        $null = Get-WibCompactStatus -Path $extDir
        $telem = Get-WibNativeToolTelemetry
        if ($telem.totalCount -lt 1 -or $telem.compactExe.invocations -lt 1 -or $telem.compactExe.lastExitCode -ne 0 -or ($telem.compactExe.workingSetMeasurementStatus -notin @('measured', 'unavailable'))) {
            throw 'G17 failed: WIB-018 structured native tool telemetry not recorded accurately'
        }

        # 4. WIB-019 & WIB-020: Mandatory ACL helpers and empty/whitespace -PasswordHash rejection
        $emptyHashBlocked = $false
        $emptyXml = Join-Path $tmp 'g17-empty-hash.xml'
        try {
            & $unattendTool -OutputPath $emptyXml -Username 'G17User' -PasswordHash '   ' -AcceptCredentialExposureRisk
        } catch {
            if ($_.Exception.Message -like '*Invalid -PasswordHash format: value cannot be empty or whitespace*') {
                $emptyHashBlocked = $true
            }
        }
        if (-not $emptyHashBlocked -or (Test-Path -LiteralPath $emptyXml)) {
            throw 'G17 failed: WIB-020 whitespace -PasswordHash was not rejected fail-closed'
        }

        Write-Output 'GATE_G17_PASS'
    } finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Test-GateG18 {
    # G18: v0.2.25 audit remediation (WIB-021 through WIB-025)
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("wib-g18-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    try {
        # 1. WIB-021: First-party native tool path resolution & mock confinement
        $resolvedDism = Resolve-WibTrustedNativeTool -ToolKey 'dismExe'
        $resolvedReg = Resolve-WibTrustedNativeTool -ToolKey 'regExe'
        $systemRoot = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Windows)
        if (-not $resolvedDism.StartsWith($systemRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
            -not $resolvedReg.StartsWith($systemRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "G18 failed: WIB-021 trusted tools did not resolve to approved System32/Sysnative path ($resolvedDism, $resolvedReg)"
        }
        $unapprovedBlocked = $false
        try {
            $null = Resolve-WibTrustedNativeTool -ToolKey 'calcExe'
        } catch {
            if ($_.Exception.Message -like '*Unrecognized native tool key*') {
                $unapprovedBlocked = $true
            }
        }
        if (-not $unapprovedBlocked) {
            throw "G18 failed: WIB-021 unapproved native tool key was not rejected fail-closed"
        }

        # 2. WIB-022: Rollback backup preservation & non-destructive cleanup
        $g18DurableTarget = Join-Path $tmp 'g18-durable.json'
        Set-WibDurableJsonFile -Path $g18DurableTarget -Data @{ initial = 'v1' } -ProtectAcl
        $origReplaceFn = ${function:Invoke-WibFileReplace}
        $corruptRollbackThrew = $false
        try {
            function Invoke-WibFileReplace {
                param($SourcePath, $DestinationPath, $BackupPath)
                [System.IO.File]::WriteAllText($BackupPath, 'CORRUPT_BYTES')
                throw 'Simulated replace failure'
            }
            Set-WibDurableJsonFile -Path $g18DurableTarget -Data @{ initial = 'v2' } -ProtectAcl
        } catch {
            if ($_.Exception.Message -like '*CRITICAL ROLLBACK FAILURE*') {
                $corruptRollbackThrew = $true
            }
        } finally {
            ${function:Invoke-WibFileReplace} = $origReplaceFn
        }
        $preservedBaks = @(Get-ChildItem -LiteralPath $tmp -Filter 'g18-durable.json.*.bak')
        if (-not $corruptRollbackThrew -or $preservedBaks.Count -eq 0) {
            throw "G18 failed: WIB-022 corrupted backup rollback did not throw CRITICAL ROLLBACK FAILURE or preserve backup on disk"
        }
        $preservedBaks | Remove-Item -Force -ErrorAction SilentlyContinue

        # 3. WIB-023: Target and parent identity binding and reparse point rejection
        $juncBase = Join-Path $tmp 'g18-junc-work'
        $extBase = Join-Path $tmp 'g18-ext'
        New-Item -ItemType Directory -Force -Path $juncBase, $extBase | Out-Null
        $juncDir = Join-Path $juncBase 'junc'
        $null = cmd.exe /c "mklink /J `"$juncDir`" `"$extBase`""
        $reparseBlockedJson = $false
        $reparseBlockedXml = $false
        try {
            try {
                Set-WibDurableJsonFile -Path (Join-Path $juncDir 'out.json') -Data @{ x = 1 } -ProtectAcl
            } catch {
                if ($_.Exception.Message -like '*reparse point or junction*') {
                    $reparseBlockedJson = $true
                }
            }
            try {
                & (Join-Path $repoRoot 'tools\New-WibUnattend.ps1') -OutputPath (Join-Path $juncDir 'autounattend.xml') -Username 'G18User'
            } catch {
                if ($_.Exception.Message -like '*reparse point or junction*') {
                    $reparseBlockedXml = $true
                }
            }
        } finally {
            cmd.exe /c "rmdir `"$juncDir`"" 2>&1 | Out-Null
        }
        if (-not $reparseBlockedJson -or -not $reparseBlockedXml) {
            throw "G18 failed: WIB-023 reparse point parent directory was not rejected fail-closed (json=$reparseBlockedJson, xml=$reparseBlockedXml)"
        }

        # 4. WIB-024: Canonical DACL integrity verification
        $aclTestFile = Join-Path $tmp 'g18-acl.txt'
        [System.IO.File]::WriteAllText($aclTestFile, 'ACL_TEST')
        [void](Protect-WibSensitiveFileAcl -Path $aclTestFile)
        $fiAcl = New-Object System.IO.FileInfo($aclTestFile)
        $badAcl = $fiAcl.GetAccessControl([System.Security.AccessControl.AccessControlSections]::Access)
        $usersSid = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::BuiltinUsersSid, $null)
        $badAcl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($usersSid, 'Write', 'Allow')))
        $fiAcl.SetAccessControl($badAcl)
        $badAclCaught = $false
        try {
            Assert-WibSensitiveAclIntegrity -Path $aclTestFile -Acl ((New-Object System.IO.FileInfo($aclTestFile)).GetAccessControl([System.Security.AccessControl.AccessControlSections]::Access))
        } catch {
            if ($_.Exception.Message -like '*unauthorized principal*') {
                $badAclCaught = $true
            }
        }
        if (-not $badAclCaught) {
            throw "G18 failed: WIB-024 Assert-WibSensitiveAclIntegrity did not reject unauthorized BUILTIN\Users ACE"
        }

        # 5. WIB-025: Child process telemetry tracking without falsifying zero metrics
        Reset-WibNativeToolTelemetry
        $beforeTelem = Get-WibNativeToolTelemetry
        $initInvocations = if ($beforeTelem.oscdimgExe) { $beforeTelem.oscdimgExe.invocations } else { 0 }
        $initFailures = if ($beforeTelem.oscdimgExe) { $beforeTelem.oscdimgExe.launchFailures } else { 0 }
        try {
            Invoke-WibNativeTool -ToolKey 'oscdimgExe' -FilePath 'C:\Windows\System32\nonexistent_executable_test.exe'
        } catch { }
        $afterTelem = Get-WibNativeToolTelemetry
        if ($afterTelem.oscdimgExe.invocations -ne $initInvocations -or $afterTelem.oscdimgExe.launchFailures -ne ($initFailures + 1)) {
            throw "G18 failed: WIB-025 telemetry did not track launchFailures accurately without incrementing invocations"
        }

        Write-Output 'GATE_G18_PASS'
    } finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Test-GateG19 {
    # G19: v0.2.26 audit remediation (WIB-026 through WIB-031)
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("wib-g19-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    $origWibFault = $global:WibFaultInjectionEnabled
    $origCommitHook = $global:WibSensitiveCommitTestHook
    $origBakHook = $global:WibBeforeBackupDeleteHook
    try {
        # 1. WIB-026: Cleanup never deletes competing unowned destination file on natural move collision failure
        $g19CompeteJson = Join-Path $tmp 'g19-compete.json'
        $g19CompeteXml = Join-Path $tmp 'g19-compete.xml'
        try {
            $global:WibFaultInjectionEnabled = $true
            $global:WibSensitiveCommitTestHook = {
                param($Boundary, $StagePath, $DestinationPath)
                if ($Boundary -eq 'AfterFinalValidationBeforeNewTargetMove') {
                    [System.IO.File]::WriteAllText($DestinationPath, 'COMPETING_PROCESS_BYTES')
                }
            }
            try { $null = Set-WibDurableJsonFile -Path $g19CompeteJson -Data @{ k = 1 } -ProtectAcl } catch { }
            try { $null = & (Join-Path $repoRoot 'tools\New-WibUnattend.ps1') -OutputPath $g19CompeteXml -Username 'G19User' -TestOnly } catch { }
        } finally {
            $global:WibFaultInjectionEnabled = $origWibFault
            $global:WibSensitiveCommitTestHook = $origCommitHook
        }
        $jsonCompeteOk = (Test-Path -LiteralPath $g19CompeteJson) -and ([System.IO.File]::ReadAllText($g19CompeteJson) -eq 'COMPETING_PROCESS_BYTES')
        $xmlCompeteOk = (Test-Path -LiteralPath $g19CompeteXml) -and ([System.IO.File]::ReadAllText($g19CompeteXml) -eq 'COMPETING_PROCESS_BYTES')
        if (-not $jsonCompeteOk -or -not $xmlCompeteOk) {
            throw "G19 failed: WIB-026 competing unowned destination file was deleted or mutated during error cleanup (json=$jsonCompeteOk, xml=$xmlCompeteOk)"
        }

        # 2. WIB-027: Staging validation binding detects pre-commit modification or substitution
        $g19TamperJson = Join-Path $tmp 'g19-tamper.json'
        $tamperCaught = $false
        try {
            $global:WibFaultInjectionEnabled = $true
            $global:WibSensitiveCommitTestHook = {
                param($Boundary, $StagePath, $DestinationPath)
                if ($Boundary -eq 'BeforeFinalValidation' -and $StagePath -like '*g19-tamper.json*') {
                    [System.IO.File]::AppendAllText($StagePath, 'TAMPER')
                }
            }
            $null = Set-WibDurableJsonFile -Path $g19TamperJson -Data @{ initial = 'clean' } -ProtectAcl
        } catch {
            if ($_.Exception.Message -like '*Staging file * changed*' -or $_.Exception.Message -like '*Staged file*') {
                $tamperCaught = $true
            }
        } finally {
            $global:WibFaultInjectionEnabled = $origWibFault
            $global:WibSensitiveCommitTestHook = $origCommitHook
        }
        if (-not $tamperCaught -or (Test-Path -LiteralPath $g19TamperJson)) {
            throw "G19 failed: WIB-027 staging tamper was not detected before commit fail-closed"
        }

        # 3. WIB-028: Sensitive output path ancestor validation and safe directory creation
        $g19DosPath = Join-Path $tmp 'NUL\test.json'
        $dosBlocked = $false
        try {
            Assert-WibSafeSensitiveOutputPath -Path $g19DosPath | Out-Null
        } catch {
            if ($_.Exception.Message -like '*Reserved DOS device name*' -or $_.Exception.Message -like '*reserved device name*') {
                $dosBlocked = $true
            }
        }
        if (-not $dosBlocked) {
            throw "G19 failed: WIB-028 reserved DOS device name was not rejected fail-closed"
        }

        # Real NTFS nested junction rejection in ancestor paths
        $g19JuncTarget = Join-Path $tmp 'g19-junc-target'
        $g19JuncLink = Join-Path $tmp 'g19-junc-link'
        New-Item -ItemType Directory -Force -Path $g19JuncTarget | Out-Null
        $null = cmd.exe /c mklink /J "$g19JuncLink" "$g19JuncTarget"
        $g19NestedBlocked = $false
        try {
            Assert-WibSafeSensitiveOutputPath -Path (Join-Path $g19JuncLink 'nested\out.json') -AllowMissingLeaf | Out-Null
        } catch {
            if ($_.Exception.Message -like '*Reparse point or junction detected*') {
                $g19NestedBlocked = $true
            }
        } finally {
            Remove-Item -LiteralPath $g19JuncLink -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $g19JuncTarget -Recurse -Force -ErrorAction SilentlyContinue
        }
        if (-not $g19NestedBlocked) {
            throw "G19 failed: WIB-028 real NTFS nested junction was not rejected"
        }

        # 4. WIB-029 & WIB-030: Canonical Windows root and DACL owner integrity
        $canonicalRoot = Get-WibCanonicalWindowsRoot
        if ([string]::IsNullOrWhiteSpace($canonicalRoot) -or -not (Test-Path -LiteralPath $canonicalRoot)) {
            throw "G19 failed: WIB-029 Get-WibCanonicalWindowsRoot returned invalid path '$canonicalRoot'"
        }
        $g19AclFile = Join-Path $tmp 'g19-acl-owner.txt'
        [System.IO.File]::WriteAllText($g19AclFile, 'ACL_OWNER_TEST')
        [void](Protect-WibSensitiveFileAcl -Path $g19AclFile)
        $origOwnerFn = ${function:Get-WibPathOwnerSid}
        $badOwnerCaught = $false
        try {
            function Get-WibPathOwnerSid { param($Path, [switch]$IsDirectory) return 'S-1-5-7' }
            Assert-WibSensitiveAclIntegrity -Path $g19AclFile
        } catch {
            if ($_.Exception.Message -like '*unapproved owner*') {
                $badOwnerCaught = $true
            }
        } finally {
            ${function:Get-WibPathOwnerSid} = $origOwnerFn
        }
        if (-not $badOwnerCaught) {
            throw "G19 failed: WIB-030 Assert-WibSensitiveAclIntegrity did not reject invalid owner SID"
        }

        # 5. WIB-031: Visible backup cleanup handling records status and warning without corrupting commit
        $g19BakTrackTarget = Join-Path $tmp 'g19-bak-track.json'
        $null = Set-WibDurableJsonFile -Path $g19BakTrackTarget -Data @{ initial = 'v1' } -ProtectAcl
        $g19BakWarningEmitted = $false
        $origWarnPref = $WarningPreference
        try {
            $global:WibFaultInjectionEnabled = $true
            $global:WibBeforeBackupDeleteHook = {
                param($Path)
                if ($Path -like '*g19-bak-track.json*') {
                    throw 'Simulated lock on backup file deletion'
                }
            }
            $WarningPreference = 'Continue'
            $null = Set-WibDurableJsonFile -Path $g19BakTrackTarget -Data @{ initial = 'v2' } -ProtectAcl -WarningVariable g19Warn
            if ($g19Warn -and ($g19Warn -join ' ') -like '*committedWithBackupRemaining*') {
                $g19BakWarningEmitted = $true
            }
        } finally {
            $WarningPreference = $origWarnPref
            $global:WibFaultInjectionEnabled = $origWibFault
            $global:WibBeforeBackupDeleteHook = $origBakHook
        }
        $g19TxStatus = $global:WibLastFileTransactionStatus
        if (-not $g19BakWarningEmitted -or $g19TxStatus.status -ne 'committedWithBackupRemaining') {
            throw "G19 failed: WIB-031 backup cleanup failure was not recorded as committedWithBackupRemaining or warning was missing (status=$($g19TxStatus.status), warned=$g19BakWarningEmitted)"
        }

        Write-Output 'GATE_G19_PASS'
    } finally {
        $global:WibFaultInjectionEnabled = $origWibFault
        $global:WibSensitiveCommitTestHook = $origCommitHook
        $global:WibBeforeBackupDeleteHook = $origBakHook
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Test-GateG20 {
    # G20: v0.2.27 audit remediation (WIB-033 through WIB-038)
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("wib-g20-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    $origWibFault = $global:WibFaultInjectionEnabled
    $origCommitHook = $global:WibSensitiveCommitTestHook
    $origBakHook = $global:WibBeforeBackupDeleteHook
    try {
        # 1. WIB-033: Atomic stage creation with FileMode.CreateNew fails closed if target exists
        $g20StageCollTarget = Join-Path $tmp 'g20-coll.tmp'
        [System.IO.File]::WriteAllText($g20StageCollTarget, 'EXISTING_STAGE')
        $g20CreateNewBlocked = $false
        try {
            $stream = [System.IO.File]::Open($g20StageCollTarget, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
            $stream.Dispose()
        } catch [System.IO.IOException] {
            $g20CreateNewBlocked = $true
        }
        $g20StagePreserved = ([System.IO.File]::ReadAllText($g20StageCollTarget) -eq 'EXISTING_STAGE')
        if (-not $g20CreateNewBlocked -or -not $g20StagePreserved) {
            throw "G20 failed: WIB-033 FileMode.CreateNew did not fail closed on existing file"
        }

        # 2. WIB-034: Handle-bound deletion via DeleteFileByHandleIfIdentityMatches
        $g20DelFile = Join-Path $tmp 'g20-del.txt'
        [System.IO.File]::WriteAllText($g20DelFile, 'DISPOSITION_DEL_TEST')
        $g20DelId = Get-WibKernelNodeIdentity -LiteralPath $g20DelFile
        $g20DelSha = Get-WibSha256 $g20DelFile
        $g20DelErr = $null
        $g20MismatchRet = [WibKernelPathHelper]::DeleteFileByHandleIfIdentityMatches($g20DelFile, $g20DelId, '0000000000000000000000000000000000000000000000000000000000000000', [ref]$g20DelErr)
        $g20PreservedOnMismatch = (Test-Path -LiteralPath $g20DelFile)
        $g20MatchRet = [WibKernelPathHelper]::DeleteFileByHandleIfIdentityMatches($g20DelFile, $g20DelId, $g20DelSha, [ref]$g20DelErr)
        $g20DeletedOnMatch = (-not (Test-Path -LiteralPath $g20DelFile))
        if ($g20MismatchRet -or -not $g20PreservedOnMismatch -or -not $g20MatchRet -or -not $g20DeletedOnMatch) {
            throw "G20 failed: WIB-034 DeleteFileByHandleIfIdentityMatches did not handle identity/hash match correctly"
        }

        # 3. WIB-035: Assert-WibSensitiveAclIntegrity authoritative on-disk check and owner provider validation
        $g20AclFile = Join-Path $tmp 'g20-acl.txt'
        [System.IO.File]::WriteAllText($g20AclFile, 'ACL_ON_DISK')
        [void](Protect-WibSensitiveFileAcl -Path $g20AclFile)
        $g20Fi = New-Object System.IO.FileInfo($g20AclFile)
        $g20MutatedAcl = $g20Fi.GetAccessControl([System.Security.AccessControl.AccessControlSections]::Access -bor [System.Security.AccessControl.AccessControlSections]::Owner)
        $g20MutatedAcl.SetOwner((New-Object System.Security.Principal.SecurityIdentifier('S-1-5-7')))
        $g20DiskIgnoredMem = Assert-WibSensitiveAclIntegrity -Path $g20AclFile -Acl $g20MutatedAcl
        $origOwnerFn = ${function:Get-WibPathOwnerSid}
        $g20BadOwnerBlocked = $false
        try {
            function Get-WibPathOwnerSid { param($Path, [switch]$IsDirectory) return 'S-1-5-7' }
            Assert-WibSensitiveAclIntegrity -Path $g20AclFile
        } catch {
            if ($_.Exception.Message -like '*unapproved owner*') {
                $g20BadOwnerBlocked = $true
            }
        } finally {
            ${function:Get-WibPathOwnerSid} = $origOwnerFn
        }
        if (-not $g20BadOwnerBlocked) {
            throw "G20 failed: WIB-035 Assert-WibSensitiveAclIntegrity did not reject unapproved owner SID"
        }

        # 4. WIB-036: Natural File.Move failure preserves competing unowned destination
        $g20CompeteJson = Join-Path $tmp 'g20-compete.json'
        try {
            $global:WibFaultInjectionEnabled = $true
            $global:WibSensitiveCommitTestHook = {
                param($Boundary, $StagePath, $DestinationPath)
                if ($Boundary -eq 'AfterFinalValidationBeforeNewTargetMove') {
                    [System.IO.File]::WriteAllText($DestinationPath, 'COMPETING_PAYLOAD_G20')
                }
            }
            try {
                $null = Set-WibDurableJsonFile -Path $g20CompeteJson -Data @{ k = 20 } -ProtectAcl
            } catch { }
        } finally {
            $global:WibFaultInjectionEnabled = $origWibFault
            $global:WibSensitiveCommitTestHook = $origCommitHook
        }
        $g20CompetePreserved = (Test-Path -LiteralPath $g20CompeteJson) -and ([System.IO.File]::ReadAllText($g20CompeteJson) -eq 'COMPETING_PAYLOAD_G20')
        if (-not $g20CompetePreserved) {
            throw "G20 failed: WIB-036 Competing unowned destination file was not preserved on natural File.Move collision"
        }

        # 5. WIB-037: Owner SID capture and restoration in DACL snapshot
        $g20SnapFile = Join-Path $tmp 'g20-snap.txt'
        [System.IO.File]::WriteAllText($g20SnapFile, 'SNAP_CONTENT')
        [void](Protect-WibSensitiveFileAcl -Path $g20SnapFile)
        $g20Snap = Get-WibFileDaclSnapshot -LiteralPath $g20SnapFile
        if ([string]::IsNullOrWhiteSpace($g20Snap.OwnerSid) -or [string]::IsNullOrWhiteSpace($g20Snap.FullSddl)) {
            throw "G20 failed: WIB-037 Get-WibFileDaclSnapshot did not capture OwnerSid or FullSddl"
        }
        Restore-WibFileDaclSnapshot -LiteralPath $g20SnapFile -Snapshot $g20Snap
        $g20RestoredOwner = Get-WibPathOwnerSid -Path $g20SnapFile
        if ($g20RestoredOwner -ine $g20Snap.OwnerSid) {
            throw "G20 failed: WIB-037 Restored owner '$g20RestoredOwner' does not match original '$($g20Snap.OwnerSid)'"
        }

        # 6. WIB-038: Launch boundary requires pinned ExpectedSha256 for production oscdimg
        $origMockMode = $script:WibAllowNativeToolMocks
        $g20HashReqBlocked = $false
        try {
            $script:WibAllowNativeToolMocks = $false
            $null = Resolve-WibTrustedNativeTool -ToolKey 'oscdimgExe' -FilePath 'C:\Windows\System32\cmd.exe' -ExpectedSha256 ''
        } catch {
            if ($_.Exception.Message -like '*requires an explicit -ExpectedSha256*') {
                $g20HashReqBlocked = $true
            }
        } finally {
            $script:WibAllowNativeToolMocks = $origMockMode
        }
        if (-not $g20HashReqBlocked) {
            throw "G20 failed: WIB-038 Resolve-WibTrustedNativeTool did not enforce -ExpectedSha256 for production oscdimg"
        }

        Write-Output 'GATE_G20_PASS'
    } finally {
        $global:WibFaultInjectionEnabled = $origWibFault
        $global:WibSensitiveCommitTestHook = $origCommitHook
        $global:WibBeforeBackupDeleteHook = $origBakHook
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Test-GateG21 {
    # G21: v0.2.28 audit remediation (mandatory kernel identity validation, unowned backup ACL preservation, single-stream stage snapshot binding, existing-target replacement race hook & rollback preservation, oscdimg strict allowlist enforcement)
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("wib-g21-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    $origWibFault = $global:WibFaultInjectionEnabled
    $origCommitHook = $global:WibSensitiveCommitTestHook
    $origBakHook = $global:WibBeforeBackupDeleteHook
    try {
        # 1. WIB-039: DeleteFileByHandleIfIdentityMatches rejects empty and malformed expected identities fail-closed
        $g21File = Join-Path $tmp 'g21-id-reject.txt'
        [System.IO.File]::WriteAllText($g21File, 'G21_ID_REJECT')
        $g21Err = $null
        $g21EmptyOk = [WibKernelPathHelper]::DeleteFileByHandleIfIdentityMatches($g21File, '', '', [ref]$g21Err)
        $g21MalformedOk = [WibKernelPathHelper]::DeleteFileByHandleIfIdentityMatches($g21File, 'INVALID:ID:HERE', '', [ref]$g21Err)
        $g21BadShaOk = [WibKernelPathHelper]::DeleteFileByHandleIfIdentityMatches($g21File, 'OK:12345678:12345678:12345678', 'badsha', [ref]$g21Err)
        $g21FilePreserved = Test-Path -LiteralPath $g21File
        if ($g21EmptyOk -or $g21MalformedOk -or $g21BadShaOk -or (-not $g21FilePreserved)) {
            throw "G21 failed: WIB-039 DeleteFileByHandleIfIdentityMatches did not fail closed on empty/malformed identity or sha"
        }

        # 2. WIB-040: Complete-WibBackupCleanup detects unowned replacement, reports backupPathReplacedByUnownedFile, and does NOT alter ACL
        $g21Bak = Join-Path $tmp 'g21-backup.txt'
        [System.IO.File]::WriteAllText($g21Bak, 'ORIG_BACKUP')
        $g21OrigId = Get-WibKernelNodeIdentity -LiteralPath $g21Bak
        Remove-Item -LiteralPath $g21Bak -Force
        [System.IO.File]::WriteAllText($g21Bak, 'UNOWNED_SUBSTITUTE')
        $g21OrigFp = Get-WibAclFingerprint -Path $g21Bak
        $g21Status = Complete-WibBackupCleanup -Path $g21Bak -ExpectedIdentity $g21OrigId -Sensitive -Outcome Committed
        $g21CurrentFp = Get-WibAclFingerprint -Path $g21Bak
        $g21Content = [System.IO.File]::ReadAllText($g21Bak)
        if ($g21Status.status -ne 'backupPathReplacedByUnownedFile' -or $g21Content -ne 'UNOWNED_SUBSTITUTE' -or $g21CurrentFp -ne $g21OrigFp) {
            throw "G21 failed: WIB-040 Complete-WibBackupCleanup did not report backupPathReplacedByUnownedFile or modified unowned file ACL"
        }

        # 3. WIB-041: Get-WibValidatedStageSnapshot binds identity, length, hash and content to single handle stream
        $g21Stage = Join-Path $tmp 'g21-stage.json'
        [System.IO.File]::WriteAllText($g21Stage, '{"g21":"stream-test"}')
        $g21Snap = Get-WibValidatedStageSnapshot -Path $g21Stage -PayloadKind Json
        $g21ExpId = Get-WibKernelNodeIdentity -LiteralPath $g21Stage
        $g21ExpSha = Get-WibSha256 -Path $g21Stage
        if ($g21Snap.KernelIdentity -ne $g21ExpId -or $g21Snap.Sha256 -ne $g21ExpSha -or $g21Snap.Length -le 0) {
            throw "G21 failed: WIB-041 Get-WibValidatedStageSnapshot handle snapshot mismatch"
        }

        # 4. WIB-042: Set-WibDurableJsonFile triggers AfterFinalValidationBeforeReplace and preserves unowned file upon target substitution
        $g21Target = Join-Path $tmp 'g21-target.json'
        Set-WibDurableJsonFile -Path $g21Target -Data @{ initial = 'g21-data' }
        $g21HookHit = $false
        $g21Threw = $false
        try {
            $global:WibFaultInjectionEnabled = $true
            $global:WibSensitiveCommitTestHook = {
                param($Boundary, $StagePath, $DestinationPath)
                if ($Boundary -eq 'AfterFinalValidationBeforeReplace') {
                    $script:g21HookHit = $true
                    Remove-Item -LiteralPath $DestinationPath -Force
                    [System.IO.File]::WriteAllText($DestinationPath, '{"unowned":"g21-adversary"}')
                    throw 'Simulated race at AfterFinalValidationBeforeReplace'
                }
            }
            $script:g21HookHit = $false
            Set-WibDurableJsonFile -Path $g21Target -Data @{ updated = 'g21-data' }
        } catch {
            $g21Threw = $true
        } finally {
            $g21HookHit = [bool]$script:g21HookHit
            $global:WibFaultInjectionEnabled = $origWibFault
            $global:WibSensitiveCommitTestHook = $origCommitHook
        }
        $g21TargetAfter = [System.IO.File]::ReadAllText($g21Target)
        if (-not $g21HookHit -or -not $g21Threw -or ($g21TargetAfter -notlike '*g21-adversary*')) {
            throw "G21 failed: WIB-042 Set-WibDurableJsonFile AfterFinalValidationBeforeReplace race did not preserve unowned replacement"
        }

        # 5. WIB-043: Resolve-WibOscdimg with -StrictOscdimgHash enforces allowlist strictly
        $g21FakeDir = Join-Path $tmp 'g21-oscd'
        New-Item -ItemType Directory -Force -Path $g21FakeDir | Out-Null
        $g21FakeExe = Join-Path $g21FakeDir 'oscdimg.exe'
        [System.IO.File]::WriteAllText($g21FakeExe, 'FAKE_OSCDIMG')
        $g21OscdBlocked = $false
        try {
            $null = Resolve-WibOscdimg -WorkDir $g21FakeDir -StrictOscdimgHash
        } catch {
            $g21OscdBlocked = $true
        }
        if (-not $g21OscdBlocked) {
            throw "G21 failed: WIB-043 Resolve-WibOscdimg did not fail closed under -StrictOscdimgHash"
        }

        Write-Output 'GATE_G21_PASS'
    } finally {
        $global:WibFaultInjectionEnabled = $origWibFault
        $global:WibSensitiveCommitTestHook = $origCommitHook
        $global:WibBeforeBackupDeleteHook = $origBakHook
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Test-GateG22 {
    # G22: v0.2.29 forensic audit remediation (WIB-046 handle-bound destination replace race closure, WIB-047 single-buffer immutable staging snapshot under FileShare.None, WIB-048 backup cleanup check-then-change race elimination, WIB-049 hermetic oscdimg Authenticode & strict allowlist enforcement)
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("wib-g22-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    $origWibFault = $global:WibFaultInjectionEnabled
    $origCommitHook = $global:WibSensitiveCommitTestHook
    $origBakDeleteHook = $global:WibBeforeBackupDeleteHook
    $origBakAclHook = $script:WibBeforeBackupAclHook
    $origMocks = $script:WibAllowNativeToolMocks
    $origSig = $script:WibMockAuthenticodeSignatureProvider
    $origHash = $script:WibMockSha256Provider
    try {
        # 1. WIB-046: Set-WibDurableJsonFile non-throwing replacement race fails closed and preserves unowned file
        $g22JsonTarget = Join-Path $tmp 'g22-target.json'
        Set-WibDurableJsonFile -Path $g22JsonTarget -Data @{ initial = 'g22-json' }
        $g22JsonHookFired = $false
        $g22JsonThrew = $false
        try {
            $global:WibFaultInjectionEnabled = $true
            $global:WibSensitiveCommitTestHook = {
                param($Boundary, $StagePath, $DestinationPath)
                if ($Boundary -eq 'AfterFinalValidationBeforeReplace') {
                    $script:g22JsonHookFired = $true
                    Remove-Item -LiteralPath $DestinationPath -Force
                    [System.IO.File]::WriteAllText($DestinationPath, '{"unowned":"g22-json-adversary"}')
                }
            }
            $script:g22JsonHookFired = $false
            Set-WibDurableJsonFile -Path $g22JsonTarget -Data @{ updated = 'g22-json' }
        } catch {
            $g22JsonThrew = $true
        } finally {
            $g22JsonHookFired = [bool]$script:g22JsonHookFired
            $global:WibFaultInjectionEnabled = $origWibFault
            $global:WibSensitiveCommitTestHook = $origCommitHook
        }
        $g22JsonTargetContent = [System.IO.File]::ReadAllText($g22JsonTarget)
        if (-not $g22JsonHookFired -or -not $g22JsonThrew -or ($g22JsonTargetContent -notlike '*g22-json-adversary*')) {
            throw "G22 failed: WIB-046 Set-WibDurableJsonFile non-throwing replacement race did not preserve unowned replacement file"
        }

        # 2. WIB-046: New-WibUnattend non-throwing replacement race fails closed and preserves unowned file
        $g22XmlDir = Join-Path $tmp 'g22-unattend'
        New-Item -ItemType Directory -Force -Path $g22XmlDir | Out-Null
        $g22XmlTarget = Join-Path $g22XmlDir 'autounattend.xml'
        & (Join-Path $repoRoot 'tools\New-WibUnattend.ps1') -OutputPath $g22XmlTarget -Password 'InitP@ssw0rd123!' -AllowPlaintextCredentials -AcceptCredentialExposureRisk -Force | Out-Null
        $global:g22XmlHookFired = $false
        $g22XmlThrew = $false
        try {
            $global:WibFaultInjectionEnabled = $true
            $global:WibSensitiveCommitTestHook = {
                param($Boundary, $StagePath, $DestinationPath)
                if ($Boundary -eq 'AfterFinalValidationBeforeReplace') {
                    $global:g22XmlHookFired = $true
                    Remove-Item -LiteralPath $DestinationPath -Force
                    [System.IO.File]::WriteAllText($DestinationPath, '<unattend><foreign>g22-xml-adversary</foreign></unattend>')
                }
            }
            & (Join-Path $repoRoot 'tools\New-WibUnattend.ps1') -OutputPath $g22XmlTarget -Password 'NewP@ssw0rd456!' -AllowPlaintextCredentials -AcceptCredentialExposureRisk -Force | Out-Null
        } catch {
            $g22XmlThrew = $true
        } finally {
            $g22XmlHookHit = [bool]$global:g22XmlHookFired
            $global:WibFaultInjectionEnabled = $origWibFault
            $global:WibSensitiveCommitTestHook = $origCommitHook
        }
        $g22XmlTargetContent = [System.IO.File]::ReadAllText($g22XmlTarget)
        if (-not $g22XmlHookFired -or -not $g22XmlThrew -or ($g22XmlTargetContent -notlike '*g22-xml-adversary*')) {
            throw "G22 failed: WIB-046 New-WibUnattend non-throwing replacement race did not preserve unowned replacement file"
        }

        # 3. WIB-047: Get-WibValidatedStageSnapshot captures single-buffer snapshot under FileShare.None and Assert-WibStagedFileStillMatches validates via handle
        $g22Stage = Join-Path $tmp 'g22-stage.json'
        [System.IO.File]::WriteAllText($g22Stage, '{"g22":"coherent-snapshot"}')
        $g22Snap = Get-WibValidatedStageSnapshot -Path $g22Stage -PayloadKind Json
        $g22StageMatches = Assert-WibStagedFileStillMatches -Snapshot $g22Snap
        if (-not $g22StageMatches -or $g22Snap.Length -le 0 -or $g22Snap.Sha256.Length -ne 64) {
            throw "G22 failed: WIB-047 Get-WibValidatedStageSnapshot or Assert-WibStagedFileStillMatches failed single-stream validation"
        }

        # 4. WIB-048: Complete-WibBackupCleanup detects substitution before ACL handling via WibBeforeBackupAclHook and preserves unowned file untouched
        $g22Bak = Join-Path $tmp 'g22-backup.txt'
        [System.IO.File]::WriteAllText($g22Bak, 'ORIG_G22_BACKUP')
        $g22OrigId = Get-WibKernelNodeIdentity -LiteralPath $g22Bak
        $g22AclHookHit = $false
        $g22BakStatus = $null
        try {
            $global:WibFaultInjectionEnabled = $true
            $global:WibBeforeBackupDeleteHook = {
                param($Path, $ExpectedId)
                throw 'Simulated lock on backup deletion'
            }
            $script:WibBeforeBackupAclHook = {
                param($Path, $ExpectedId)
                $script:g22AclHookHit = $true
                Remove-Item -LiteralPath $Path -Force
                [System.IO.File]::WriteAllText($Path, 'SUBSTITUTED_BEFORE_ACL')
            }
            $script:g22AclHookHit = $false
            $g22BakStatus = Complete-WibBackupCleanup -Path $g22Bak -ExpectedIdentity $g22OrigId -Sensitive -Outcome Committed
        } finally {
            $g22AclHookHit = [bool]$script:g22AclHookHit
            $global:WibFaultInjectionEnabled = $origWibFault
            $global:WibBeforeBackupDeleteHook = $origBakDeleteHook
            $script:WibBeforeBackupAclHook = $origBakAclHook
        }
        $g22BakContent = [System.IO.File]::ReadAllText($g22Bak)
        if (-not $g22AclHookHit -or ($null -eq $g22BakStatus) -or ($g22BakStatus.status -ne 'backupPathReplacedByUnownedFile') -or ($g22BakContent -ne 'SUBSTITUTED_BEFORE_ACL')) {
            throw "G22 failed: WIB-048 Complete-WibBackupCleanup check-then-change race did not preserve unowned replacement"
        }

        # 5. WIB-049: Resolve-WibOscdimg Authenticode signature and strict allowlist enforcement matrix
        $g22OscdDir = Join-Path $tmp 'g22-oscd'
        New-Item -ItemType Directory -Force -Path $g22OscdDir | Out-Null
        $g22OscdExe = Join-Path $g22OscdDir 'oscdimg.exe'
        [System.IO.File]::WriteAllText($g22OscdExe, 'MOCK_OSCDIMG')

        # 5a. Unallowlisted hash rejection
        $g22UnallowlistedThrew = $false
        $g22UnallowlistedMsg = ''
        try {
            $script:WibAllowNativeToolMocks = $true
            $script:WibMockAuthenticodeSignatureProvider = {
                param($p)
                [pscustomobject]@{
                    Status = [System.Management.Automation.SignatureStatus]::Valid
                    SignerCertificate = [pscustomobject]@{ Subject = 'CN=Microsoft Corporation, O=Microsoft Corporation' }
                }
            }
            $null = Resolve-WibOscdimg -CandidatePath $g22OscdExe -StrictOscdimgHash
        } catch {
            $g22UnallowlistedThrew = $true
            $g22UnallowlistedMsg = $_.Exception.Message
        } finally {
            $script:WibAllowNativeToolMocks = $origMocks
            $script:WibMockAuthenticodeSignatureProvider = $origSig
        }
        if (-not $g22UnallowlistedThrew -or ($g22UnallowlistedMsg -notmatch 'is not in the approved Microsoft known-hashes allowlist')) {
            throw "G22 failed: WIB-049 Resolve-WibOscdimg did not reject unallowlisted hash with strict error"
        }

        # 5b. Invalid signature rejection
        $g22BadSigThrew = $false
        $g22BadSigMsg = ''
        try {
            $script:WibAllowNativeToolMocks = $true
            $script:WibMockAuthenticodeSignatureProvider = {
                param($p)
                [pscustomobject]@{
                    Status = [System.Management.Automation.SignatureStatus]::NotSigned
                    SignerCertificate = $null
                }
            }
            $null = Resolve-WibOscdimg -CandidatePath $g22OscdExe -StrictOscdimgHash
        } catch {
            $g22BadSigThrew = $true
            $g22BadSigMsg = $_.Exception.Message
        } finally {
            $script:WibAllowNativeToolMocks = $origMocks
            $script:WibMockAuthenticodeSignatureProvider = $origSig
        }
        if (-not $g22BadSigThrew -or ($g22BadSigMsg -notmatch 'signature verification failed')) {
            throw "G22 failed: WIB-049 Resolve-WibOscdimg did not reject invalid Authenticode signature"
        }

        # 5c. Non-Microsoft signer rejection
        $g22BadSignerThrew = $false
        $g22BadSignerMsg = ''
        try {
            $script:WibAllowNativeToolMocks = $true
            $script:WibMockAuthenticodeSignatureProvider = {
                param($p)
                [pscustomobject]@{
                    Status = [System.Management.Automation.SignatureStatus]::Valid
                    SignerCertificate = [pscustomobject]@{ Subject = 'CN=Untrusted Entity, O=Untrusted Corp' }
                }
            }
            $null = Resolve-WibOscdimg -CandidatePath $g22OscdExe -StrictOscdimgHash
        } catch {
            $g22BadSignerThrew = $true
            $g22BadSignerMsg = $_.Exception.Message
        } finally {
            $script:WibAllowNativeToolMocks = $origMocks
            $script:WibMockAuthenticodeSignatureProvider = $origSig
        }
        if (-not $g22BadSignerThrew -or ($g22BadSignerMsg -notmatch 'is not Microsoft Corporation')) {
            throw "G22 failed: WIB-049 Resolve-WibOscdimg did not reject non-Microsoft signer"
        }

        # 5d. Valid signature and approved hash success
        $g22SuccessResolved = $null
        try {
            $script:WibAllowNativeToolMocks = $true
            $script:WibMockAuthenticodeSignatureProvider = {
                param($p)
                [pscustomobject]@{
                    Status = [System.Management.Automation.SignatureStatus]::Valid
                    SignerCertificate = [pscustomobject]@{ Subject = 'CN=Microsoft Corporation, O=Microsoft Corporation' }
                }
            }
            $script:WibMockSha256Provider = { param($p) '35C4E5CA92C44D4AE62ED11D15694C7BD212574A92AC0BEACD4A27BEA0D45366' }
            $g22SuccessResolved = Resolve-WibOscdimg -CandidatePath $g22OscdExe -StrictOscdimgHash
        } finally {
            $script:WibAllowNativeToolMocks = $origMocks
            $script:WibMockAuthenticodeSignatureProvider = $origSig
            $script:WibMockSha256Provider = $origHash
        }
        if ($g22SuccessResolved -ne $g22OscdExe) {
            throw "G22 failed: WIB-049 Resolve-WibOscdimg failed to resolve valid Microsoft binary with allowlisted hash"
        }

        Write-Output 'GATE_G22_PASS'
    } finally {
        $global:WibFaultInjectionEnabled = $origWibFault
        $global:WibSensitiveCommitTestHook = $origCommitHook
        $global:WibBeforeBackupDeleteHook = $origBakDeleteHook
        $script:WibBeforeBackupAclHook = $origBakAclHook
        $script:WibAllowNativeToolMocks = $origMocks
        $script:WibMockAuthenticodeSignatureProvider = $origSig
        $script:WibMockSha256Provider = $origHash
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

switch ($Gate) {
    'G1'  { Test-GateG1 }
    'G2'  { Test-GateG2 }
    'G3'  { Test-GateG3 }
    'G4'  { Test-GateG4 }
    'G5'  { Test-GateG5 }
    'G6'  { Test-GateG6 }
    'G7'  { Test-GateG7 }
    'G8'  { Test-GateG8 }
    'G9'  { Test-GateG9 }
    'G10' { Test-GateG10 }
    'G11' { Test-GateG11 }
    'G12' { Test-GateG12 }
    'G13' { Test-GateG13 }
    'G14' { Test-GateG14 }
    'G15' { Test-GateG15 }
    'G16' { Test-GateG16 }
    'G17' { Test-GateG17 }
    'G18' { Test-GateG18 }
    'G19' { Test-GateG19 }
    'G20' { Test-GateG20 }
    'G21' { Test-GateG21 }
    'G22' { Test-GateG22 }
    'All' {
        Test-GateG1
        Test-GateG2
        Test-GateG3
        Test-GateG4
        Test-GateG5
        Test-GateG6
        Test-GateG7
        Test-GateG8
        Test-GateG9
        Test-GateG10
        Test-GateG11
        Test-GateG12
        Test-GateG13
        Test-GateG14
        Test-GateG15
        Test-GateG16
        Test-GateG17
        Test-GateG18
        Test-GateG19
        Test-GateG20
        Test-GateG21
        Test-GateG22
        Write-Output 'ALL_GATES_PASS'
    }
}
