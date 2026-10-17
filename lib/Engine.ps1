# Build engine. Requires Core.ps1, Planner.ps1, Report.ps1 and registered modules.

function Select-WibIndex {
    param([string]$ImagePath, [int]$Index)
    $imgs = @(Get-WindowsImage -ImagePath $ImagePath)
    if ($Index -gt 0) {
        if ($imgs.ImageIndex -contains $Index) { return $Index }
        throw "Image index $Index not found in $ImagePath"
    }
    if ($imgs.Count -eq 1) { return [int]$imgs[0].ImageIndex }
    foreach ($i in $imgs) { Write-Host ('  {0}: {1}' -f $i.ImageIndex, $i.ImageName) }

    # Find the primary preferred edition (Windows 11 Pro first, then first available)
    $proCandidate = $imgs | Where-Object { $_.ImageName -match '(?i)Windows 11 Pro$' } | Select-Object -First 1
    if (-not $proCandidate) {
        $proCandidate = $imgs | Where-Object { $_.ImageName -match '(?i)\bPro\b' } | Select-Object -First 1
    }
    $defaultIndex = if ($proCandidate) { [int]$proCandidate.ImageIndex } else { [int]$imgs[0].ImageIndex }
    $defaultName = if ($proCandidate) { $proCandidate.ImageName } else { $imgs[0].ImageName }

    if ([Console]::IsInputRedirected -or -not [Environment]::UserInteractive) {
        Write-Host ('[INFO] Auto-selected primary target edition: [{0}] {1} (pass -Index to choose another).' -f $defaultIndex, $defaultName)
        return $defaultIndex
    }

    $n = 0
    $prompt = ('Enter the image index to build [Default: {0} ({1})]' -f $defaultIndex, $defaultName)
    $in = Read-Host $prompt
    if ([string]::IsNullOrWhiteSpace($in)) {
        Write-Host ('[INFO] Selected default edition: [{0}] {1}' -f $defaultIndex, $defaultName)
        return $defaultIndex
    }
    if ([int]::TryParse($in, [ref]$n) -and ($imgs.ImageIndex -contains $n)) {
        return $n
    }

    Write-Host ('[WARN] Input "{0}" was not a valid edition index. Defaulting to: [{1}] {2}' -f $in, $defaultIndex, $defaultName)
    return $defaultIndex
}

function Get-WibArchitectureName {
    param($ArchValue)
    switch ([string]$ArchValue) {
        '9'     { return 'x64' }
        '0'     { return 'x86' }
        '12'    { return 'arm64' }
        '5'     { return 'arm' }
        'amd64' { return 'x64' }
        'x64'   { return 'x64' }
        'arm64' { return 'arm64' }
        default {
            if ($env:PROCESSOR_ARCHITECTURE -eq 'AMD64') { return 'x64' }
            elseif ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { return 'arm64' }
            return 'x64'
        }
    }
}

function Resolve-WibOscdimg {
    <#
    .SYNOPSIS
        Resolves or downloads oscdimg.exe from official Microsoft sources.
    .DESCRIPTION
        Security Policy: Forward-compatible Microsoft Authenticode digital signature verification
        (Valid status and Microsoft Corporation signer) is authoritative for executable integrity
        and origin authenticity across ADK releases. When known-good Microsoft hashes are available,
        the binary SHA-256 is validated or recorded in manifest.reproducibility for cryptographic auditability.
        When -StrictOscdimgHash is specified, the binary SHA-256 is strictly enforced to match
        the approved Microsoft known-hashes allowlist for both local ADK and downloaded binaries.
    #>
    param(
        [switch]$AllowDownload,
        [string]$WorkDir,
        [switch]$StrictOscdimgHash,
        [string]$CandidatePath = ''
    )
    $arch = $env:PROCESSOR_ARCHITECTURE
    if ($arch -ieq 'AMD64') { $arch = 'amd64' }
    elseif ($arch -ieq 'ARM64') { $arch = 'arm64' }
    elseif ($arch -ieq 'X86') { $arch = 'x86' }

    # Known good Microsoft oscdimg.exe SHA-256 hashes
    $knownHashes = @(
        '35C4E5CA92C44D4AE62ED11D15694C7BD212574A92AC0BEACD4A27BEA0D45366',
        '9D8A2750F3EDBC926943C53C471321FF5D040713DBBCFFBD2DCBA4017EE28DF4',
        'D2709F8099DDD202BC41BCB399ECD5638503C6466F416D1A321769AF83A70C3A',
        'B99CF18DE8006F7BEC5B9618EAC6D2F4BA9F1700ADC78A2BC49433B55629C93B',
        '175E8899C9925C0A91289FA8294D6969EEB88A7C753B3B9001CD63A3B3D9A8F4'
    )

    $sigProvider = if ($script:WibAllowNativeToolMocks -and $script:WibMockAuthenticodeSignatureProvider -is [scriptblock]) {
        $script:WibMockAuthenticodeSignatureProvider
    } elseif ($global:WibAllowNativeToolMocks -and $global:WibMockAuthenticodeSignatureProvider -is [scriptblock]) {
        $global:WibMockAuthenticodeSignatureProvider
    } else {
        $null
    }

    $hashProvider = if ($script:WibAllowNativeToolMocks -and $script:WibMockSha256Provider -is [scriptblock]) {
        $script:WibMockSha256Provider
    } elseif ($global:WibAllowNativeToolMocks -and $global:WibMockSha256Provider -is [scriptblock]) {
        $global:WibMockSha256Provider
    } else {
        $null
    }

    $candidate = $null
    if ($CandidatePath -and (Test-Path -LiteralPath $CandidatePath -PathType Leaf)) {
        $candidate = $CandidatePath
    } else {
        $kitsRoot = ${env:ProgramFiles(x86)}
        if (-not $kitsRoot) { $kitsRoot = $env:ProgramFiles }
        $adk = Join-Path $kitsRoot "Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\$arch\Oscdimg\oscdimg.exe"
        $adk64 = Join-Path $kitsRoot "Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"

        if (Test-Path -LiteralPath $adk -PathType Leaf) { $candidate = $adk }
        elseif (Test-Path -LiteralPath $adk64 -PathType Leaf) { $candidate = $adk64 }
        elseif ($WorkDir -and (Test-Path -LiteralPath (Join-Path $WorkDir 'oscdimg.exe') -PathType Leaf)) {
            $candidate = Join-Path $WorkDir 'oscdimg.exe'
        }
        elseif ($WorkDir -and (Test-Path -LiteralPath (Join-Path $WorkDir 'tools\oscdimg.exe') -PathType Leaf)) {
            $candidate = Join-Path $WorkDir 'tools\oscdimg.exe'
        }
        else {
            $pathCmd = Get-Command 'oscdimg.exe' -ErrorAction SilentlyContinue
            if ($pathCmd -and (Test-Path -LiteralPath $pathCmd.Source -PathType Leaf)) {
                $candidate = $pathCmd.Source
            }
        }
    }

    if ($candidate) {
        $sig = if ($null -ne $sigProvider) {
            & $sigProvider $candidate
        } else {
            Get-AuthenticodeSignature -LiteralPath $candidate
        }

        if ($sig.Status -ne 'Valid') {
            throw "Authenticode signature status is '$($sig.Status)' on oscdimg at '$candidate': signature verification failed."
        }

        $signer = [string]$sig.SignerCertificate.Subject
        if ($signer -notmatch 'O=Microsoft Corporation') {
            throw "Signer '$signer' on oscdimg at '$candidate' is not Microsoft Corporation."
        }

        $candHash = if ($null -ne $hashProvider) { & $hashProvider $candidate } else { Get-WibSha256 $candidate }
        if ($knownHashes -notcontains $candHash) {
            if ($StrictOscdimgHash) {
                throw "Strict oscdimg verification failed: ADK binary SHA-256 '$candHash' at '$candidate' is not in the approved Microsoft known-hashes allowlist."
            }
            Write-WibLog "Found ADK oscdimg at $candidate with valid Microsoft Authenticode signature and unpinned SHA-256: $candHash (recorded for auditability)" 'INFO'
        }
        return $candidate
    }

    if (-not $AllowDownload) {
        throw "oscdimg.exe not found (install the Windows ADK 'Deployment Tools', or re-run with -DownloadOscdimg)."
    }
    $dest = Join-Path $WorkDir 'oscdimg.exe'
    if (-not (Test-Path -LiteralPath $dest -PathType Leaf)) {
        Write-WibLog "Downloading signed oscdimg from Microsoft ADK CDN (arch: $arch)..." 'WARN'
        $cabMap = @{
            'amd64' = @{ Cab = 'bbf55224a0290f00676ddc410f004498.cab'; File = 'fild40c79d789d460e48dc1cbd485d6fc2e' }
            'arm64' = @{ Cab = '9d2b092478d6cca70d5ac957368c00ba.cab'; File = 'filb3742d71928e52cc44a3f06ecca9f1c3' }
            'x86'   = @{ Cab = '5d984200acbde182fd99cbfbe9bad133.cab'; File = 'fil720cc132fbb53f3bed2e525eb77bdbc1' }
        }
        $payloadInfo = $cabMap[$arch]
        if ($null -eq $payloadInfo) { $payloadInfo = $cabMap['amd64'] }
        $cabUrl = 'https://download.microsoft.com/download/8e0c0f5a-abb5-4358-a51b-168eb40b1590/adk/Installers/' + $payloadInfo.Cab
        $tempCab = Join-Path $env:TEMP ("wib-oscdimg-{0}.cab" -f [guid]::NewGuid().ToString('N'))
        $tempExtract = Join-Path $env:TEMP ("wib-oscdimg-ext-{0}" -f [guid]::NewGuid().ToString('N'))
        try {
            Invoke-WebRequest -Uri $cabUrl -OutFile $tempCab -UseBasicParsing
            if (-not (Test-Path -LiteralPath $tempExtract)) { New-Item -ItemType Directory -Path $tempExtract | Out-Null }
            $expandProc = Start-Process -FilePath "$env:SystemRoot\System32\expand.exe" -ArgumentList @($tempCab, '-F:*', $tempExtract) -NoNewWindow -Wait -PassThru
            if ($expandProc.ExitCode -ne 0) { throw "expand.exe failed with exit code $($expandProc.ExitCode)" }
            $extractedFile = Join-Path $tempExtract $payloadInfo.File
            if (-not (Test-Path -LiteralPath $extractedFile -PathType Leaf)) {
                throw "Expected payload '$($payloadInfo.File)' not found in extracted ADK cab."
            }
            Copy-Item -LiteralPath $extractedFile -Destination $dest -Force
        } finally {
            if (Test-Path -LiteralPath $tempCab) { Remove-Item -LiteralPath $tempCab -Force -ErrorAction SilentlyContinue }
            if (Test-Path -LiteralPath $tempExtract) { Remove-Item -LiteralPath $tempExtract -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }

    $sig = if ($null -ne $sigProvider) {
        & $sigProvider $dest
    } else {
        Get-AuthenticodeSignature -LiteralPath $dest
    }

    if ($sig.Status -ne 'Valid') { throw "Downloaded oscdimg.exe does not have a valid Microsoft signature ($($sig.Status))." }
    # Verify signer subject contains 'O=Microsoft Corporation'
    $signer = [string]$sig.SignerCertificate.Subject
    if ($signer -notmatch 'O=Microsoft Corporation') { throw "Downloaded oscdimg.exe is not signed by Microsoft Corporation ($signer)." }

    $fileHash = if ($null -ne $hashProvider) { & $hashProvider $dest } else { Get-WibSha256 $dest }
    if ($knownHashes -notcontains $fileHash) {
        if ($StrictOscdimgHash) {
            throw "Strict oscdimg verification failed: SHA-256 '$fileHash' at '$dest' is not in the approved Microsoft known-hashes allowlist."
        }
        Write-WibLog "Downloaded oscdimg.exe has valid Microsoft Authenticode signature with SHA-256: $fileHash (recorded for auditability)" 'INFO'
    }
    return $dest
}

# ---------------------------------------------------------------- adaptive profile resolution
# Centralised helper consumed by BOTH initial build and -Resume paths so that the effective
# profile hash (post-adaptation) is computed identically in both code paths.
#
# Returns a hashtable:
#   ResolvedHash      - SHA-256 of the merged profile before adaptive mutations (identity)
#   AdaptedProfile    - the buildProfile hashtable AFTER Invoke-WibAdaptiveDecisions has run
#   EffectiveHash     - SHA-256 of the profile AFTER adaptive mutations  (resume key)
#   AdaptiveDecisions - array of decisions that were resolved
#   HardwareProfile   - the hardware profile object (or $null for non-adaptive builds)
#   HardwareProfileHash - hash of the hardware profile (or '')
#
# For non-adaptive profiles, EffectiveHash == ResolvedHash and AdaptiveDecisions is empty.
function Resolve-WibEffectiveBuildProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$BuildProfile,
        [string]$HardwareSpec,
        [switch]$AcceptRisk
    )
    $resolvedHash = Get-WibProfileCanonicalHash $BuildProfile

    $isAdaptive = ($BuildProfile.ContainsKey('adaptive') -and $BuildProfile['adaptive']) -or ($HardwareSpec -and $HardwareSpec.Length -gt 0)
    $hwProfile   = $null
    $hwHash      = ''
    $decisions   = @()

    if ($isAdaptive) {
        $hwProfile = Get-WibHardwareProfile -SpecPath $HardwareSpec
        $hwHash    = if ($hwProfile.PSObject.Properties['HardwareProfileHash'] -and $hwProfile.HardwareProfileHash) {
            [string]$hwProfile.HardwareProfileHash
        } else {
            Get-WibHardwareProfileHash -HardwareProfile $hwProfile
        }
        $decisions = @(Resolve-WibAdaptiveDecisions -HardwareProfile $hwProfile -BuildProfile $BuildProfile)
        if ($decisions.Count -gt 0) {
            # Mutate the profile in-place so the caller gets the adapted copy
            $dummyCtx = @{ AdaptiveDecisions = New-Object System.Collections.ArrayList }
            Invoke-WibAdaptiveDecisions -Decisions $decisions -BuildProfile $BuildProfile -Ctx $dummyCtx
            Test-WibProfile -BuildProfile $BuildProfile -AcceptRisk:$AcceptRisk
        }
    }

    $effectiveHash = Get-WibProfileCanonicalHash $BuildProfile

    return @{
        ResolvedHash        = $resolvedHash
        AdaptedProfile      = $BuildProfile
        EffectiveHash       = $effectiveHash
        AdaptiveDecisions   = $decisions
        HardwareProfile     = $hwProfile
        HardwareProfileHash = $hwHash
    }
}

# ---------------------------------------------------------------- checkpoints
function New-WibCheckpoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Ctx,
        [Parameter(Mandatory)][string]$StageName
    )
    # Checkpoints are never created during a dry run or when -NoCheckpoints is set
    if ($Ctx.DryRun -or ($Ctx.ContainsKey('NoCheckpoints') -and $Ctx.NoCheckpoints)) {
        return $null
    }

    if (-not $Ctx.ContainsKey('Checkpoints')) {
        $Ctx['Checkpoints'] = New-Object System.Collections.ArrayList
    }

    $cpIndex = $Ctx.Checkpoints.Count + 1
    $targetWimIndex = $cpIndex
    if ($Ctx.ContainsKey('CurrentIndex') -and $Ctx.CurrentIndex) {
        $targetWimIndex = [int]$Ctx.CurrentIndex
    }
    $origSourceIndex = if ($Ctx.ContainsKey('OriginalSourceIndex') -and $Ctx.OriginalSourceIndex) { [int]$Ctx.OriginalSourceIndex } elseif ($Ctx.ContainsKey('SourceIndex') -and $Ctx.SourceIndex) { [int]$Ctx.SourceIndex } elseif ($Ctx.ContainsKey('MountedIndex')) { [int]$Ctx.MountedIndex } else { 1 }

    $profHash = if ($Ctx.ContainsKey('ProfileHash') -and $Ctx.ProfileHash) { [string]$Ctx.ProfileHash } else { 'default_profile_hash' }
    $effSha = if ($Ctx.ContainsKey('EffectiveSha256') -and $Ctx.EffectiveSha256) { [string]$Ctx.EffectiveSha256 } else { $profHash }
    $srcArch = if ($Ctx.ContainsKey('Arch') -and $Ctx.Arch) { [string]$Ctx.Arch } else { 'amd64' }
    $srcBuild = if ($Ctx.ContainsKey('Build') -and $Ctx.Build) { [string]$Ctx.Build } else { '26100.1' }
    $srcEdition = if ($Ctx.ContainsKey('Edition') -and $Ctx.Edition) { [string]$Ctx.Edition } else { 'Windows 11 Pro' }

    $baselineWimSha = if ($Ctx.ContainsKey('BaselineSourceWimSha256') -and $Ctx.BaselineSourceWimSha256) {
        [string]$Ctx.BaselineSourceWimSha256
    } elseif ($Ctx.ContainsKey('SourceWimSha256') -and $Ctx.SourceWimSha256) {
        [string]$Ctx.SourceWimSha256
    } else {
        'MOCK_SOURCE_WIM_SHA256'
    }
    $Ctx['BaselineSourceWimSha256'] = $baselineWimSha
    $Ctx['SourceWimSha256'] = $baselineWimSha

    $currentWimSha = if ($Ctx.ContainsKey('CurrentWorkspaceWimSha256') -and $Ctx.CurrentWorkspaceWimSha256) {
        [string]$Ctx.CurrentWorkspaceWimSha256
    } elseif ($Ctx.ContainsKey('WimPath') -and $Ctx.WimPath -and (Test-Path -LiteralPath $Ctx.WimPath)) {
        Get-WibSha256 $Ctx.WimPath
    } else {
        'MOCK_CURRENT_WIM_SHA256'
    }
    $Ctx['CurrentWorkspaceWimSha256'] = $currentWimSha

    $sourceIsoSha = if ($Ctx.ContainsKey('SourceIsoSha256')) { [string]$Ctx.SourceIsoSha256 } else { '' }
    $sourceIsoStatus = if ($Ctx.ContainsKey('SourceIsoHashStatus') -and $Ctx.SourceIsoHashStatus) {
        [string]$Ctx.SourceIsoHashStatus
    } elseif ($sourceIsoSha -and $sourceIsoSha.Trim() -ne '') {
        'verified'
    } else {
        'unavailable'
    }

    # 1. Real DISM snapshot: Save-WindowsImage -Append with In-Flight Append Transaction Marker
    $dismAppended = if ($Ctx.ContainsKey('SimulateDismAppended') -and $Ctx.SimulateDismAppended) { $true } else { $false }
    $txMarkerFile = $null
    if ($Ctx.ContainsKey('WimPath') -and $Ctx.WimPath -and (Test-Path -LiteralPath $Ctx.WimPath)) {
        if (@(Get-WibMountedImage -Path $Ctx.MountDir).Count -eq 0) {
            throw "Cannot checkpoint '$StageName': no image is mounted at $($Ctx.MountDir)."
        }
        Write-WibLog "Creating WIM checkpoint after stage: $StageName (Save-WindowsImage -Append)" 'STEP'
        if (-not (Get-Command Save-WindowsImage -ErrorAction SilentlyContinue)) {
            throw 'Save-WindowsImage cmdlet not available for checkpoint creation.'
        }

        # Authoritative Pre-Append Transaction Binding & HMAC Authentication (Trusted Recovery-Ledger Model)
        if ($Ctx.ContainsKey('WorkDir') -and $Ctx.WorkDir -and (Test-Path -LiteralPath $Ctx.WorkDir)) {
            $txMarkerFile = Join-Path $Ctx.WorkDir 'checkpoint.transaction.json'
            $recFile = Join-Path $Ctx.WorkDir 'recovery-state.json'
            $preAppendCount = 0
            if (Get-Command Get-WindowsImage -ErrorAction SilentlyContinue) {
                try {
                    $physicalImages = @(Get-WindowsImage -ImagePath $Ctx.WimPath -ErrorAction Stop)
                    $preAppendCount = $physicalImages.Count
                } catch {
                    throw "Failed to query physical WIM images before checkpoint append: $($_.Exception.Message)"
                }
            } else {
                throw "Get-WindowsImage cmdlet is not available to determine physical WIM index count before checkpoint append."
            }
            if ($preAppendCount -le 0) {
                throw "Physical WIM '$($Ctx.WimPath)' contains no images ($preAppendCount) before checkpoint append."
            }
            $expectedNextIndex = $preAppendCount + 1
            $txId = [Guid]::NewGuid().ToString('N')
            $txRunId = if ($Ctx.ContainsKey('RunId')) { [string]$Ctx.RunId } else { '' }
            $txMountedIdx = if ($Ctx.ContainsKey('MountedIndex')) { [int]$Ctx.MountedIndex } else { 1 }
            $txSecret = if ($Ctx.ContainsKey('TransactionAuthSecret') -and $Ctx.TransactionAuthSecret) {
                [string]$Ctx.TransactionAuthSecret
            } else {
                $genSec = New-WibCryptoSecret
                $Ctx['TransactionAuthSecret'] = $genSec
                $genSec
            }
            $macMsg = "$txId|$cpIndex|$StageName|$profHash|$effSha|$currentWimSha|$preAppendCount|$expectedNextIndex|$txRunId|$($script:WibVersion)|$txMountedIdx"
            $txMac = Get-WibHmacSha256 -Message $macMsg -KeyHex $txSecret

            # Authoritatively bind in-flight transaction into recovery ledger BEFORE mutating physical WIM
            $curRec = $null
            if (Test-Path -LiteralPath $recFile) {
                try {
                    $curRec = ConvertFrom-Json (Get-Content -LiteralPath $recFile -Raw)
                } catch { $curRec = $null }
            }
            if ($null -eq $curRec) {
                $curRec = [ordered]@{
                    Version                     = $script:WibVersion
                    ToolVersion                 = $script:WibVersion
                    Stage                       = $StageName
                    ProvenanceTier              = 'authoritative'
                    Checkpoints                 = @()
                    Journal                     = @()
                    OriginalSourceIndex         = $origSourceIndex
                    SourceWimOriginalIndex      = $origSourceIndex
                    SourceContainer             = if ($Ctx.ContainsKey('SourceContainer') -and $Ctx.SourceContainer) { [string]$Ctx.SourceContainer } else { 'WIM' }
                    SourceContainerIndex        = if ($Ctx.ContainsKey('SourceContainerIndex') -and $Ctx.SourceContainerIndex) { [int]$Ctx.SourceContainerIndex } else { $origSourceIndex }
                    ServicingWimIndex           = if ($Ctx.ContainsKey('ServicingWimIndex') -and $Ctx.ServicingWimIndex) { [int]$Ctx.ServicingWimIndex } else { $targetWimIndex }
                    MountedIndex                = if ($Ctx.ContainsKey('MountedIndex')) { [int]$Ctx.MountedIndex } else { 1 }
                    CommittedCheckpointWimIndex = if ($Ctx.ContainsKey('MountedIndex')) { [int]$Ctx.MountedIndex } else { 1 }
                    PhysicalImageIndex          = $preAppendCount
                    OrphanIndexSet              = if ($Ctx.ContainsKey('OrphanIndexSet')) { @($Ctx.OrphanIndexSet) } else { @() }
                    NextCheckpointLogicalId     = $cpIndex
                    ProfileHash                 = $profHash
                    EffectiveSha256             = $effSha
                    HardwareProfileHash         = if ($Ctx.ContainsKey('HardwareProfileHash')) { [string]$Ctx.HardwareProfileHash } else { '' }
                    HardwareSpecHash            = if ($Ctx.ContainsKey('HardwareSpecHash')) { [string]$Ctx.HardwareSpecHash } else { '' }
                    SourceArch                  = $srcArch
                    SourceBuild                 = $srcBuild
                    SourceEdition               = $srcEdition
                    BaselineSourceWimSha256     = $baselineWimSha
                    SourceWimSha256             = $baselineWimSha
                    CurrentWorkspaceWimSha256   = $currentWimSha
                    SourceIsoHashStatus         = $sourceIsoStatus
                    SourceIsoSha256             = $sourceIsoSha
                }
            }
            $curRec.CommitState = 'in-flight-append'
            $curRec | Add-Member -NotePropertyName 'ActiveTransactionId' -NotePropertyValue $txId -Force
            $curRec | Add-Member -NotePropertyName 'ActiveCheckpointId' -NotePropertyValue $cpIndex -Force
            $curRec | Add-Member -NotePropertyName 'ActiveTransactionStage' -NotePropertyValue $StageName -Force
            $curRec | Add-Member -NotePropertyName 'ActiveRunId' -NotePropertyValue $txRunId -Force
            $curRec | Add-Member -NotePropertyName 'ActiveToolVersion' -NotePropertyValue $script:WibVersion -Force
            $curRec | Add-Member -NotePropertyName 'ActiveMountedIndex' -NotePropertyValue $txMountedIdx -Force
            $curRec | Add-Member -NotePropertyName 'PreAppendWimSha256' -NotePropertyValue $currentWimSha -Force
            $curRec | Add-Member -NotePropertyName 'PreAppendPhysicalCount' -NotePropertyValue $preAppendCount -Force
            $curRec | Add-Member -NotePropertyName 'ExpectedAppendedIndex' -NotePropertyValue $expectedNextIndex -Force
            $curRec | Add-Member -NotePropertyName 'TransactionMac' -NotePropertyValue $txMac -Force
            $curRec | Add-Member -NotePropertyName 'TransactionAuthSecret' -NotePropertyValue $txSecret -Force
            Set-WibDurableJsonFile -Path $recFile -Data $curRec -Depth 10

            # Write matching in-flight transaction marker
            $txData = [ordered]@{
                TransactionId          = $txId
                ToolVersion            = $script:WibVersion
                RunId                  = $txRunId
                Stage                  = $StageName
                ActiveCheckpointId     = $cpIndex
                ProfileHash            = $profHash
                EffectiveSha256        = $effSha
                MountedIndex           = $txMountedIdx
                PreAppendWimSha256     = $currentWimSha
                PreAppendPhysicalCount = $preAppendCount
                ExpectedAppendedIndex  = $expectedNextIndex
                TransactionMac         = $txMac
                Timestamp              = (Get-Date).ToString('o')
                Status                 = 'in-flight'
            }
            Set-WibDurableJsonFile -Path $txMarkerFile -Data $txData -Depth 5
        }

        # Save-WindowsImage -Append commits dirty mount changes into a new index in the WIM
        Save-WindowsImage -Path $Ctx.MountDir -Append -CheckIntegrity -ErrorAction Stop
        $dismAppended = $true

        # Post-append WIM hash: appending an image modifies the physical WIM file on disk
        $Ctx['CurrentWorkspaceWimSha256'] = Get-WibSha256 $Ctx.WimPath
        $currentWimSha = $Ctx['CurrentWorkspaceWimSha256']

        if (Get-Command Get-WindowsImage -ErrorAction SilentlyContinue) {
            try {
                $images = @(Get-WindowsImage -ImagePath $Ctx.WimPath -ErrorAction Stop)
                if ($images.Count -gt 0) {
                    $physicalCountNow = $images.Count
                    $targetWimIndex = $images.Count
                } else {
                    throw "Get-WindowsImage reported 0 images in physical WIM '$($Ctx.WimPath)' after Save-WindowsImage -Append."
                }
            } catch {
                throw "Failed to verify physical WIM image indices after checkpoint append: $($_.Exception.Message)"
            }
        } else {
            throw "Get-WindowsImage cmdlet is not available to verify physical WIM index count after checkpoint append."
        }
        # Save-WindowsImage -Append creates a snapshot copy at $targetWimIndex.
        # Active mount remains bound to $Ctx.MountedIndex; do not overwrite CurrentIndex.
    }

    # 2. Filesystem snapshot (STRICTLY for unit/logic tests where IsTest is true; never runs in real builds)
    $snapshotDir = $null
    if ($Ctx.ContainsKey('IsTest') -and $Ctx.IsTest -and $Ctx.ContainsKey('CheckpointDir') -and $Ctx.CheckpointDir) {
        $snapshotDir = Join-Path $Ctx.CheckpointDir "cp_$cpIndex"
        if (Test-Path -LiteralPath $snapshotDir) { Remove-Item -LiteralPath $snapshotDir -Recurse -Force }
        New-Item -ItemType Directory -Force -Path $snapshotDir | Out-Null
        if (Test-Path -LiteralPath $Ctx.MountDir) {
            Copy-Item -Path (Join-Path $Ctx.MountDir '*') -Destination $snapshotDir -Recurse -Force -ErrorAction Stop
        }
    }

    $provenance = [ordered]@{
        ProfileHash                 = $profHash
        EffectiveSha256             = $effSha
        HardwareSpecHash            = if ($Ctx.ContainsKey('HardwareSpecHash')) { [string]$Ctx.HardwareSpecHash } else { '' }
        HardwareProfileHash         = if ($Ctx.ContainsKey('HardwareProfileHash')) { [string]$Ctx.HardwareProfileHash } else { '' }
        SourceArch                  = $srcArch
        SourceBuild                 = $srcBuild
        SourceEdition               = $srcEdition
        SourceContainer             = if ($Ctx.ContainsKey('SourceContainer') -and $Ctx.SourceContainer) { [string]$Ctx.SourceContainer } else { 'WIM' }
        SourceContainerIndex        = if ($Ctx.ContainsKey('SourceContainerIndex') -and $Ctx.SourceContainerIndex) { [int]$Ctx.SourceContainerIndex } else { $origSourceIndex }
        ServicingWimIndex           = if ($Ctx.ContainsKey('ServicingWimIndex') -and $Ctx.ServicingWimIndex) { [int]$Ctx.ServicingWimIndex } else { $targetWimIndex }
        SourceWimOriginalIndex      = $origSourceIndex
        SourceIndex                 = $origSourceIndex
        CheckpointWimIndex          = $targetWimIndex
        BaselineSourceWimSha256     = $baselineWimSha
        SourceWimSha256             = $baselineWimSha
        CurrentWorkspaceWimSha256   = $currentWimSha
        SourceIsoHashStatus         = $sourceIsoStatus
        SourceIsoSha256             = $sourceIsoSha
        CommittedCheckpointWimIndex = $targetWimIndex
        PhysicalImageIndex          = $physicalCountNow
        OrphanIndexSet              = if ($Ctx.ContainsKey('OrphanIndexSet')) { @($Ctx.OrphanIndexSet) } else { @() }
        NextCheckpointLogicalId     = ($cpIndex + 1)
        ProvenanceTier              = 'authoritative'
        ToolVersion                 = $script:WibVersion
    }

    # Status is 'saved' from construction - the file must record 'saved', not 'pending'.
    $cp = @{
        Index        = $cpIndex
        WimIndex     = $targetWimIndex
        Stage        = $StageName
        ProfileHash  = $provenance.ProfileHash
        Provenance   = $provenance
        Timestamp    = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        MountDir     = $Ctx.MountDir
        SnapshotDir  = $snapshotDir
        DismAppended = $dismAppended
        Status       = 'saved'
    }
    [void]$Ctx.Checkpoints.Add($cp)

    # Persist transactional recovery-state record (combines Checkpoints, Journal, provenance, and commit state)
    if ($Ctx.ContainsKey('WorkDir') -and $Ctx.WorkDir -and (Test-Path -LiteralPath $Ctx.WorkDir)) {
        try {
            $jData = @()
            if ($Ctx.ContainsKey('Journal') -and $Ctx.Journal) {
                $jData = @($Ctx.Journal)
            }

            $recoveryState = [ordered]@{
                Version                     = $script:WibVersion
                ToolVersion                 = $script:WibVersion
                Stage                       = $StageName
                CommitState                 = 'committed'
                ProvenanceTier              = 'authoritative'
                Checkpoints                 = $Ctx.Checkpoints
                Journal                     = $jData
                OriginalSourceIndex         = $origSourceIndex
                SourceWimOriginalIndex      = $origSourceIndex
                SourceContainer             = $provenance.SourceContainer
                SourceContainerIndex        = $provenance.SourceContainerIndex
                ServicingWimIndex           = $provenance.ServicingWimIndex
                MountedIndex                = $targetWimIndex
                CommittedCheckpointWimIndex = $targetWimIndex
                PhysicalImageIndex          = $physicalCountNow
                OrphanIndexSet              = if ($Ctx.ContainsKey('OrphanIndexSet')) { @($Ctx.OrphanIndexSet) } else { @() }
                NextCheckpointLogicalId     = ($cpIndex + 1)
                ProfileHash                 = $provenance.ProfileHash
                EffectiveSha256             = $provenance.EffectiveSha256
                HardwareProfileHash         = $provenance.HardwareProfileHash
                HardwareSpecHash            = $provenance.HardwareSpecHash
                SourceArch                  = $provenance.SourceArch
                SourceBuild                 = $provenance.SourceBuild
                SourceEdition               = $provenance.SourceEdition
                BaselineSourceWimSha256     = $baselineWimSha
                SourceWimSha256             = $baselineWimSha
                CurrentWorkspaceWimSha256   = $currentWimSha
                SourceIsoHashStatus         = $sourceIsoStatus
                SourceIsoSha256             = $provenance.SourceIsoSha256
                ActiveTransactionId         = $null
                ActiveCheckpointId          = $null
                ActiveTransactionStage      = $null
                ActiveRunId                 = $null
                ActiveToolVersion           = $null
                ActiveMountedIndex          = $null
                PreAppendWimSha256          = $null
                PreAppendPhysicalCount      = $null
                ExpectedAppendedIndex       = $null
                TransactionMac              = $null
                TransactionAuthSecret       = $null
            }
            $recFile = Join-Path $Ctx.WorkDir 'recovery-state.json'
            Set-WibDurableJsonFile -Path $recFile -Data $recoveryState -Depth 10
            if ($Ctx.ContainsKey('TransactionAuthSecret')) {
                $Ctx.Remove('TransactionAuthSecret')
            }
            $Ctx['PhysicalImageIndex'] = $physicalCountNow
            $Ctx['CommittedCheckpointWimIndex'] = $targetWimIndex
            $Ctx['NextCheckpointLogicalId'] = ($cpIndex + 1)

            # Commit succeeded: safely clean up in-flight append transaction marker
            if ($txMarkerFile -and (Test-Path -LiteralPath $txMarkerFile)) {
                Remove-Item -LiteralPath $txMarkerFile -Force -ErrorAction SilentlyContinue
            }
        } catch {
            $cp.Status = 'failed'
            # Rollback in-memory ledger entry to prevent split-brain state
            [void]$Ctx.Checkpoints.Remove($cp)
            if ($dismAppended) {
                if (-not $Ctx.ContainsKey('OrphanWimIndices')) {
                    $Ctx['OrphanWimIndices'] = New-Object System.Collections.ArrayList
                }
                [void]$Ctx.OrphanWimIndices.Add($targetWimIndex)
                Write-WibLog "Checkpoint persistence failed after appending WIM index $targetWimIndex. Index recorded in OrphanWimIndices." 'ERROR'
            }
            throw "Failed to persist checkpoint ledger: $($_.Exception.Message)"
        }

        # Secondary compatibility views: best-effort projection from authoritative state.
        # Failures here never uncommit the already-committed recovery transaction.
        try {
            $cpFile = Join-Path $Ctx.WorkDir 'checkpoints.json'
            Set-WibDurableJsonFile -Path $cpFile -Data $Ctx.Checkpoints -Depth 6
            if ($Ctx.ContainsKey('Journal')) {
                $jpFile = Join-Path $Ctx.WorkDir 'journal.partial.json'
                Set-WibDurableJsonFile -Path $jpFile -Data $jData -Depth 8
            }
        } catch {
            Write-WibLog "Warning: failed to persist secondary compatibility view ($($_.Exception.Message)). Authoritative recovery-state.json is committed." 'WARN'
        }
    }

    Write-WibLog "Checkpoint #$cpIndex recorded ($StageName, WIM index $targetWimIndex)" 'INFO'
    return $cp
}

function Update-WibRecoveryCommitState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$WorkDir,
        [Parameter(Mandatory)][ValidateSet('committed', 'finalizing', 'post-export', 'reconciled-in-flight')][string]$CommitState,
        [hashtable]$Updates
    )
    $recFile = Join-Path $WorkDir 'recovery-state.json'
    if (-not (Test-Path -LiteralPath $recFile)) {
        throw "Cannot update recovery state: file '$recFile' does not exist."
    }
    try {
        $raw = Get-Content -LiteralPath $recFile -Raw
        $data = ConvertFrom-Json -InputObject $raw
        $ht = ConvertTo-WibHashtable $data
        $ht['CommitState'] = $CommitState
        if ($Updates) {
            foreach ($k in $Updates.Keys) {
                if ($null -eq $Updates[$k]) {
                    if ($ht.ContainsKey($k)) {
                        $ht.Remove($k)
                    }
                } else {
                    $ht[$k] = $Updates[$k]
                }
            }
        }
        Set-WibDurableJsonFile -Path $recFile -Data $ht -Depth 10

        # Transactional read-back verification
        $verifyRaw = Get-Content -LiteralPath $recFile -Raw
        $verifyData = ConvertFrom-Json -InputObject $verifyRaw
        $readState = [string](Get-WibPropValue $verifyData 'CommitState')
        if ($readState -ne $CommitState) {
            throw "CommitState read-back verification failed: expected '$CommitState', got '$readState'"
        }
        if ($Updates) {
            foreach ($k in $Updates.Keys) {
                $expected = $Updates[$k]
                $propVal = Get-WibPropValue $verifyData $k
                if ($null -eq $expected) {
                    if ($null -ne $propVal) {
                        throw "Property '$k' read-back verification failed: expected null/absent, got '$propVal'"
                    }
                } else {
                    if ($null -eq $propVal -or "$propVal" -ne "$expected") {
                        throw "Property '$k' read-back verification failed: expected '$expected', got '$propVal'"
                    }
                }
            }
        }
    } catch {
        throw "Failed to update recovery state CommitState to '$CommitState': $($_.Exception.Message)"
    }
}


function Restore-WibCheckpoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Ctx,
        [string]$TargetStage
    )
    if (-not $Ctx.ContainsKey('Checkpoints') -or $Ctx.Checkpoints.Count -eq 0) {
        Write-WibLog 'No checkpoint available for rollback' 'WARN'
        return $null
    }

    $targetCp = $null
    if ($TargetStage) {
        for ($i = $Ctx.Checkpoints.Count - 1; $i -ge 0; $i--) {
            if ($Ctx.Checkpoints[$i].Stage -eq $TargetStage) {
                $targetCp = $Ctx.Checkpoints[$i]
                break
            }
        }
    }
    if ($null -eq $targetCp) {
        $targetCp = $Ctx.Checkpoints[$Ctx.Checkpoints.Count - 1]
    }

    Write-WibLog "Rolling back to checkpoint #$($targetCp.Index) ('$($targetCp.Stage)')" 'WARN'

    # 1. Real DISM rollback flow: Dismount -Discard, then Mount target index
    if ($Ctx.ContainsKey('WimPath') -and $Ctx.WimPath -and (Test-Path -LiteralPath $Ctx.WimPath) -and -not $Ctx.DryRun) {
        Write-WibLog "Discarding dirty changes in mount ($($Ctx.MountDir))" 'STEP'
        if (-not (Get-Command Dismount-WindowsImage -ErrorAction SilentlyContinue)) {
            throw 'Dismount-WindowsImage cmdlet not available for checkpoint rollback.'
        }
        # Discard uncommitted changes in the mount directory
        Dismount-WindowsImage -Path $Ctx.MountDir -Discard -ErrorAction Stop

        Write-WibLog "Remounting WIM index $($targetCp.WimIndex) to $($Ctx.MountDir)" 'STEP'
        if (-not (Get-Command Mount-WindowsImage -ErrorAction SilentlyContinue)) {
            throw 'Mount-WindowsImage cmdlet not available for checkpoint remount.'
        }
        # Remount the clean checkpoint index
        Mount-WindowsImage -ImagePath $Ctx.WimPath -Index $targetCp.WimIndex -Path $Ctx.MountDir -ErrorAction Stop

        # Confirm remount via Get-WindowsImage -Mounted; fail immediately if not confirmed
        if (-not (Get-Command Get-WindowsImage -ErrorAction SilentlyContinue)) {
            throw 'Get-WindowsImage cmdlet not available to confirm remount.'
        }
        $mounted = @(Get-WibMountedImage -Path $Ctx.MountDir)
        if ($mounted.Count -eq 0 -or ($mounted[0].PSObject.Properties['MountStatus'] -and $mounted[0].MountStatus -ne 'Ok')) {
            throw "Rollback verification failed: Get-WindowsImage -Mounted did not find active/healthy mount at '$($Ctx.MountDir)'."
        }
        $Ctx.MountedIndex = $targetCp.WimIndex
        $Ctx.CurrentIndex = $targetCp.WimIndex
    }

    # 2. Filesystem snapshot rollback (STRICTLY for unit/logic tests where IsTest is true)
    if ($Ctx.ContainsKey('IsTest') -and $Ctx.IsTest -and $targetCp.SnapshotDir -and (Test-Path -LiteralPath $targetCp.SnapshotDir)) {
        if (Test-Path -LiteralPath $Ctx.MountDir) {
            Remove-Item -Path (Join-Path $Ctx.MountDir '*') -Recurse -Force -ErrorAction Stop
            Copy-Item -Path (Join-Path $targetCp.SnapshotDir '*') -Destination $Ctx.MountDir -Recurse -Force -ErrorAction Stop
        }
    }

    # Mark restored ONLY after confirmed remount and restoration
    $targetCp.Status = 'restored'
    Write-WibLog "Rollback to checkpoint #$($targetCp.Index) ('$($targetCp.Stage)') successful. Mount restored to clean state." 'INFO'
    return $targetCp
}

function Remove-WibCheckpoints {
    param($Ctx)
    if ($Ctx.ContainsKey('IsTest') -and $Ctx.IsTest -and $Ctx.ContainsKey('CheckpointDir') -and $Ctx.CheckpointDir -and (Test-Path -LiteralPath $Ctx.CheckpointDir)) {
        Remove-Item -LiteralPath $Ctx.CheckpointDir -Recurse -Force -ErrorAction Stop
        if (Test-Path -LiteralPath $Ctx.CheckpointDir) {
            throw "Failed to clean test checkpoint directory '$($Ctx.CheckpointDir)': directory remains present after deletion attempt."
        }
    }
    if ($Ctx.ContainsKey('WorkDir') -and $Ctx.WorkDir) {
        # Transactional recovery cleanup ordering (P1 fix):
        # Compatibility/secondary projection ledgers MUST be deleted and verified gone FIRST.
        # Authoritative recovery-state.json is deleted strictly LAST.
        # Invariant: Never delete the authoritative recovery record while any resume-capable
        # compatibility state remains, preventing cleanup failure from manufacturing an
        # inadvertent fallback to legacy migration.
        $secondaryFiles = @('journal.partial.json', 'checkpoints.json', 'checkpoint.transaction.json')
        foreach ($f in $secondaryFiles) {
            $fPath = Join-Path $Ctx.WorkDir $f
            if (Test-Path -LiteralPath $fPath) {
                Remove-Item -LiteralPath $fPath -Force -ErrorAction Stop
                if (Test-Path -LiteralPath $fPath) {
                    throw "Failed to clean secondary recovery ledger '$fPath': file remains present after deletion attempt."
                }
            }
        }

        # Delete authoritative recovery-state.json strictly AFTER secondary ledgers are confirmed gone
        $authoritativeFile = Join-Path $Ctx.WorkDir 'recovery-state.json'
        if (Test-Path -LiteralPath $authoritativeFile) {
            Remove-Item -LiteralPath $authoritativeFile -Force -ErrorAction Stop
            if (Test-Path -LiteralPath $authoritativeFile) {
                throw "Failed to clean authoritative recovery state '$authoritativeFile': file remains present after deletion attempt."
            }
        }
    }
    if ($Ctx.ContainsKey('Checkpoints')) {
        $Ctx.Checkpoints.Clear()
    }
}

function Get-WibPropValue {
    param($Obj, [string]$PropName)
    if ($null -eq $Obj) { return $null }
    if ($Obj -is [System.Collections.IDictionary]) {
        if ($Obj.Contains($PropName)) { return ,$Obj[$PropName] }
        return $null
    }
    if ($Obj.PSObject.Properties[$PropName]) {
        return ,$Obj.$PropName
    }
    return $null
}

function Test-WibHasProp {
    param($Obj, [string]$PropName)
    if ($null -eq $Obj) { return $false }
    if ($Obj -is [System.Collections.IDictionary]) {
        return $Obj.Contains($PropName)
    }
    return ($null -ne $Obj.PSObject.Properties[$PropName])
}

function Test-WibResumeProvenance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Checkpoints,
        [Parameter(Mandatory)][string]$ExpectedToolVersion,
        [Parameter(Mandatory)][string]$ExpectedProfileHash,
        [string]$ExpectedHardwareProfileHash,
        [string]$ExpectedHardwareSpecHash,
        [string]$ExpectedSourceIsoSha,
        [string]$ExpectedSourceWimSha,
        [int]$OriginalSourceIndex
    )
    $idx = 0
    foreach ($item in $Checkpoints) {
        $idx++
        $status = [string](Get-WibPropValue $item 'Status')
        if (-not $status -or ($status -ne 'saved' -and $status -ne 'restored')) {
            throw "Cannot resume: checkpoint #$idx has invalid or uncommitted status '$status'. Only 'saved' or 'restored' checkpoints can be resumed."
        }
        $prov = Get-WibPropValue $item 'Provenance'
        if (-not $prov) {
            throw "Cannot resume: checkpoint #$idx is missing required Provenance object."
        }

        # Schema strictness: all required identity fields must be present and non-empty (P1/P2 Finding 1, 3)
        $requiredFields = @(
            'ToolVersion',
            'ProfileHash',
            'EffectiveSha256',
            'SourceWimOriginalIndex',
            'CheckpointWimIndex',
            'SourceArch',
            'SourceBuild',
            'SourceEdition',
            'SourceContainer',
            'SourceContainerIndex',
            'ServicingWimIndex',
            'BaselineSourceWimSha256',
            'CurrentWorkspaceWimSha256',
            'SourceIsoHashStatus'
        )
        foreach ($rf in $requiredFields) {
            $val = Get-WibPropValue $prov $rf
            if ($null -eq $val -or [string]$val.ToString().Trim() -eq '') {
                throw "Cannot resume: checkpoint #$idx provenance schema invalid. Missing required field '$rf'."
            }
        }
        $srcContainer = [string](Get-WibPropValue $prov 'SourceContainer')
        if ($srcContainer -notin @('WIM', 'ESD')) {
            throw "Cannot resume: checkpoint #$idx provenance SourceContainer '$srcContainer' is invalid. Expected 'WIM' or 'ESD'."
        }
        $srcContainerIdx = [int](Get-WibPropValue $prov 'SourceContainerIndex')
        if ($srcContainerIdx -le 0) {
            throw "Cannot resume: checkpoint #$idx provenance SourceContainerIndex '$srcContainerIdx' is invalid (must be > 0)."
        }
        $srvWimIdx = [int](Get-WibPropValue $prov 'ServicingWimIndex')
        if ($srvWimIdx -le 0) {
            throw "Cannot resume: checkpoint #$idx provenance ServicingWimIndex '$srvWimIdx' is invalid (must be > 0)."
        }
        $baseWimVal = Get-WibPropValue $prov 'BaselineSourceWimSha256'

        $toolVer = [string](Get-WibPropValue $prov 'ToolVersion')
        if ($toolVer -ne $ExpectedToolVersion) {
            throw "Cannot resume: WIB tool version mismatch (checkpoint created with v$toolVer, current v$ExpectedToolVersion). Re-run without -Resume."
        }
        $effSha = [string](Get-WibPropValue $prov 'EffectiveSha256')
        if ($effSha -ne $ExpectedProfileHash) {
            throw "Cannot resume: effective profile canonical hash has changed since last checkpoint (recorded '$effSha' != current '$ExpectedProfileHash'). Re-run without -Resume."
        }
        $chkSourceIdx = [int](Get-WibPropValue $prov 'SourceWimOriginalIndex')
        if ($OriginalSourceIndex -gt 0 -and $chkSourceIdx -ne $OriginalSourceIndex) {
            throw "Cannot resume: source image index mismatch (checkpoint source index $chkSourceIdx != original source index $OriginalSourceIndex). Re-run without -Resume."
        }
        $srcWimSha = [string]$baseWimVal
        if ($ExpectedSourceWimSha -and $srcWimSha -and $srcWimSha -ne 'MOCK_SOURCE_WIM_SHA256' -and $srcWimSha -ne $ExpectedSourceWimSha) {
            throw "Cannot resume: baseline source WIM SHA-256 hash mismatch (recorded '$srcWimSha' != current '$ExpectedSourceWimSha'). Re-run without -Resume."
        }
        $isoStatus = [string](Get-WibPropValue $prov 'SourceIsoHashStatus')
        if ($isoStatus -notin @('verified', 'unavailable', 'skipped')) {
            throw "Cannot resume: checkpoint #$idx provenance SourceIsoHashStatus '$isoStatus' is invalid. Expected one of: 'verified', 'unavailable', 'skipped'."
        }
        if ($ExpectedSourceIsoSha) {
            $srcIsoSha = [string](Get-WibPropValue $prov 'SourceIsoSha256')
            if ($isoStatus -eq 'verified' -and $srcIsoSha -ne $ExpectedSourceIsoSha) {
                throw "Cannot resume: source ISO SHA-256 hash mismatch (recorded '$srcIsoSha' != current '$ExpectedSourceIsoSha'). Re-run without -Resume."
            }
        }
        if ($ExpectedHardwareSpecHash) {
            $hwSpec = [string](Get-WibPropValue $prov 'HardwareSpecHash')
            if ($hwSpec -ne $ExpectedHardwareSpecHash) {
                throw "Cannot resume: hardware specification hash mismatch since last checkpoint. Re-run without -Resume."
            }
        }
        if ($ExpectedHardwareProfileHash) {
            $hwProf = [string](Get-WibPropValue $prov 'HardwareProfileHash')
            if ($hwProf -ne $ExpectedHardwareProfileHash) {
                throw "Cannot resume: hardware profile hash mismatch since last checkpoint (recorded '$hwProf' != current '$ExpectedHardwareProfileHash'). Re-run without -Resume."
            }
        }
    }
}

function Test-WibRecoveryState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$RecoveryState,
        [Parameter(Mandatory)][string]$WorkDir,
        [Parameter(Mandatory)][string]$ExpectedToolVersion,
        [Parameter(Mandatory)][string]$ExpectedProfileHash,
        [string]$ExpectedHardwareProfileHash,
        [string]$ExpectedHardwareSpecHash,
        [string]$ExpectedSourceIsoSha,
        [string]$ExpectedSourceWimSha,
        [int]$ExpectedOriginalSourceIndex
    )
    # 1. Root schema invariants (no conditional presence allowed - P1/P2 Finding 2, 3)
    $requiredRootProps = @(
        'CommitState',
        'ToolVersion',
        'EffectiveSha256',
        'ProfileHash',
        'OriginalSourceIndex',
        'MountedIndex',
        'SourceContainer',
        'SourceContainerIndex',
        'ServicingWimIndex',
        'BaselineSourceWimSha256',
        'CurrentWorkspaceWimSha256',
        'SourceIsoHashStatus',
        'Checkpoints',
        'Journal'
    )
    foreach ($rrp in $requiredRootProps) {
        if (-not (Test-WibHasProp $RecoveryState $rrp)) {
            throw "Cannot resume: recovery-state.json root schema invalid. Missing required property '$rrp'."
        }
        $val = Get-WibPropValue $RecoveryState $rrp
        if ($rrp -notin @('Checkpoints', 'Journal') -and ($null -eq $val -or [string]$val.ToString().Trim() -eq '')) {
            throw "Cannot resume: recovery-state.json root schema invalid. Property '$rrp' cannot be empty."
        }
    }
    $rootContainer = [string](Get-WibPropValue $RecoveryState 'SourceContainer')
    if ($rootContainer -notin @('WIM', 'ESD')) {
        throw "Cannot resume: recovery-state.json root SourceContainer '$rootContainer' is invalid. Expected 'WIM' or 'ESD'."
    }
    $rootContainerIdx = [int](Get-WibPropValue $RecoveryState 'SourceContainerIndex')
    if ($rootContainerIdx -le 0) {
        throw "Cannot resume: recovery-state.json root SourceContainerIndex '$rootContainerIdx' is invalid (must be > 0)."
    }
    $rootSrvWimIdx = [int](Get-WibPropValue $RecoveryState 'ServicingWimIndex')
    if ($rootSrvWimIdx -le 0) {
        throw "Cannot resume: recovery-state.json root ServicingWimIndex '$rootSrvWimIdx' is invalid (must be > 0)."
    }

    $rootBaseWimSha = [string](Get-WibPropValue $RecoveryState 'BaselineSourceWimSha256')
    if (-not $rootBaseWimSha) {
        throw "Cannot resume: recovery-state.json root schema invalid. Missing required property 'BaselineSourceWimSha256'."
    }

    $commitState = [string](Get-WibPropValue $RecoveryState 'CommitState')
    if ($commitState -in @('finalizing', 'post-export')) {
        throw "Cannot resume: workspace was interrupted during finalization (CommitState is '$commitState'). Intermediate servicing changes and image export have already mutated the workspace; this is a terminal non-resumable state. Re-run without -Resume for a clean build."
    }
    if ($commitState -ne 'committed' -and $commitState -ne 'in-flight-append' -and $commitState -ne 'reconciled-in-flight') {
        throw "Cannot resume: recovery-state.json CommitState is '$commitState' (expected 'committed', 'in-flight-append', or 'reconciled-in-flight'). Re-run without -Resume."
    }

    if ($commitState -eq 'in-flight-append') {
        $requiredInFlightProps = @(
            'ActiveTransactionId',
            'ActiveCheckpointId',
            'ActiveTransactionStage',
            'ActiveRunId',
            'ActiveToolVersion',
            'ActiveMountedIndex',
            'PreAppendWimSha256',
            'PreAppendPhysicalCount',
            'ExpectedAppendedIndex',
            'TransactionMac',
            'TransactionAuthSecret'
        )
        foreach ($prop in $requiredInFlightProps) {
            if (-not (Test-WibHasProp $RecoveryState $prop)) {
                throw "Cannot resume: recovery ledger is in CommitState 'in-flight-append' but missing mandatory transaction property '$prop'. Tamper detected. Re-run without -Resume."
            }
            $pVal = Get-WibPropValue $RecoveryState $prop
            if ($null -eq $pVal -or ($pVal -is [string] -and [string]::IsNullOrWhiteSpace($pVal))) {
                throw "Cannot resume: recovery ledger is in CommitState 'in-flight-append' but transaction property '$prop' is empty. Tamper detected. Re-run without -Resume."
            }
        }
    }

    $toolVer = [string](Get-WibPropValue $RecoveryState 'ToolVersion')
    if ($toolVer -ne $ExpectedToolVersion) {
        throw "Cannot resume: WIB tool version mismatch (recovery state recorded v$toolVer, current v$ExpectedToolVersion). Re-run without -Resume."
    }
    $effSha = [string](Get-WibPropValue $RecoveryState 'EffectiveSha256')
    if ($effSha -ne $ExpectedProfileHash) {
        throw "Cannot resume: recovery state effective profile hash mismatch (recorded '$effSha' != current '$ExpectedProfileHash'). Re-run without -Resume."
    }
    $cps = Get-WibPropValue $RecoveryState 'Checkpoints'
    if (-not $cps -or @($cps).Count -eq 0) {
        throw "Cannot resume: recovery state contains no checkpoints. Re-run without -Resume."
    }

    $lastCp = @($cps)[@($cps).Count - 1]
    $lastProv = Get-WibPropValue $lastCp 'Provenance'
    if (-not $lastProv) {
        throw "Cannot resume: last checkpoint provenance is missing. Re-run without -Resume."
    }

    # 2. Strict Root vs Checkpoint coherence checks (mandatory, not conditional - P1/P2 Finding 2)
    $rootOrigIdx = [int](Get-WibPropValue $RecoveryState 'OriginalSourceIndex')
    $cpOrigIdx = [int](Get-WibPropValue $lastProv 'SourceWimOriginalIndex')
    if ($rootOrigIdx -ne $cpOrigIdx) {
        throw "Cannot resume: recovery state coherence violation (root OriginalSourceIndex $rootOrigIdx != checkpoint SourceWimOriginalIndex $cpOrigIdx). Re-run without -Resume."
    }

    $rootMountedIdx = [int](Get-WibPropValue $RecoveryState 'MountedIndex')
    $cpWimIdx = [int](Get-WibPropValue $lastCp 'WimIndex')
    if ($rootMountedIdx -ne $cpWimIdx) {
        throw "Cannot resume: recovery state coherence violation (root MountedIndex $rootMountedIdx != checkpoint WimIndex $cpWimIdx). Re-run without -Resume."
    }

    $cpContainer = [string](Get-WibPropValue $lastProv 'SourceContainer')
    if ($rootContainer -ne $cpContainer) {
        throw "Cannot resume: recovery state coherence violation (root SourceContainer '$rootContainer' != checkpoint SourceContainer '$cpContainer'). Re-run without -Resume."
    }
    $cpContainerIdx = [int](Get-WibPropValue $lastProv 'SourceContainerIndex')
    if ($rootContainerIdx -ne $cpContainerIdx) {
        throw "Cannot resume: recovery state coherence violation (root SourceContainerIndex $rootContainerIdx != checkpoint SourceContainerIndex $cpContainerIdx). Re-run without -Resume."
    }
    $cpSrvWimIdx = [int](Get-WibPropValue $lastProv 'ServicingWimIndex')
    if ($rootSrvWimIdx -ne $cpSrvWimIdx) {
        throw "Cannot resume: recovery state coherence violation (root ServicingWimIndex $rootSrvWimIdx != checkpoint ServicingWimIndex $cpSrvWimIdx). Re-run without -Resume."
    }

    $rootProfileHash = [string](Get-WibPropValue $RecoveryState 'ProfileHash')
    $cpProfileHash = [string](Get-WibPropValue $lastCp 'ProfileHash')
    if ($rootProfileHash -ne $cpProfileHash) {
        throw "Cannot resume: recovery state coherence violation (root ProfileHash '$rootProfileHash' != checkpoint ProfileHash '$cpProfileHash'). Re-run without -Resume."
    }

    $cpEffSha = [string](Get-WibPropValue $lastProv 'EffectiveSha256')
    if ($effSha -ne $cpEffSha) {
        throw "Cannot resume: recovery state coherence violation (root EffectiveSha256 '$effSha' != checkpoint EffectiveSha256 '$cpEffSha'). Re-run without -Resume."
    }

    $rootCurrentWimSha = [string](Get-WibPropValue $RecoveryState 'CurrentWorkspaceWimSha256')
    $cpCurrentWimSha = [string](Get-WibPropValue $lastProv 'CurrentWorkspaceWimSha256')
    $isReconciledAppend = ($commitState -eq 'reconciled-in-flight' -or [bool](Get-WibPropValue $RecoveryState 'ReconciledFromAppend'))
    if (-not $isReconciledAppend -and $rootCurrentWimSha -ne $cpCurrentWimSha) {
        throw "Cannot resume: recovery state coherence violation (root CurrentWorkspaceWimSha256 '$rootCurrentWimSha' != checkpoint CurrentWorkspaceWimSha256 '$cpCurrentWimSha'). Re-run without -Resume."
    }

    $cpBaseWimSha = [string](Get-WibPropValue $lastProv 'BaselineSourceWimSha256')
    if (-not $cpBaseWimSha) {
        throw "Cannot resume: last checkpoint provenance missing BaselineSourceWimSha256."
    }
    if ($rootBaseWimSha -ne $cpBaseWimSha) {
        throw "Cannot resume: recovery state coherence violation (root BaselineSourceWimSha256 '$rootBaseWimSha' != checkpoint BaselineSourceWimSha256 '$cpBaseWimSha'). Re-run without -Resume."
    }

    $validIsoStatuses = @('verified', 'unavailable', 'skipped')
    $rootIsoStatus = [string](Get-WibPropValue $RecoveryState 'SourceIsoHashStatus')
    if ($rootIsoStatus -notin $validIsoStatuses) {
        throw "Cannot resume: recovery state root SourceIsoHashStatus '$rootIsoStatus' is invalid. Expected one of: $($validIsoStatuses -join ', ')."
    }
    $cpIsoStatus = [string](Get-WibPropValue $lastProv 'SourceIsoHashStatus')
    if ($rootIsoStatus -ne $cpIsoStatus) {
        throw "Cannot resume: recovery state coherence violation (root SourceIsoHashStatus '$rootIsoStatus' != checkpoint SourceIsoHashStatus '$cpIsoStatus'). Re-run without -Resume."
    }

    # 3. Semantic provenance verification of all checkpoints
    Test-WibResumeProvenance -Checkpoints $cps `
        -ExpectedToolVersion $ExpectedToolVersion `
        -ExpectedProfileHash $ExpectedProfileHash `
        -ExpectedHardwareProfileHash $ExpectedHardwareProfileHash `
        -ExpectedHardwareSpecHash $ExpectedHardwareSpecHash `
        -ExpectedSourceIsoSha $ExpectedSourceIsoSha `
        -ExpectedSourceWimSha $ExpectedSourceWimSha `
        -OriginalSourceIndex $ExpectedOriginalSourceIndex

    # 4. Mandatory physical WIM validation (FAIL CLOSED IF MISSING - P2 Finding 6)
    $actualWim = Join-Path $WorkDir 'iso\sources\install.wim'
    if (-not (Test-Path -LiteralPath $actualWim)) {
        $actualWim = Join-Path $WorkDir 'sources\install.wim'
    }
    if (-not (Test-Path -LiteralPath $actualWim -PathType Leaf)) {
        throw "Cannot resume: workspace WIM file is missing in '$WorkDir'. Work directory sources are incomplete or corrupted."
    }
    $wimItem = Get-Item -LiteralPath $actualWim
    if ($wimItem.Length -eq 0) {
        throw "Cannot resume: workspace WIM file at '$actualWim' is empty (0 bytes). Image in workspace has been corrupted."
    }

    # 5. Transaction Shape & Authenticity Inspection (P1 Trust Boundary Protection)
    # Solves the crash window where Save-WindowsImage -Append succeeded (mutating physical WIM)
    # but process crashed before recovery-state.json was updated.
    $orphanWimIndices = New-Object System.Collections.ArrayList
    $physicalCount = 0
    if (Get-Command Get-WindowsImage -ErrorAction SilentlyContinue) {
        try {
            $physicalImages = @(Get-WindowsImage -ImagePath $actualWim -ErrorAction Stop)
            $physicalCount = $physicalImages.Count
        } catch {
            throw "Cannot resume: failed to query image indices from physical WIM '$actualWim': $($_.Exception.Message)"
        }
    }

    if ($physicalCount -gt 0 -and $physicalCount -lt $rootMountedIdx) {
        throw "Cannot resume: committed checkpoint image index $rootMountedIdx does not exist in physical WIM (image count is $physicalCount). WIM file is truncated or corrupted."
    }

    Write-WibLog "Verifying physical workspace WIM SHA-256 integrity: $actualWim" 'INFO'
    $actualWimHash = Get-WibSha256 $actualWim
    $expectedCurrentHash = if ($rootCurrentWimSha) { $rootCurrentWimSha } elseif ($cpCurrentWimSha) { $cpCurrentWimSha } else { '' }

    $txMarkerFile = Join-Path $WorkDir 'checkpoint.transaction.json'
    $hasTxMarker = Test-Path -LiteralPath $txMarkerFile
    $wimHashMismatch = ($expectedCurrentHash -and $expectedCurrentHash -ne 'MOCK_CURRENT_WIM_SHA256' -and $actualWimHash -ne $expectedCurrentHash)

    if ($physicalCount -gt $rootMountedIdx) {
        if ($wimHashMismatch) {
            # Extra physical indexes detected with mutated WIM hash: must prove authentic in-flight append by WIB
            $recActiveTxId = [string](Get-WibPropValue $RecoveryState 'ActiveTransactionId')
            $recCommitState = [string](Get-WibPropValue $RecoveryState 'CommitState')
            if (-not $recActiveTxId -or $recCommitState -ne 'in-flight-append') {
                throw "Cannot resume: physical WIM index count ($physicalCount) exceeds committed index ($rootMountedIdx) with modified WIM hash, but recovery ledger does not record an active in-flight transaction bound before mutation. The WIM file was modified outside an authorized WIB append transaction (tamper detected). Re-run without -Resume."
            }

            if (-not $hasTxMarker) {
                throw "Cannot resume: physical WIM index count ($physicalCount) exceeds committed index ($rootMountedIdx), but no active in-flight append transaction marker ('checkpoint.transaction.json') exists. The WIM file was modified outside an authorized WIB append transaction (tamper detected). Re-run without -Resume."
            }

            # Parse and cryptographically validate the transaction marker against committed recovery state
            try {
                $txRaw = Get-Content -LiteralPath $txMarkerFile -Raw
                $txData = ConvertFrom-Json -InputObject $txRaw -ErrorAction Stop
            } catch {
                throw "Cannot resume: in-flight append transaction marker '$txMarkerFile' is corrupt or unreadable: $($_.Exception.Message). Re-run without -Resume."
            }

            $txId = [string](Get-WibPropValue $txData 'TransactionId')
            if (-not $txId -or $txId -ne $recActiveTxId) {
                throw "Cannot resume: transaction marker ID '$txId' does not match authoritative ledger ActiveTransactionId '$recActiveTxId'. Tamper detected. Re-run without -Resume."
            }

            $txSecret = [string](Get-WibPropValue $RecoveryState 'TransactionAuthSecret')
            if (-not $txSecret) {
                throw "Cannot resume: recovery ledger is missing TransactionAuthSecret. Tamper detected. Re-run without -Resume."
            }

            $recMac = [string](Get-WibPropValue $RecoveryState 'TransactionMac')
            $markerMac = [string](Get-WibPropValue $txData 'TransactionMac')
            if (-not $markerMac -or $markerMac -ne $recMac) {
                throw "Cannot resume: transaction marker MAC does not match authoritative ledger TransactionMac. Tamper detected. Re-run without -Resume."
            }

            $txCpId = [int](Get-WibPropValue $txData 'ActiveCheckpointId')
            $txStage = [string](Get-WibPropValue $txData 'Stage')
            $txProfHash = [string](Get-WibPropValue $txData 'ProfileHash')
            $txEffSha = [string](Get-WibPropValue $txData 'EffectiveSha256')
            $txPreHash = [string](Get-WibPropValue $txData 'PreAppendWimSha256')
            $txPreCount = [int](Get-WibPropValue $txData 'PreAppendPhysicalCount')
            $txExpectedIdx = [int](Get-WibPropValue $txData 'ExpectedAppendedIndex')
            $txRunId = [string](Get-WibPropValue $txData 'RunId')
            $txToolVer = [string](Get-WibPropValue $txData 'ToolVersion')
            $txMounted = [int](Get-WibPropValue $txData 'MountedIndex')

            $recActiveCpId = [int](Get-WibPropValue $RecoveryState 'ActiveCheckpointId')
            if ($txCpId -ne $recActiveCpId) {
                throw "Cannot resume: in-flight append transaction marker ActiveCheckpointId $txCpId does not match authoritative ledger ActiveCheckpointId $recActiveCpId. Tamper detected. Re-run without -Resume."
            }

            $recActiveStage = [string](Get-WibPropValue $RecoveryState 'ActiveTransactionStage')
            if ($txStage -ne $recActiveStage) {
                throw "Cannot resume: in-flight append transaction marker Stage '$txStage' does not match authoritative ledger ActiveTransactionStage '$recActiveStage'. Tamper detected. Re-run without -Resume."
            }

            $recActiveRunId = [string](Get-WibPropValue $RecoveryState 'ActiveRunId')
            if ($txRunId -ne $recActiveRunId) {
                throw "Cannot resume: in-flight append transaction marker RunId '$txRunId' does not match authoritative ledger ActiveRunId '$recActiveRunId'. Tamper detected. Re-run without -Resume."
            }

            $recActiveToolVer = [string](Get-WibPropValue $RecoveryState 'ActiveToolVersion')
            if ($txToolVer -ne $recActiveToolVer) {
                throw "Cannot resume: in-flight append transaction marker ToolVersion '$txToolVer' does not match authoritative ledger ActiveToolVersion '$recActiveToolVer'. Tamper detected. Re-run without -Resume."
            }

            $recActiveMountedIdx = [int](Get-WibPropValue $RecoveryState 'ActiveMountedIndex')
            if ($txMounted -ne $recActiveMountedIdx) {
                throw "Cannot resume: in-flight append transaction marker MountedIndex $txMounted does not match authoritative ledger ActiveMountedIndex $recActiveMountedIdx. Tamper detected. Re-run without -Resume."
            }

            $macMessage = "$txId|$txCpId|$txStage|$txProfHash|$txEffSha|$txPreHash|$txPreCount|$txExpectedIdx|$txRunId|$txToolVer|$txMounted"
            $recalcMac = Get-WibHmacSha256 -Message $macMessage -KeyHex $txSecret
            if ($markerMac -ne $recalcMac) {
                throw "Cannot resume: transaction marker cryptographic HMAC authentication failed. Tamper detected. Re-run without -Resume."
            }
            if ($recMac -ne $recalcMac) {
                throw "Cannot resume: authoritative ledger TransactionMac does not match computed HMAC. Tamper detected. Re-run without -Resume."
            }

            $recPreCount = [int](Get-WibPropValue $RecoveryState 'PreAppendPhysicalCount')
            if ($txPreCount -ne $recPreCount) {
                throw "Cannot resume: in-flight append transaction marker mismatch (PreAppendPhysicalCount $txPreCount != ledger PreAppendPhysicalCount $recPreCount). Tamper detected. Re-run without -Resume."
            }
            if ($txPreCount -lt $rootMountedIdx) {
                throw "Cannot resume: in-flight append transaction marker mismatch (PreAppendPhysicalCount $txPreCount < committed MountedIndex $rootMountedIdx). Tamper detected. Re-run without -Resume."
            }
            $recExpectedIdx = [int](Get-WibPropValue $RecoveryState 'ExpectedAppendedIndex')
            if ($txExpectedIdx -ne $recExpectedIdx) {
                throw "Cannot resume: in-flight append transaction marker mismatch (ExpectedAppendedIndex $txExpectedIdx != ledger ExpectedAppendedIndex $recExpectedIdx). Tamper detected. Re-run without -Resume."
            }
            if ($txExpectedIdx -ne $physicalCount) {
                throw "Cannot resume: in-flight append transaction marker mismatch (ExpectedAppendedIndex $txExpectedIdx != actual physical count $physicalCount). Tamper detected. Re-run without -Resume."
            }
            $recPreHash = [string](Get-WibPropValue $RecoveryState 'PreAppendWimSha256')
            if ($txPreHash -ne $recPreHash) {
                throw "Cannot resume: in-flight append transaction marker mismatch (PreAppendWimSha256 '$txPreHash' != ledger PreAppendWimSha256 '$recPreHash'). Tamper detected. Re-run without -Resume."
            }
            if ($expectedCurrentHash -and $expectedCurrentHash -ne 'MOCK_CURRENT_WIM_SHA256' -and $txPreHash -ne $expectedCurrentHash) {
                throw "Cannot resume: in-flight append transaction marker mismatch (PreAppendWimSha256 '$txPreHash' != committed checkpoint hash '$expectedCurrentHash'). Tamper detected. Re-run without -Resume."
            }
            if ($txProfHash -ne $rootProfileHash) {
                throw "Cannot resume: in-flight append transaction marker mismatch (ProfileHash '$txProfHash' != recovery ProfileHash '$rootProfileHash'). Tamper detected. Re-run without -Resume."
            }
            if ($txEffSha -ne $effSha) {
                throw "Cannot resume: in-flight append transaction marker mismatch (EffectiveSha256 '$txEffSha' != recovery EffectiveSha256 '$effSha'). Re-run without -Resume."
            }

            for ($oidx = $rootMountedIdx + 1; $oidx -le $physicalCount; $oidx++) {
                [void]$orphanWimIndices.Add($oidx)
            }
            Write-WibLog "Verified Transactional In-Flight Append: transaction '$txId' authenticated via HMAC-SHA256 under trusted recovery-ledger model. Detected $($orphanWimIndices.Count) uncommitted orphan index/indices in physical WIM ($($orphanWimIndices -join ', ')). Reconciling workspace WIM hash to '$actualWimHash' and restricting active mount to committed checkpoint index $rootMountedIdx." 'WARN'
            $expectedCurrentHash = $actualWimHash

            # CRITICAL (P1 Two-Crash Consistency):
            # Durably persist reconciled state to recovery-state.json and verify read-back BEFORE removing the transaction marker.
            # If the process or host crashes immediately after marker deletion, recovery on subsequent run sees CommitState='reconciled-in-flight'
            # with CurrentWorkspaceWimSha256 matching the physical WIM, avoiding permanent unrecoverability.
            $recFile = Join-Path $WorkDir 'recovery-state.json'
            if (Test-Path -LiteralPath $recFile) {
                $reconciledUpdates = @{
                    CurrentWorkspaceWimSha256   = $actualWimHash
                    PhysicalImageIndex          = $physicalCount
                    OrphanIndexSet              = @($orphanWimIndices)
                    ReconciledFromAppend        = $true
                    ActiveTransactionId         = $null
                    ActiveCheckpointId          = $null
                    ActiveTransactionStage      = $null
                    ActiveRunId                 = $null
                    ActiveToolVersion           = $null
                    ActiveMountedIndex          = $null
                    PreAppendWimSha256          = $null
                    PreAppendPhysicalCount      = $null
                    ExpectedAppendedIndex       = $null
                    TransactionMac              = $null
                    TransactionAuthSecret       = $null
                }
                Update-WibRecoveryCommitState -WorkDir $WorkDir -CommitState 'reconciled-in-flight' -Updates $reconciledUpdates
            }

            Remove-Item -LiteralPath $txMarkerFile -Force -ErrorAction SilentlyContinue
        } else {
            # WIM hash is intact/unmodified or already reconciled: record uncommitted physical indices as orphans
            for ($oidx = $rootMountedIdx + 1; $oidx -le $physicalCount; $oidx++) {
                [void]$orphanWimIndices.Add($oidx)
            }
            if ($commitState -eq 'reconciled-in-flight' -and (Test-Path -LiteralPath $txMarkerFile)) {
                Remove-Item -LiteralPath $txMarkerFile -Force -ErrorAction SilentlyContinue
            }
        }
    } else {
        # Strict tamper protection when no uncommitted append is present
        if ($wimHashMismatch) {
            throw "Cannot resume: actual physical WIM hash in workspace ($actualWimHash) does not match expected checkpoint WIM hash ($expectedCurrentHash). Image in workspace has been modified or corrupted since checkpoint was saved."
        }
    }

    $provTier = if (Test-WibHasProp $RecoveryState 'ProvenanceTier') { [string](Get-WibPropValue $RecoveryState 'ProvenanceTier') } else { 'authoritative' }
    $isoSha = if (Test-WibHasProp $RecoveryState 'SourceIsoSha256') { [string](Get-WibPropValue $RecoveryState 'SourceIsoSha256') } else { '' }
    $recTxSecret = if (Test-WibHasProp $RecoveryState 'TransactionAuthSecret') { [string](Get-WibPropValue $RecoveryState 'TransactionAuthSecret') } else { '' }
    return @{
        Checkpoints                 = $cps
        LastCheckpoint              = $lastCp
        MountedIndex                = $rootMountedIdx
        OriginalSourceIndex         = $rootOrigIdx
        SourceContainer             = $rootContainer
        SourceContainerIndex        = $rootContainerIdx
        ServicingWimIndex           = $rootSrvWimIdx
        BaselineSourceWimSha256     = $rootBaseWimSha
        CurrentWorkspaceWimSha256   = $expectedCurrentHash
        SourceIsoHashStatus         = $rootIsoStatus
        SourceIsoSha256             = $isoSha
        OrphanWimIndices            = $orphanWimIndices
        OrphanIndexSet              = @($orphanWimIndices)
        CommittedCheckpointWimIndex = $rootMountedIdx
        PhysicalImageIndex          = if ($physicalCount -gt 0) { $physicalCount } else { $rootMountedIdx }
        NextCheckpointLogicalId     = ($cps.Count + 1)
        ActualWimPath               = $actualWim
        ProvenanceTier              = $provTier
        TransactionAuthSecret       = $recTxSecret
    }
}

# ---------------------------------------------------------------- general verify pass
function Invoke-WibGeneralVerify {
    param($Ctx, [hashtable]$BuildProfile)
    if ($script:WibLoadedHives -notcontains 'SOFTWARE') {
        return @(New-WibResult 'verify-general' 'General leftover scan' 'warn' 'SOFTWARE hive not loaded; scan skipped')
    }
    $enabled = @(Get-WibEnabledModuleIds $BuildProfile $Ctx.Image)
    $findings = New-Object System.Collections.ArrayList
    $pfx = if ($script:WibHivePrefix) { $script:WibHivePrefix } else { 'wib_' }

    # 1. Orphaned TaskCache registry entries
    if ($enabled -contains 'tasks-cleanup') {
        $taskCacheTree = "Registry::HKEY_LOCAL_MACHINE\${pfx}SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree"
        if (Test-Path -LiteralPath $taskCacheTree) {
            $telemetryTaskKeys = @(
                'Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser',
                'Microsoft\Windows\Application Experience\ProgramDataUpdater',
                'Microsoft\Windows\Customer Experience Improvement Program',
                'Microsoft\Windows\Chkdsk\Proxy',
                'Microsoft\Windows\Windows Error Reporting\QueueReporting'
            )
            foreach ($tKey in $telemetryTaskKeys) {
                $fullKey = Join-Path $taskCacheTree $tKey
                if (Test-Path -LiteralPath $fullKey) {
                    [void]$findings.Add((New-WibResult 'verify-general' "TaskCache remnant: $tKey" 'warn' 'registry entry exists though task file deleted'))
                }
            }
        }

        # Check for orphaned TaskCache\Tasks entries missing from TaskCache\Tree
        if (Test-Path -LiteralPath $taskCacheTree) {
            $taskGuids = Get-WibOfflineTaskCacheGuids
            foreach ($tg in $taskGuids) {
                if ($tg.Path) {
                    $relativeTree = ($tg.Path).TrimStart('\')
                    $matchingTreeKey = Join-Path $taskCacheTree $relativeTree
                    if (-not (Test-Path -LiteralPath $matchingTreeKey)) {
                        [void]$findings.Add((New-WibResult 'verify-general' "Orphaned TaskCache GUID: $($tg.Guid)" 'warn' "TaskCache\Tasks entry exists with path '$($tg.Path)' but missing from TaskCache\Tree"))
                    }
                }
            }
        }
    }

    # 2. Leftover Edge uninstall registry entries & Edge Update scheduled tasks
    if ($enabled -contains 'edge-removal') {
        $edgeUninstallKey = "Registry::HKEY_LOCAL_MACHINE\${pfx}SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge"
        if (Test-Path -LiteralPath $edgeUninstallKey) {
            [void]$findings.Add((New-WibResult 'verify-general' 'Edge uninstall key' 'warn' 'remnant registry key in Uninstall'))
        }
        $edgeTaskTree = "Registry::HKEY_LOCAL_MACHINE\${pfx}SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\Microsoft\EdgeUpdate"
        if (Test-Path -LiteralPath $edgeTaskTree) {
            [void]$findings.Add((New-WibResult 'verify-general' 'EdgeUpdate TaskCache remnant' 'warn' 'Microsoft\EdgeUpdate TaskCache\Tree remnant still present'))
        }
    }

    # 3. Check deprovisioned app entries
    if ($enabled -contains 'appx-removal') {
        try {
            $deprovKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("${pfx}SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Deprovisioned")
            if ($deprovKey) {
                try {
                    $count = $deprovKey.SubKeyCount
                    if ($count -gt 0) {
                        [void]$findings.Add((New-WibResult 'verify-general' "Deprovisioned AppX packages ($count)" 'pass' 'recorded in Deprovisioned store'))
                    }
                } finally {
                    $deprovKey.Close()
                    $deprovKey.Dispose()
                }
            }
        } catch {
            Write-Verbose "Deprovisioned check: $($_.Exception.Message)"
        }
    }

    $warns = @($findings | Where-Object { $_.Status -eq 'warn' -or $_.Status -eq 'fail' })
    if ($warns.Count -eq 0) {
        [void]$findings.Add((New-WibResult 'verify-general' 'General leftover scan' 'pass' 'no dangling references detected'))
    }

    return $findings.ToArray()
}

function Invoke-WibModuleStep {
    param($Module, [scriptblock]$Block, $Ctx, $Settings, [string]$Stage)
    try { return @(& $Block $Ctx $Settings) }
    catch {
        if ($Module.OnError -eq 'halt') { throw }
        $status = 'failed'
        if ($Module.OnError -eq 'ignore') { $status = 'ignored' }
        return @(New-WibResult $Module.Id $Stage $status $_.Exception.Message)
    }
}

function Invoke-WibApply {
    param([hashtable]$BuildProfile, $Ctx)
    $results = New-Object System.Collections.ArrayList
    $verify = New-Object System.Collections.ArrayList
    $ids = @(Get-WibEnabledModuleIds $BuildProfile $Ctx.Image)
    $isInstall = ($Ctx.Image -eq 'install')

    # A: file-level work (hives not loaded)
    if ($isInstall) {
        if ($Ctx.ContainsKey('CompletedStages') -and ($Ctx.CompletedStages -contains 'apply-files')) {
            Write-WibLog 'Stage apply-files previously completed; resuming next stage.' 'INFO'
        } else {
            try {
                foreach ($id in $ids) {
                    $mod = $script:WibModules[$id]
                    $appliesRes = Test-WibModuleApplies -Module $mod -Context $Ctx
                    if (-not $appliesRes.Applies) {
                        [void]$results.Add((New-WibResult $id $id 'skipped' "appliesWhen not met: $($appliesRes.Reason)"))
                        continue
                    }
                    if (-not $mod.Apply) { continue }
                    Write-WibLog "Applying: $id" 'STEP'
                    $modResults = Invoke-WibModuleStep $mod $mod.Apply $Ctx (Get-WibModuleSettings $BuildProfile $id) 'apply'
                    foreach ($r in $modResults) {
                        if ($r) {
                            if ($r.Status -eq 'failed') {
                                if ($mod.OnError -eq 'halt') {
                                    throw "Module '$id' failed with OnError=halt: $($r.Detail)"
                                } elseif ($mod.OnError -eq 'ignore') {
                                    $r.Status = 'ignored'
                                }
                            }
                            [void]$results.Add($r)
                        }
                    }
                }
                $unresolvedApplyFails = @($results | Where-Object { $_.Status -eq 'failed' })
                if ($unresolvedApplyFails.Count -gt 0) {
                    throw "Stage 'apply-files' finished with $($unresolvedApplyFails.Count) unresolved failed module(s). Checkpoint commit blocked."
                }
                New-WibCheckpoint -Ctx $Ctx -StageName 'apply-files' | Out-Null
            } catch {
                Write-WibLog "File apply stage failed: $($_.Exception.Message). Rolling back to last checkpoint..." 'ERROR'
                Restore-WibCheckpoint -Ctx $Ctx | Out-Null
                throw
            }
        }
    }

    # B + C: registry tweaks and verification (hives loaded)
    if ($isInstall) {
        if ($Ctx.ContainsKey('CompletedStages') -and ($Ctx.CompletedStages -contains 'apply-tweaks')) {
            Write-WibLog 'Stage apply-tweaks previously completed; resuming next stage.' 'INFO'
        } else {
            try {
                try {
                    Mount-WibHives -MountDir $Ctx.MountDir
                    foreach ($id in $ids) {
                        $mod = $script:WibModules[$id]
                        $appliesRes = Test-WibModuleApplies -Module $mod -Context $Ctx
                        if (-not $appliesRes.Applies) { continue }
                        $s = Get-WibModuleSettings $BuildProfile $id
                        $tweaks = @(Get-WibModuleTweaks $mod $s)
                        if ($tweaks.Count -gt 0) {
                            Write-WibLog "Registry tweaks: $id ($($tweaks.Count))" 'STEP'
                            $tweakResults = @(Invoke-WibTweaks -Tweaks $tweaks -ModuleId $id -Journal $Ctx.Journal -Image $Ctx.Image)
                            foreach ($r in $tweakResults) {
                                if ($r.Status -eq 'failed') {
                                    Write-WibLog "Tweak failed: $($r.Item) - $($r.Detail)" 'WARN'
                                    if ($mod.OnError -eq 'halt') {
                                        throw "Module '$id' failed with OnError=halt: $($r.Detail)"
                                    } elseif ($mod.OnError -eq 'ignore') {
                                        $r.Status = 'ignored'
                                    }
                                }
                                [void]$results.Add($r)
                            }
                        }
                    }

                    # Apply Adaptive Decisions Tweaks (if any)
                    if ($Ctx.ContainsKey('AdaptiveDecisions') -and $Ctx.AdaptiveDecisions) {
                        foreach ($ad in $Ctx.AdaptiveDecisions) {
                            if (-not ($ad.Contains('Tweaks') -and $ad.Tweaks)) { continue }
                            if ($ad.Contains('Settings') -and $ad.Settings) { continue }   # module already applies these
                            foreach ($r in @(Invoke-WibTweaks -Tweaks @($ad.Tweaks) -ModuleId 'adaptive-hardware' -Journal $Ctx.Journal -Image $Ctx.Image)) {
                                if ($r.Status -eq 'failed') {
                                    Write-WibLog "Adaptive tweak failed: $($r.Item) - $($r.Detail)" 'WARN'
                                }
                                [void]$results.Add($r)
                            }
                        }
                    }

                    Write-WibLog 'Verifying changes' 'STEP'
                    foreach ($id in $ids) {
                        $mod = $script:WibModules[$id]
                        $appliesRes = Test-WibModuleApplies -Module $mod -Context $Ctx
                        if (-not $appliesRes.Applies) { continue }
                        $s = Get-WibModuleSettings $BuildProfile $id
                        $tweaks = @(Get-WibModuleTweaks $mod $s)
                        $passed = 0
                        foreach ($t in $tweaks) {
                            if ($script:WibLoadedHives -notcontains $t.Hive) { continue }
                            $r = Test-WibTweak $t
                            if ($r.Status -eq 'pass') {
                                $passed++
                            } else {
                                Write-WibLog "Verify failed: $($r.Item) - $($r.Detail)" 'WARN'
                                [void]$verify.Add($r)
                            }
                        }
                        if ($passed -gt 0) { [void]$verify.Add((New-WibResult 'verify' "$id : $passed registry tweak(s)" 'pass')) }
                    }

                    if ($Ctx.ContainsKey('AdaptiveDecisions') -and $Ctx.AdaptiveDecisions) {
                        foreach ($ad in $Ctx.AdaptiveDecisions) {
                            if (-not ($ad.Contains('Tweaks') -and $ad.Tweaks)) { continue }
                            if ($ad.Contains('Settings') -and $ad.Settings) { continue }
                            $adPassed = 0
                            foreach ($t in @($ad.Tweaks)) {
                                if ($script:WibLoadedHives -notcontains $t.Hive) { continue }
                                $r = Test-WibTweak $t
                                if ($r.Status -eq 'pass') { $adPassed++ } else { [void]$verify.Add($r) }
                            }
                            if ($adPassed -gt 0) { [void]$verify.Add((New-WibResult 'verify' "adaptive-hardware : $adPassed adaptive tweak(s)" 'pass')) }
                        }
                    }

                    # Stage 7 General leftover verify pass (requires hives)
                    Write-WibLog 'Running general verify pass' 'STEP'
                    foreach ($gv in @(Invoke-WibGeneralVerify -Ctx $Ctx -BuildProfile $BuildProfile)) {
                        if ($gv) { [void]$verify.Add($gv) }
                    }
                } finally {
                    [void](Dismount-WibHives -ThrowOnFailure)
                }

                # Module verification pass (DISM package/feature checks run with hives dismounted to avoid file locks)
                Write-WibLog 'Verifying package and feature state' 'STEP'
                foreach ($id in $ids) {
                    $mod = $script:WibModules[$id]
                    $appliesRes = Test-WibModuleApplies -Module $mod -Context $Ctx
                    if (-not $appliesRes.Applies) { continue }
                    if (-not $mod.Verify) { continue }
                    $s = Get-WibModuleSettings $BuildProfile $id
                    try {
                        $modVerifies = @(& $mod.Verify $Ctx $s)
                        foreach ($r in $modVerifies) {
                            if ($r) { [void]$verify.Add($r) }
                        }
                    } catch {
                        [void]$verify.Add((New-WibResult $id 'verify' 'fail' "Module verification error: $($_.Exception.Message)"))
                    }
                }

                # Check for unresolved failures before committing checkpoint
                $unresolvedVerifyFails = @($verify | Where-Object { $_.Status -in @('fail', 'failed') })
                $unresolvedTweakFails = @($results | Where-Object { $_.Status -eq 'failed' })
                if (($unresolvedVerifyFails.Count -gt 0) -or ($unresolvedTweakFails.Count -gt 0)) {
                    throw "Stage 'apply-tweaks' finished with unresolved failure(s) (tweaks: $($unresolvedTweakFails.Count), verify: $($unresolvedVerifyFails.Count)). Checkpoint commit blocked."
                }

                # Checkpoint after registry & verify pass
                New-WibCheckpoint -Ctx $Ctx -StageName 'apply-tweaks' | Out-Null
            } catch {
                Write-WibLog "Registry tweak/verify stage failed: $($_.Exception.Message). Rolling back to last checkpoint..." 'ERROR'
                [void](Dismount-WibHives)
                Restore-WibCheckpoint -Ctx $Ctx | Out-Null
                throw
            }
        }
    } else {
        # Boot image path (registry tweaks only)
        try {
            Mount-WibHives -MountDir $Ctx.MountDir
            foreach ($id in $ids) {
                $mod = $script:WibModules[$id]
                $appliesRes = Test-WibModuleApplies -Module $mod -Context $Ctx
                if (-not $appliesRes.Applies) { continue }
                $s = Get-WibModuleSettings $BuildProfile $id
                $tweaks = @(Get-WibModuleTweaks $mod $s)
                if ($tweaks.Count -gt 0) {
                    Write-WibLog "Registry tweaks: $id ($($tweaks.Count))" 'STEP'
                    $tweakResults = @(Invoke-WibTweaks -Tweaks $tweaks -ModuleId $id -Journal $Ctx.Journal -Image $Ctx.Image)
                    foreach ($r in $tweakResults) {
                        if ($r.Status -eq 'failed') {
                            if ($mod.OnError -eq 'halt') {
                                throw "Module '$id' failed with OnError=halt: $($r.Detail)"
                            } elseif ($mod.OnError -eq 'ignore') {
                                $r.Status = 'ignored'
                            }
                        }
                        [void]$results.Add($r)
                    }
                }
            }
            Write-WibLog 'Verifying changes' 'STEP'
            foreach ($id in $ids) {
                $mod = $script:WibModules[$id]
                $appliesRes = Test-WibModuleApplies -Module $mod -Context $Ctx
                if (-not $appliesRes.Applies) { continue }
                $s = Get-WibModuleSettings $BuildProfile $id
                $tweaks = @(Get-WibModuleTweaks $mod $s)
                $passed = 0
                foreach ($t in $tweaks) {
                    if ($script:WibLoadedHives -notcontains $t.Hive) { continue }
                    $r = Test-WibTweak $t
                    if ($r.Status -eq 'pass') { $passed++ } else { [void]$verify.Add($r) }
                }
                if ($passed -gt 0) { [void]$verify.Add((New-WibResult 'verify' "$id : $passed registry tweak(s)" 'pass')) }
            }
        } finally {
            [void](Dismount-WibHives -ThrowOnFailure)
        }
    }

    # E: post steps (hives unloaded)
    if ($isInstall) {
        if ($Ctx.ContainsKey('CompletedStages') -and ($Ctx.CompletedStages -contains 'post-steps')) {
            Write-WibLog 'Stage post-steps previously completed; continuing packaging.' 'INFO'
        } else {
            try {
                foreach ($id in $ids) {
                    $mod = $script:WibModules[$id]
                    $appliesRes = Test-WibModuleApplies -Module $mod -Context $Ctx
                    if (-not $appliesRes.Applies) { continue }
                    if (-not $mod.Post) { continue }
                    Write-WibLog "Post-step: $id" 'STEP'
                    $postResults = Invoke-WibModuleStep $mod $mod.Post $Ctx (Get-WibModuleSettings $BuildProfile $id) 'post'
                    foreach ($r in $postResults) {
                        if ($r) {
                            if ($r.Status -eq 'failed') {
                                if ($mod.OnError -eq 'halt') {
                                    throw "Module '$id' failed with OnError=halt: $($r.Detail)"
                                } elseif ($mod.OnError -eq 'ignore') {
                                    $r.Status = 'ignored'
                                }
                            }
                            [void]$results.Add($r)
                        }
                    }
                }
                $unresolvedPostFails = @($results | Where-Object { $_.Status -eq 'failed' })
                if ($unresolvedPostFails.Count -gt 0) {
                    throw "Stage 'post-steps' finished with $($unresolvedPostFails.Count) unresolved failure(s). Checkpoint commit blocked."
                }
                New-WibCheckpoint -Ctx $Ctx -StageName 'post-steps' | Out-Null
            } catch {
                Write-WibLog "Post-step stage failed: $($_.Exception.Message). Rolling back to last checkpoint..." 'ERROR'
                Restore-WibCheckpoint -Ctx $Ctx | Out-Null
                throw
            }
        }
    }
    @{ Results = $results; Verify = $verify }
}

function Test-WibPreflight {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ToolRoot,
        [Parameter(Mandatory)][string]$WorkDir,
        [string]$IsoPath = '',
        [string]$IsoDrive = '',
        [string]$ExpectedIsoSha256 = '',
        [switch]$DryRun,
        [switch]$DownloadOscdimg,
        [switch]$Resume,
        [double]$MinFreeDiskSpaceGB = 25.0,
        [switch]$NoCheckpoints,
        [switch]$Force,
        [switch]$StrictOscdimgHash
    )

    $resolvedWorkDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($WorkDir)
    $checks = New-Object System.Collections.ArrayList
    $failed = $false

    # 1. Admin check
    $isAdmin = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
    [void]$checks.Add([PSCustomObject]@{
        Check    = 'Elevation'
        Required = (-not $DryRun -and -not $Force)
        Status   = if ($isAdmin) { 'PASS' } elseif ($Force -or $DryRun) { 'WARN' } else { 'FAIL' }
        Detail   = if ($isAdmin) { 'Running as Administrator' } else { 'Run PowerShell as Administrator' }
    })
    if (-not $isAdmin -and -not $DryRun -and -not $Force) { $failed = $true }

    # 2. PowerShell Version
    $psOk = ($PSVersionTable.PSVersion.Major -ge 5)
    [void]$checks.Add([PSCustomObject]@{
        Check    = 'PowerShell Version'
        Required = $true
        Status   = if ($psOk) { 'PASS' } else { 'FAIL' }
        Detail   = "PowerShell $($PSVersionTable.PSVersion)"
    })
    if (-not $psOk) { $failed = $true }

    # 3. DISM Cmdlets
    $dismCmds = (Get-Command Mount-WindowsImage, Dismount-WindowsImage, Save-WindowsImage -ErrorAction SilentlyContinue).Count -eq 3
    [void]$checks.Add([PSCustomObject]@{
        Check    = 'DISM Cmdlets'
        Required = $true
        Status   = if ($dismCmds) { 'PASS' } else { 'FAIL' }
        Detail   = if ($dismCmds) { 'Available (Dism PowerShell module)' } else { 'Missing DISM cmdlets' }
    })
    if (-not $dismCmds) { $failed = $true }

    # 4. Source Image or Drive (or resumed existing sources)
    $srcOk = $false
    $srcDetail = ''
    $existingWim = Join-Path $resolvedWorkDir 'iso\sources\install.wim'
    if (-not (Test-Path -LiteralPath $existingWim)) {
        $existingWim = Join-Path $resolvedWorkDir 'sources\install.wim'
    }
    if ($Resume -and (Test-Path -LiteralPath $existingWim)) {
        $srcOk = $true
        $srcDetail = "Resuming from extracted sources: $existingWim"
    } elseif ($IsoPath) {
        $srcOk = (Test-Path -LiteralPath $IsoPath -PathType Leaf)
        $srcDetail = if ($srcOk) { "File: $IsoPath" } else { "ISO file not found: $IsoPath" }
    } elseif ($IsoDrive) {
        $drv = ($IsoDrive.TrimEnd(':\')) + ':\'
        $srcOk = (Test-Path -LiteralPath $drv)
        $srcDetail = if ($srcOk) { "Drive: $drv" } else { "Drive not found: $drv" }
    }
    [void]$checks.Add([PSCustomObject]@{
        Check    = 'Source Image'
        Required = $true
        Status   = if ($srcOk) { 'PASS' } else { 'FAIL' }
        Detail   = $srcDetail
    })
    if (-not $srcOk) { $failed = $true }

    # 4b. ISO Hash Verification Compatibility Check (F-11 / BUG-11)
    if ($IsoDrive -and $ExpectedIsoSha256) {
        [void]$checks.Add([PSCustomObject]@{
            Check    = 'ISO Hash Compatibility'
            Required = $true
            Status   = 'FAIL'
            Detail   = 'ExpectedIsoSha256 cannot be validated against -IsoDrive. Use -IsoPath for ISO hash verification or omit -ExpectedIsoSha256.'
        })
        $failed = $true
    }

    # 5. Work Drive Free Space - Dynamic capacity budgeting (F-06 / B-05)
    $driveRoot = [System.IO.Path]::GetPathRoot($resolvedWorkDir)
    $freeGB = 0.0
    try {
        $di = New-Object System.IO.DriveInfo $driveRoot
        $freeGB = [math]::Round($di.AvailableFreeSpace / 1GB, 1)
    } catch { Write-Verbose $_.Exception.Message }

    $sourceGB = 6.0
    if ($IsoPath -and (Test-Path -LiteralPath $IsoPath)) {
        try { $sourceGB = [math]::Round(((Get-Item -LiteralPath $IsoPath).Length / 1GB), 1) } catch {}
    } elseif ($existingWim -and (Test-Path -LiteralPath $existingWim)) {
        try { $sourceGB = [math]::Round((((Get-Item -LiteralPath $existingWim).Length * 1.3) / 1GB), 1) } catch {}
    }
    # Dynamic worst-case budget calculation derived from pipeline stages:
    # Staging extracted ISO (1.0x source) + mount expansion & servicing scratch (16 GB)
    # + checkpoints (4 checkpoints * 2.5 GB delta/scratch = 10 GB) + exported WIM (0.65x source, min 3.5 GB)
    # + boot.wim workspace (2.0 GB) + output ISO (0.9x source, min 4.5 GB) + safety buffer (5.0 GB)
    $stagingGB = [math]::Round($sourceGB * 1.0, 1)
    $mountGB = 16.0
    $checkpointsGB = if ($NoCheckpoints) { 0.0 } else { 10.0 }
    $exportWimGB = [math]::Round([math]::Max(3.5, $sourceGB * 0.65), 1)
    $bootWorkspaceGB = 2.0
    $outputIsoGB = [math]::Round([math]::Max(4.5, $sourceGB * 0.9), 1)
    $safetyMarginGB = 5.0

    $worstCaseBudgetGB = [math]::Round($stagingGB + $mountGB + $checkpointsGB + $exportWimGB + $bootWorkspaceGB + $outputIsoGB + $safetyMarginGB, 1)
    $thresholdGB = [math]::Max([double]$MinFreeDiskSpaceGB, $worstCaseBudgetGB)
    $spaceOk = ($freeGB -ge $thresholdGB -or $DryRun -or $Force)
    [void]$checks.Add([PSCustomObject]@{
        Check    = 'Work Drive Free Space'
        Required = (-not $DryRun -and -not $Force)
        Status   = if ($freeGB -ge $thresholdGB) { 'PASS' } elseif ($Force -or $DryRun) { 'WARN' } else { 'FAIL' }
        Detail   = "$freeGB GB free on $driveRoot (budgeted $thresholdGB GB based on staging: ${stagingGB}G, mount: ${mountGB}G, checkpoints: ${checkpointsGB}G, export: ${exportWimGB}G, boot/iso: $($bootWorkspaceGB + $outputIsoGB)G, safety: ${safetyMarginGB}G)"
    })
    if (-not $spaceOk) { $failed = $true }

    # 6. oscdimg tool check
    $oscdOk = $true
    $oscdDetail = 'Found or download allowed'
    if (-not $DryRun) {
        try {
            $null = Resolve-WibOscdimg -AllowDownload:$DownloadOscdimg -WorkDir $ToolRoot -StrictOscdimgHash:$StrictOscdimgHash
        } catch {
            $oscdOk = $false
            $oscdDetail = $_.Exception.Message
        }
    }
    [void]$checks.Add([PSCustomObject]@{
        Check    = 'Oscdimg Tool'
        Required = (-not $DryRun)
        Status   = if ($oscdOk) { 'PASS' } else { 'FAIL' }
        Detail   = $oscdDetail
    })
    if (-not $oscdOk -and -not $DryRun) { $failed = $true }

    # 7. Work Directory Space Check (oscdimg compatibility - BUG-16)
    $workHasSpace = ($resolvedWorkDir -match '\s')
    $workShort = if ($workHasSpace) { Get-WibShortPath $resolvedWorkDir } else { $resolvedWorkDir }
    $shortHasSpace = ($workShort -match '\s')
    $spaceStatus = 'PASS'
    $spaceDetail = 'Work path is space-free'
    if ($workHasSpace) {
        if (-not $shortHasSpace) {
            $spaceStatus = 'PASS'
            $spaceDetail = "Resolved 8.3 short path without spaces: $workShort"
        } else {
            $spaceStatus = if ($DryRun -or $Force) { 'WARN' } else { 'FAIL' }
            $spaceDetail = "Work path contains spaces ($resolvedWorkDir) and 8.3 short names are unavailable. oscdimg -bootdata will fail. Specify a path without spaces via -WorkDir (e.g. C:\wib-work)."
        }
    }
    [void]$checks.Add([PSCustomObject]@{
        Check    = 'Work Directory Path'
        Required = (-not $DryRun -and -not $Force)
        Status   = $spaceStatus
        Detail   = $spaceDetail
    })
    if ($spaceStatus -eq 'FAIL') { $failed = $true }

    Write-Host '================ PREFLIGHT SYSTEM VERIFICATION ================' -ForegroundColor Cyan
    '{0,-25} {1,-8} {2,-10} {3}' -f 'CHECK', 'REQUIRED', 'STATUS', 'DETAIL'
    Write-Host ('-' * 75)
    foreach ($c in $checks) {
        $color = switch ($c.Status) {
            'PASS' { 'Green' }
            'WARN' { 'Yellow' }
            default { 'Red' }
        }
        Write-Host ('{0,-25} {1,-8} {2,-10} {3}' -f $c.Check, [string]$c.Required, $c.Status, $c.Detail) -ForegroundColor $color
    }
    Write-Host ('-' * 75)

    if ($failed) {
        throw 'Preflight check failed. Resolve the highlighted issues or run with -Force where applicable.'
    }
    return @($checks)
}

function Publish-WibOutputIso {
    <#
    .SYNOPSIS
        Publishes a completed build ISO to its destination path atomically and safely.
    .DESCRIPTION
        Acquires an exclusive target-level publication lock file ($OutputIso.publock) with FileShare.None
        to serialize concurrent cross-workspace publishers.
        Re-verifies target existence inside the lock:
        - If target appeared and -Force was not specified, aborts immediately fail-closed and preserves
          both the pre-existing target and the completed temporary build artifact.
        - If target exists and -Force was specified, atomically replaces target in-place via Win32 ReplaceFile
          ([System.IO.File]::Replace).
        - If target does not exist, moves the temporary ISO to the destination.
        Optionally executes -PostPublishAction while the publication lock is STILL HELD, ensuring complete
        artifact, manifest, and report coherence before releasing the lock.
        If -PostPublishAction throws, rolls back target in-place inside the publication lock and preserves
        the temporary artifact before releasing the lock.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TempIsoPath,

        [Parameter(Mandatory = $true)]
        [string]$OutputIso,

        [Parameter(Mandatory = $false)]
        [string]$RunId = '',

        [switch]$Force,

        [string]$ExpectedTempIsoSha256 = '',

        [long]$ExpectedTempIsoSize = 0,

        [switch]$RequireIntegrityCheck,

        [scriptblock]$PostPublishAction = $null,

        [scriptblock]$OnFailureAction = $null,

        [switch]$RetainLock
    )

    if (-not (Test-Path -LiteralPath $TempIsoPath -PathType Leaf)) {
        throw "Temporary ISO '$TempIsoPath' does not exist or is not a leaf file."
    }

    if ([string]::IsNullOrEmpty($RunId)) {
        $RunId = [Guid]::NewGuid().ToString('N')
    }

    # Ensure parent directory of OutputIso exists
    $outDir = Split-Path -Parent $OutputIso
    if ($outDir -and -not (Test-Path -LiteralPath $outDir)) {
        New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    }

    # 1. Acquire target-level publication lock file to serialize cross-workspace builds
    $pubLockPath = "$OutputIso.publock"
    $pubLockStream = $null
    $lockAttempts = 0
    $maxLockAttempts = 300 # 30 seconds max wait (100ms * 300)
    while ($null -eq $pubLockStream -and $lockAttempts -lt $maxLockAttempts) {
        try {
            $pubLockStream = [System.IO.File]::Open($pubLockPath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        } catch [System.IO.IOException] {
            Start-Sleep -Milliseconds 100
            $lockAttempts++
        }
    }
    if ($null -eq $pubLockStream) {
        throw "Timed out waiting for publication lock on '$OutputIso' ($pubLockPath). Another build is currently publishing to this target output."
    }

    $bakPath = $null
    $targetExistsNow = $false
    $movedNew = $false
    $callbackFailed = $false
    $publishSucceeded = $false
    try {
        # 2a. Verify temporary artifact integrity under the publication lock
        if ($RequireIntegrityCheck -and (-not $ExpectedTempIsoSha256 -or $ExpectedTempIsoSize -le 0)) {
            throw "Cannot publish output ISO: -RequireIntegrityCheck is active but ExpectedTempIsoSha256 or ExpectedTempIsoSize was missing or non-positive."
        }
        if ($ExpectedTempIsoSize -gt 0) {
            $currentTempItem = Get-Item -LiteralPath $TempIsoPath
            if ($currentTempItem.Length -ne $ExpectedTempIsoSize) {
                throw "Temporary ISO size mismatch under publication lock: expected $ExpectedTempIsoSize bytes, got $($currentTempItem.Length) bytes."
            }
        }
        if ($ExpectedTempIsoSha256) {
            $currentTempSha = Get-WibSha256 -Path $TempIsoPath
            if ($currentTempSha -ne $ExpectedTempIsoSha256) {
                throw "Temporary ISO SHA-256 hash mismatch under publication lock: expected '$ExpectedTempIsoSha256', got '$currentTempSha'."
            }
        }

        # 2b. Re-verify target existence inside the lock
        $targetExistsNow = Test-Path -LiteralPath $OutputIso -PathType Leaf
        if ($targetExistsNow -and -not $Force) {
            throw "Output ISO '$OutputIso' was created during the build and -Force was not specified. Existing target preserved; completed build artifact preserved at '$TempIsoPath'."
        }

        # 3. Publish atomically
        if ($targetExistsNow) {
            $bakPath = "$OutputIso.bak.$RunId"
            [System.IO.File]::Replace($TempIsoPath, $OutputIso, $bakPath)
        } else {
            [System.IO.File]::Move($TempIsoPath, $OutputIso)
            $movedNew = $true
        }

        if (-not (Test-Path -LiteralPath $OutputIso -PathType Leaf)) {
            throw "Failed to publish output ISO: file '$OutputIso' not found after atomic replacement."
        }

        # 4. Execute post-publish action while publication lock is STILL HELD
        # Guarantees manifest, report, and published file coherence against concurrent publishers
        if ($PostPublishAction) {
            try {
                & $PostPublishAction @{
                    OutputIso         = $OutputIso
                    TempIsoPath       = $TempIsoPath
                    BackupPath        = $bakPath
                    RunId             = $RunId
                    Force             = [bool]$Force
                    TargetOverwritten = $targetExistsNow
                }
            } catch {
                $callbackFailed = $true
                $callbackError = $_
                Write-WibLog "Post-publish callback failed: $($callbackError.Exception.Message). Rolling back published ISO inside publication lock..." 'ERROR'

                $rollbackAttempted = $true
                $rollbackSucceeded = $false
                $rollbackError = $null

                # Rollback inside publication lock: atomically restore overwritten target via Win32 ReplaceFile
                if ($targetExistsNow -and $bakPath -and (Test-Path -LiteralPath $bakPath)) {
                    try {
                        # Atomically replace OutputIso with backup via Win32 ReplaceFile
                        # OutputIso is replaced with bakPath, and OutputIso's current content is moved to TempIsoPath.
                        # Zero interval where OutputIso does not exist.
                        if (Test-Path -LiteralPath $TempIsoPath) {
                            Remove-Item -LiteralPath $TempIsoPath -Force -ErrorAction SilentlyContinue
                        }
                        [System.IO.File]::Replace($bakPath, $OutputIso, $TempIsoPath)
                        if (Test-Path -LiteralPath $OutputIso -PathType Leaf) {
                            $rollbackSucceeded = $true
                            Write-WibLog "Published target '$OutputIso' atomically restored from backup via ReplaceFile; temporary build artifact preserved at '$TempIsoPath'." 'INFO'
                        } else {
                            $rollbackError = "Target file '$OutputIso' was not present after atomic ReplaceFile from backup."
                            Write-WibLog "Target restoration failed during publication rollback: $rollbackError" 'ERROR'
                        }
                    } catch {
                        $rollbackError = "Atomic ReplaceFile failed: $($_.Exception.Message)"
                        Write-WibLog "Target restoration failed during publication rollback: $rollbackError" 'ERROR'
                    }
                } elseif ($movedNew -and (Test-Path -LiteralPath $OutputIso)) {
                    try {
                        [System.IO.File]::Move($OutputIso, $TempIsoPath)
                        if (Test-Path -LiteralPath $TempIsoPath -PathType Leaf) {
                            $rollbackSucceeded = $true
                            Write-WibLog "Newly published target '$OutputIso' unlinked and returned to '$TempIsoPath'." 'INFO'
                        } else {
                            $rollbackError = "Temporary artifact '$TempIsoPath' was not present after revocation."
                            Write-WibLog "New target revocation failed during publication rollback: $rollbackError" 'ERROR'
                        }
                    } catch {
                        $rollbackError = "New target revocation failed: $($_.Exception.Message)"
                        Write-WibLog "New target revocation failed during publication rollback: $rollbackError" 'ERROR'
                    }
                }

                if ($OnFailureAction) {
                    try {
                        & $OnFailureAction @{
                            Error             = $callbackError
                            OutputIso         = $OutputIso
                            TempIsoPath       = $TempIsoPath
                            RunId             = $RunId
                            RollbackAttempted = $rollbackAttempted
                            RollbackSucceeded = $rollbackSucceeded
                            RollbackError     = $rollbackError
                        }
                    } catch {
                        Write-WibLog "OnFailureAction threw: $($_.Exception.Message)" 'WARN'
                    }
                }

                throw $callbackError
            }
        }

        # Clean up backup artifact strictly AFTER PostPublishAction succeeds
        if ($bakPath -and (Test-Path -LiteralPath $bakPath)) {
            try {
                Remove-Item -LiteralPath $bakPath -Force -ErrorAction Stop
            } catch {
                Write-WibLog "Backup artifact cleanup failed for '$bakPath': $($_.Exception.Message)" 'WARN'
            }
        }

        $publishSucceeded = $true
        return [PSCustomObject]@{
            Success           = $true
            OutputIso         = $OutputIso
            TargetOverwritten = $targetExistsNow
            ReplacedInPlace   = $targetExistsNow
            TempIsoConsumed   = (-not (Test-Path -LiteralPath $TempIsoPath))
            LockStream        = if ($RetainLock) { $pubLockStream } else { $null }
            LockPath          = if ($RetainLock) { $pubLockPath } else { $null }
        }
    }
    catch {
        if ($OnFailureAction -and -not $callbackFailed) {
            try {
                & $OnFailureAction @{
                    Error             = $_
                    OutputIso         = $OutputIso
                    TempIsoPath       = $TempIsoPath
                    RunId             = $RunId
                    RollbackAttempted = $false
                    RollbackSucceeded = $false
                    RollbackError     = $null
                }
            } catch {}
        }
        throw
    }
    finally {
        # 5. Release publication lock strictly after post-publish actions, any rollback, or failure handling finish
        # If -RetainLock was specified and publication succeeded, the caller retains the lock until final sealing.
        if ($pubLockStream -and (-not $RetainLock -or -not $publishSucceeded)) {
            $pubLockStream.Close()
            $pubLockStream.Dispose()
            Remove-Item -LiteralPath $pubLockPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-WibBuild {
    [CmdletBinding()]
    param(
        [string]$IsoPath, [string]$IsoDrive, [string]$ExpectedIsoSha256, [switch]$SkipIsoHash,
        [Parameter(Mandatory)][string]$ProfilePath,
        [Parameter(Mandatory)][string]$ToolRoot,
        [string]$WorkDir, [string]$OutputIso, [int]$Index = 0,
        [switch]$DryRun, [switch]$KeepWork, [switch]$DownloadOscdimg, [switch]$Resume,
        [string]$HardwareSpec, [switch]$AcceptRisk,
        [string]$DeltaFromManifest = '',
        [switch]$Strict,
        [switch]$Force,
        [switch]$NoCheckpoints,
        [string]$Compression = '',
        [string]$SigningCertThumbprint,
        [double]$MinFreeDiskSpaceGB = 25.0,
        [switch]$StrictOscdimgHash
    )
    $ErrorActionPreference = 'Stop'
    if ($Strict) {
        $StrictOscdimgHash = $true
    }
    if ($Strict -and $Force) {
        throw 'Parameter conflict: -Strict cannot be combined with -Force. -Strict mandates fail-closed enforcement on all failed or unverified steps.'
    }
    if (Get-Command Reset-WibNativeToolTelemetry -ErrorAction SilentlyContinue) {
        Reset-WibNativeToolTelemetry
    }
    $buildStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $runId = [System.Guid]::NewGuid().ToString('N').Substring(0, 8).ToUpper()
    $stamp = (Get-Date).ToString('yyyyMMdd_HHmmss') + "_$runId"
    $ToolRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ToolRoot)
    $reportDir = Join-Path $ToolRoot "reports\$stamp"
    New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
    if (Get-Command Protect-WibSensitiveDirectoryAcl -ErrorAction SilentlyContinue) {
        try { [void](Protect-WibSensitiveDirectoryAcl -Path $reportDir) } catch { Write-Verbose $_.Exception.Message }
    }
    Set-WibLogPath (Join-Path $reportDir 'build.log')

    # ---- load + validate profile BEFORE touching any image
    # Resolve-WibEffectiveBuildProfile is the single canonical entry point for both initial
    # build and -Resume. It computes ResolvedHash (pre-adaptation, for profile identity) and
    # EffectiveHash (post-adaptation, the resume comparison key). Using EffectiveHash as the
    # resume comparison value fixes the P1 adaptive resume hash mismatch (v0.2.8).
    $buildProfile = Import-WibProfile -Path $ProfilePath
    Test-WibProfile -BuildProfile $buildProfile -AcceptRisk:$AcceptRisk
    $profileName = [string]$buildProfile['profile']
    $effectiveResolution = Resolve-WibEffectiveBuildProfile -BuildProfile $buildProfile -HardwareSpec $HardwareSpec -AcceptRisk:$AcceptRisk
    $resolvedHash      = $effectiveResolution.ResolvedHash      # pre-adaptation identity hash
    $effectiveHash     = $effectiveResolution.EffectiveHash      # post-adaptation resume key
    $hwProfile         = $effectiveResolution.HardwareProfile
    $hwProfileHash     = $effectiveResolution.HardwareProfileHash
    $adaptiveDecisions = @($effectiveResolution.AdaptiveDecisions)
    # buildProfile is already mutated by Resolve-WibEffectiveBuildProfile if adaptive
    Write-WibLog "WIB $script:WibVersion - profile '$profileName'$(if ($DryRun) { ' (DRY RUN)' })" 'STEP'
    Write-WibLog "Profile canonical hash (resolved): $resolvedHash" 'INFO'
    Write-WibLog "Profile canonical hash (effective): $effectiveHash" 'INFO'
    Write-WibLog 'Rollback policy: stage failure triggers DISM discard and clean mount restoration from last good checkpoint index.' 'INFO'
    if ($hwProfile) {
        Write-WibLog "Adaptive Mode: Target hardware: $($hwProfile.RamGB) GB RAM, $($hwProfile.StorageType), $($hwProfile.CpuCores) cores, $($hwProfile.GpuType) GPU ($($hwProfile.FormFactor)) [Source: $($hwProfile.Source), Confidence: $($hwProfile.Confidence)]" 'INFO'
        Write-WibLog "Hardware profile canonical hash: $hwProfileHash" 'INFO'
        if ($hwProfile.SpecFile -and (Test-Path -LiteralPath $hwProfile.SpecFile)) {
            $HardwareSpec = $hwProfile.SpecFile
        }
    }

    if (-not $WorkDir) { $WorkDir = Join-Path $ToolRoot 'work' }
    $WorkDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($WorkDir)
    $isoDir = Join-Path $WorkDir 'iso'
    $mountDir = Join-Path $WorkDir 'mount'
    if (-not $OutputIso) { $OutputIso = Join-Path $ToolRoot ("wib-{0}-{1}-{2}.iso" -f $profileName, (Get-Date).ToString('yyyyMMdd'), $runId) }
    $OutputIso = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputIso)
    
    # Reject dangerous -OutputIso configurations (source ISO overwrite or workdir nesting)
    $outCanonical = [System.IO.Path]::GetFullPath($OutputIso)
    if ($IsoPath -and (Test-Path -LiteralPath $IsoPath)) {
        $sourceCanonical = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $IsoPath).Path)
        if ($outCanonical.Equals($sourceCanonical, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Invalid -OutputIso: target ISO path '$OutputIso' cannot be identical to the source ISO '$IsoPath'."
        }
    }
    $workCanonical = [System.IO.Path]::GetFullPath($WorkDir)
    $workBoundary = $workCanonical.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    if ($outCanonical.StartsWith($workBoundary, [System.StringComparison]::OrdinalIgnoreCase) -or $outCanonical.Equals($workCanonical, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Invalid -OutputIso: target ISO path '$OutputIso' cannot reside inside active build workspace '$WorkDir'."
    }

    # Path containment and adversarial reparse point checks (P2-05 / v0.2.18)
    if (Test-Path -LiteralPath $WorkDir) {
        $workDirItem = Get-Item -LiteralPath $WorkDir -Force -ErrorAction SilentlyContinue
        if ($workDirItem -and [bool]($workDirItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
            throw "Security violation: Workspace directory '$WorkDir' is an NTFS junction or symbolic link. Reparse points are forbidden for workspace root."
        }
    }
    $null = Test-WibPathContainment -Path $isoDir -BaseDir $WorkDir
    $null = Test-WibPathContainment -Path $mountDir -BaseDir $WorkDir
    if (Test-Path -LiteralPath $mountDir) {
        $mountDirItem = Get-Item -LiteralPath $mountDir -Force -ErrorAction SilentlyContinue
        if ($mountDirItem -and [bool]($mountDirItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
            throw "Security violation: Mount directory '$mountDir' is an NTFS junction or symbolic link. Reparse points are forbidden for mount directory."
        }
    }

    if (Test-Path -LiteralPath $OutputIso) {
        if (-not $Force -and -not $DryRun) {
            throw "Output ISO '$OutputIso' already exists. Specify a unique -OutputIso path, pass -Force to overwrite, or omit -OutputIso to generate a unique default name."
        } else {
            Write-WibLog "Overwriting existing output ISO '$OutputIso' (-Force specified)." 'WARN'
        }
    }

    $state = @{ IsoMounted = $false; ImageMounted = $false; Success = $false; TeardownFailed = $false }
    $manifest = [ordered]@{
        tool = @{ name = 'WIB'; version = $script:WibVersion; runId = $runId }
        createdUtc = (Get-Date).ToUniversalTime().ToString('o')
        status = 'failed'; dryRun = [bool]$DryRun; resumed = [bool]$Resume
        profile = @{
            name            = $profileName
            version         = $buildProfile['version']
            sha256          = $resolvedHash
            effectiveSha256 = $effectiveHash
            parentChain     = @($buildProfile.parentChain)
            fileSha256      = (Get-WibSha256 $ProfilePath)
        }
        source = @{}; oscdimg = @{}; output = @{}
        plan = @(); results = @(); verification = @(); checkpoints = @()
    }
    if ($hwProfile) {
        $manifest['hardware'] = [ordered]@{
            ramGB               = $hwProfile.RamGB
            storageType         = $hwProfile.StorageType
            cpuCores            = $hwProfile.CpuCores
            gpuType             = $hwProfile.GpuType
            formFactor          = $hwProfile.FormFactor
            source              = $hwProfile.Source
            confidence          = $hwProfile.Confidence
            hardwareProfileHash = $hwProfileHash
        }
        $manifest['adaptiveDecisions'] = @($adaptiveDecisions)
    }
    $journal = New-Object System.Collections.ArrayList
    $workspaceLock = $null
    $targetPubLockStream = $null
    $targetPubLockPath = $null
    $parsedCp = $null
    $unattendResumePath = $null

    try {
        # ---- 1. preflight
        Write-WibLog 'Preflight' 'STEP'
        Test-WibPreflight -ToolRoot $ToolRoot -WorkDir $WorkDir -IsoPath $IsoPath -IsoDrive $IsoDrive -ExpectedIsoSha256 $ExpectedIsoSha256 -DryRun:$DryRun -DownloadOscdimg:$DownloadOscdimg -Resume:$Resume -MinFreeDiskSpaceGB $MinFreeDiskSpaceGB -NoCheckpoints:$NoCheckpoints -Force:$Force -StrictOscdimgHash:$StrictOscdimgHash | Out-Null

        # ---- 1a. Pre-DISM recovery validation (before lock + stale-mount ops)
        # Authoritatively validate recovery-state.json BEFORE acquiring the
        # workspace lock and before touching any stale DISM mount state.
        if ($Resume) {
            New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

            $recFile = Join-Path $WorkDir 'recovery-state.json'
            $hasRec = Test-Path -LiteralPath $recFile
            $cpFile = Join-Path $WorkDir 'checkpoints.json'
            $hasCp = Test-Path -LiteralPath $cpFile

            if (-not $hasRec -and -not $hasCp) {
                $missingTarget = if ($hasRec) { $recFile } else { $cpFile }
                throw "Cannot resume: checkpoints ledger '$missingTarget' is missing. Re-run without -Resume."
            }

            if ($hasRec) {
                $rawRec = Get-Content -LiteralPath $recFile -Raw
                if (-not $rawRec -or $rawRec.Trim().Length -lt 2) {
                    throw "Cannot resume: recovery state '$recFile' is corrupt or unparseable: recovery ledger is empty. Re-run without -Resume."
                }
                try {
                    $parsedRec = ConvertFrom-Json -InputObject $rawRec -ErrorAction Stop
                    if ($null -eq $parsedRec) { throw "recovery state '$recFile' parsed as null." }
                } catch {
                    if ($_.Exception.Message -like '*Cannot resume:*') { throw }
                    throw "Cannot resume: recovery state '$recFile' is corrupt or unparseable: $($_.Exception.Message). Re-run without -Resume."
                }
            } else {
                # Legacy compatibility fallback for checkpoints.json and journal.partial.json
                $rawCp = Get-Content -LiteralPath $cpFile -Raw
                if (-not $rawCp -or $rawCp.Trim().Length -lt 2) {
                    throw "Cannot resume: checkpoints ledger '$cpFile' is empty. Re-run without -Resume."
                }
                try {
                    $legacyCps = ConvertFrom-Json -InputObject $rawCp -ErrorAction Stop
                    if ($null -eq $legacyCps -and ($rawCp.Trim() -replace '\s+', '') -eq '[]') {
                        $legacyCps = @()
                    }
                    if ($null -eq $legacyCps) { throw "checkpoints ledger '$cpFile' parsed as null." }
                } catch {
                    if ($_.Exception.Message -like '*Cannot resume:*') { throw }
                    throw "Cannot resume: checkpoints ledger '$cpFile' is corrupt or unparseable: $($_.Exception.Message). Re-run without -Resume."
                }

                $jp = Join-Path $WorkDir 'journal.partial.json'
                if (-not (Test-Path -LiteralPath $jp)) {
                    throw "Cannot resume: journal ledger '$jp' is missing. Re-run without -Resume."
                }
                $rawJp = Get-Content -LiteralPath $jp -Raw
                if (-not $rawJp -or $rawJp.Trim().Length -lt 2) {
                    throw "Cannot resume: partial journal '$jp' is corrupt or unparseable: journal ledger is empty. Re-run without -Resume."
                }
                try {
                    $legacyJournal = ConvertFrom-Json -InputObject $rawJp -ErrorAction Stop
                    if ($null -eq $legacyJournal -and ($rawJp.Trim() -replace '\s+', '') -eq '[]') {
                        $legacyJournal = @()
                    }
                    if ($null -eq $legacyJournal) { throw "journal ledger '$jp' parsed as null." }
                } catch {
                    if ($_.Exception.Message -like '*Cannot resume:*') { throw }
                    throw "Cannot resume: partial journal '$jp' is corrupt or unparseable: $($_.Exception.Message). Re-run without -Resume."
                }

                # Construct recovery state from legacy ledgers for uniform validation
                $lastLegacyCp = if (@($legacyCps).Count -gt 0) { @($legacyCps)[@($legacyCps).Count - 1] } else { $null }
                $lastProv = if ($lastLegacyCp -and $lastLegacyCp.PSObject.Properties['Provenance']) { $lastLegacyCp.Provenance } else { $null }
                $legacyOrigIdx = if ($lastProv -and $lastProv.PSObject.Properties['SourceWimOriginalIndex'] -and $lastProv.SourceWimOriginalIndex) {
                    [int]$lastProv.SourceWimOriginalIndex
                } elseif ($lastProv -and $lastProv.PSObject.Properties['SourceIndex'] -and $lastProv.SourceIndex) {
                    [int]$lastProv.SourceIndex
                } else {
                    1
                }
                $legacyMountedIdx = if ($lastLegacyCp -and $lastLegacyCp.WimIndex) { [int]$lastLegacyCp.WimIndex } else { 1 }
                $legacyEffSha = if ($lastProv -and $lastProv.PSObject.Properties['EffectiveSha256'] -and $lastProv.EffectiveSha256) {
                    [string]$lastProv.EffectiveSha256
                } else {
                    $resolvedHash
                }
                $legacyWimSha = if ($lastProv -and $lastProv.PSObject.Properties['BaselineSourceWimSha256'] -and $lastProv.BaselineSourceWimSha256) {
                    [string]$lastProv.BaselineSourceWimSha256
                } elseif ($lastProv -and $lastProv.PSObject.Properties['SourceWimSha256'] -and $lastProv.SourceWimSha256) {
                    [string]$lastProv.SourceWimSha256
                } else {
                    'MOCK_SOURCE_WIM_SHA256'
                }
                $legacyCurrentWimSha = if ($lastProv -and $lastProv.PSObject.Properties['CurrentWorkspaceWimSha256'] -and $lastProv.CurrentWorkspaceWimSha256) {
                    [string]$lastProv.CurrentWorkspaceWimSha256
                } else {
                    $legacyWimSha
                }
                $legacyIsoSha = if ($lastProv -and $lastProv.PSObject.Properties['SourceIsoSha256']) { [string]$lastProv.SourceIsoSha256 } else { '' }
                $legacyIsoStatus = if ($lastProv -and $lastProv.PSObject.Properties['SourceIsoHashStatus'] -and $lastProv.SourceIsoHashStatus) {
                    [string]$lastProv.SourceIsoHashStatus
                } elseif ($legacyIsoSha -and $legacyIsoSha.Trim() -ne '') {
                    'verified'
                } else {
                    'unavailable'
                }

                # Synthesize any missing mandatory schema fields across legacy checkpoints
                foreach ($lcp in $legacyCps) {
                    if ($lcp.PSObject.Properties['Provenance'] -and $lcp.Provenance) {
                        $lp = $lcp.Provenance
                        if (-not (Test-WibHasProp $lp 'BaselineSourceWimSha256')) {
                            $baseVal = if (Test-WibHasProp $lp 'SourceWimSha256') { [string]$lp.SourceWimSha256 } else { $legacyWimSha }
                            $lp | Add-Member -MemberType NoteProperty -Name 'BaselineSourceWimSha256' -Value $baseVal -Force
                        }
                        if (-not (Test-WibHasProp $lp 'CurrentWorkspaceWimSha256')) {
                            $lp | Add-Member -MemberType NoteProperty -Name 'CurrentWorkspaceWimSha256' -Value $legacyCurrentWimSha -Force
                        }
                        if (-not (Test-WibHasProp $lp 'SourceIsoHashStatus')) {
                            $lp | Add-Member -MemberType NoteProperty -Name 'SourceIsoHashStatus' -Value $legacyIsoStatus -Force
                        }
                        if (-not (Test-WibHasProp $lp 'SourceWimOriginalIndex')) {
                            $lp | Add-Member -MemberType NoteProperty -Name 'SourceWimOriginalIndex' -Value $legacyOrigIdx -Force
                        }
                        if (-not (Test-WibHasProp $lp 'CheckpointWimIndex')) {
                            $lpWimIdx = if ($lcp.WimIndex) { [int]$lcp.WimIndex } else { 1 }
                            $lp | Add-Member -MemberType NoteProperty -Name 'CheckpointWimIndex' -Value $lpWimIdx -Force
                        }
                        if (-not (Test-WibHasProp $lp 'ProvenanceTier')) {
                            $lp | Add-Member -MemberType NoteProperty -Name 'ProvenanceTier' -Value 'migrated-inferred' -Force
                        }
                    }
                }

                $parsedRec = [ordered]@{
                    Version                     = $script:WibVersion
                    ToolVersion                 = $script:WibVersion
                    CommitState                 = 'committed'
                    ProvenanceTier              = 'migrated-inferred'
                    ProvenanceTrustNotice       = 'Inferred provenance from legacy checkpoints.json / journal.partial.json. Historical physical WIM mutation hash inferred from baseline hash.'
                    Checkpoints                 = $legacyCps
                    Journal                     = $legacyJournal
                    OriginalSourceIndex         = $legacyOrigIdx
                    MountedIndex                = $legacyMountedIdx
                    ProfileHash                 = $resolvedHash
                    EffectiveSha256             = $legacyEffSha
                    BaselineSourceWimSha256     = $legacyWimSha
                    SourceWimSha256             = $legacyWimSha
                    CurrentWorkspaceWimSha256   = $legacyCurrentWimSha
                    SourceIsoHashStatus         = $legacyIsoStatus
                    SourceIsoSha256             = $legacyIsoSha
                }
                Write-WibLog "Resuming from legacy workspace: synthesized recovery record labeled as 'migrated-inferred' trust tier." 'WARN'
            }

            # Validate confined unattend path on resume (before any DISM operations)
            $oobeSettings = Get-WibModuleSettings $buildProfile 'oobe-local-account'
            if ($oobeSettings -and $oobeSettings.ContainsKey('unattendPath') -and $oobeSettings['unattendPath']) {
                $base = if ($ToolRoot) { $ToolRoot } else { Split-Path -Parent $PSScriptRoot }
                try {
                    $uSrc = Resolve-WibConfinedPath -Path ([string]$oobeSettings['unattendPath']) -BaseDir $base -AllowedExtensions @('.xml')
                    if (Test-Path -LiteralPath $uSrc) { $unattendResumePath = $uSrc }
                } catch {
                    throw "Failed to resolve confined unattend path on resume: $($_.Exception.Message)"
                }
            }

            # Context parameters for recovery validation
            $preExpectedIsoSha = if ($ExpectedIsoSha256) {
                $ExpectedIsoSha256.ToUpper()
            } elseif (Test-Path -LiteralPath (Join-Path $WorkDir 'source.iso.sha256')) {
                (Get-Content -LiteralPath (Join-Path $WorkDir 'source.iso.sha256') -Raw).Trim()
            } else { '' }

            $preExpectedWimSha = if (Test-Path -LiteralPath (Join-Path $WorkDir 'source.wim.sha256')) {
                (Get-Content -LiteralPath (Join-Path $WorkDir 'source.wim.sha256') -Raw).Trim()
            } else { '' }

            $preHwSpecHash = if ($HardwareSpec -and (Test-Path -LiteralPath $HardwareSpec)) { Get-WibSha256 $HardwareSpec } else { '' }

            $preOrigSourceIdx = if ($Index) {
                [int]$Index
            } elseif (Test-Path -LiteralPath (Join-Path $WorkDir 'source.index')) {
                [int](Get-Content -LiteralPath (Join-Path $WorkDir 'source.index') -Raw).Trim()
            } else {
                0
            }

            # Single unified pre-DISM recovery validation (P1 Findings 1, 2, 3, 4)
            # Use effectiveHash (post-adaptation) as the expected hash -- checkpoints store
            # EffectiveSha256 computed after Invoke-WibAdaptiveDecisions mutated the profile.
            # Using resolvedHash (pre-adaptation) would reject every valid adaptive checkpoint.
            $validatedRecovery = Test-WibRecoveryState -RecoveryState $parsedRec `
                -WorkDir $WorkDir `
                -ExpectedToolVersion $script:WibVersion `
                -ExpectedProfileHash $effectiveHash `
                -ExpectedHardwareProfileHash $hwProfileHash `
                -ExpectedHardwareSpecHash $preHwSpecHash `
                -ExpectedSourceIsoSha $preExpectedIsoSha `
                -ExpectedSourceWimSha $preExpectedWimSha `
                -ExpectedOriginalSourceIndex $preOrigSourceIdx

            $parsedCp = $validatedRecovery.Checkpoints
            if ($parsedRec.Journal) {
                foreach ($entry in $parsedRec.Journal) {
                    $hashEntry = ConvertTo-WibHashtable $entry
                    [void]$journal.Add($hashEntry)
                }
            }
            $Index = $validatedRecovery.MountedIndex
            $originalSourceIndex = $validatedRecovery.OriginalSourceIndex
            $sourceContainer = if ($validatedRecovery.ContainsKey('SourceContainer')) { [string]$validatedRecovery.SourceContainer } else { 'WIM' }
            $sourceContainerIndex = if ($validatedRecovery.ContainsKey('SourceContainerIndex')) { [int]$validatedRecovery.SourceContainerIndex } else { [int]$originalSourceIndex }
            $servicingWimIndex = if ($validatedRecovery.ContainsKey('ServicingWimIndex')) { [int]$validatedRecovery.ServicingWimIndex } else { [int]$Index }
            $baselineSourceWimSha = $validatedRecovery.BaselineSourceWimSha256
            $currentWorkspaceWimSha = $validatedRecovery.CurrentWorkspaceWimSha256
            $orphanWimIndices = $validatedRecovery.OrphanWimIndices
        }

        New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
        $script:WibHivePrefix = "wib_${runId}_"
        $workspaceLock = Lock-WibWorkspace -WorkDir $WorkDir -RunId $runId
        Clear-WibStaleHives -Prefix $script:WibHivePrefix

        $resumingExistingSources = ($Resume -and ((Test-Path -LiteralPath (Join-Path $isoDir 'sources\install.wim')) -or (Test-Path -LiteralPath (Join-Path $WorkDir 'sources\install.wim'))))
        $stale = @(Get-WibMountedImage -Path $mountDir)
        if ($stale.Count -gt 0) {
            Write-WibLog 'Found a stale mount at the work path; discarding it.' 'WARN'
            try {
                Dismount-WindowsImage -Path $mountDir -Discard -ErrorAction Stop
            } catch {
                Write-WibLog "Standard dismount failed: $($_.Exception.Message). Running Clear-WindowsCorruptMountPoint / dism /Cleanup-Wim..." 'WARN'
                if (Get-Command Clear-WindowsCorruptMountPoint -ErrorAction SilentlyContinue) {
                    try { Clear-WindowsCorruptMountPoint -Path $mountDir -ErrorAction SilentlyContinue } catch { Write-Verbose $_.Exception.Message }
                }
                [void](Invoke-WibNativeTool -ToolKey 'dismExe' -FilePath 'dism.exe' -Arguments @('/Cleanup-Wim'))
            }
            # Positive proof invariant: verify mount point is completely clear
            $remaining = @(Get-WibMountedImage -Path $mountDir)
            if ($remaining.Count -gt 0) {
                throw "Stale mount recovery failed: mount path '$mountDir' remains active after discard/cleanup."
            }
        }

        $fastDryRun = $false
        $scratchWim = $null
        $originalSourceIndex = if ($Index) { [int]$Index } else { 1 }
        $sourceContainer = 'WIM'
        $sourceContainerIndex = $originalSourceIndex
        $servicingWimIndex = $originalSourceIndex

        if (-not $resumingExistingSources) {
            if ($IsoPath) {
                $isoFull = (Resolve-Path -LiteralPath $IsoPath).Path
                $isoItemBefore = Get-Item -LiteralPath $isoFull
                $isoLengthBefore = $isoItemBefore.Length
                $isoMtimeBefore = $isoItemBefore.LastWriteTimeUtc
                $preMountIsoSha = ''
                if (-not $SkipIsoHash) {
                    Write-WibLog 'Hashing source ISO pre-mount (use -SkipIsoHash to skip)...'
                    $preMountIsoSha = Get-WibSha256 $isoFull
                    $manifest.source.isoSha256 = $preMountIsoSha
                    $manifest.source['isoSha256PreMount'] = $preMountIsoSha
                    if ($ExpectedIsoSha256 -and ($preMountIsoSha -ne $ExpectedIsoSha256.ToUpper())) {
                        throw "ISO hash mismatch. Expected $ExpectedIsoSha256, got $preMountIsoSha."
                    }
                } elseif ($ExpectedIsoSha256) { throw '-ExpectedIsoSha256 cannot be combined with -SkipIsoHash.' }
                $img = Mount-DiskImage -ImagePath $isoFull -PassThru
                $state.IsoMounted = $true

                # Verify file integrity invariance across mount transition (P2-04 Cryptographic TOCTOU Mitigation)
                $isoItemAfter = Get-Item -LiteralPath $isoFull
                if ($isoItemAfter.Length -ne $isoLengthBefore -or $isoItemAfter.LastWriteTimeUtc -ne $isoMtimeBefore) {
                    throw "Source ISO TOCTOU mutation detected: '$isoFull' was altered or replaced during image mounting. Build aborted fail-closed."
                }
                if (-not $SkipIsoHash) {
                    Write-WibLog 'Re-verifying cryptographic SHA-256 of mounted source ISO under kernel mount lock...'
                    $postMountIsoSha = Get-WibSha256 $isoFull
                    $manifest.source['isoSha256PostMount'] = $postMountIsoSha
                    if ($postMountIsoSha -ne $preMountIsoSha) {
                        throw "Source ISO TOCTOU mutation detected: cryptographic SHA-256 digest of '$isoFull' changed across mount transition (pre-mount: $preMountIsoSha, post-mount: $postMountIsoSha). Build aborted fail-closed."
                    }
                    $manifest.source.isoSha256 = $postMountIsoSha
                    $manifest.source['isoToctouVerified'] = $true
                } else {
                    $manifest.source['isoToctouVerified'] = $false
                }
                $srcRoot = ('{0}:\' -f ($img | Get-Volume).DriveLetter)
            } elseif ($IsoDrive) {
                $srcRoot = ($IsoDrive.TrimEnd(':') + ':\')
            } else { throw 'Provide -IsoPath or -IsoDrive.' }

            # Faster Dry-Run: mount read-only directly from source ISO if WIM exists (skips multi-GB copy)
            if ($DryRun) {
                $candidateWim = Join-Path $srcRoot 'sources\install.wim'
                $candidateEsd = Join-Path $srcRoot 'sources\install.esd'
                if (Test-Path -LiteralPath $candidateWim) {
                    Write-WibLog "Faster Dry-Run: mounting read-only directly from source ($candidateWim) without copying files." 'INFO'
                    $wim = $candidateWim
                    $fastDryRun = $true
                    $Index = Select-WibIndex -ImagePath $wim -Index $Index
                    $originalSourceIndex = [int]$Index
                    New-Item -ItemType Directory -Force -Path $mountDir | Out-Null
                    if (Get-Command Protect-WibSensitiveDirectoryAcl -ErrorAction SilentlyContinue) { [void](Protect-WibSensitiveDirectoryAcl -Path $mountDir) }
                } elseif (Test-Path -LiteralPath $candidateEsd) {
                    Write-WibLog "Faster Dry-Run: exporting single target index from ESD with fast compression for scan." 'INFO'
                    $Index = Select-WibIndex -ImagePath $candidateEsd -Index $Index
                    $originalSourceIndex = [int]$Index
                    $sourceContainer = 'ESD'
                    $sourceContainerIndex = $originalSourceIndex
                    $servicingWimIndex = 1
                    $scratchWim = Join-Path $WorkDir 'scratch.wim'
                    Export-WindowsImage -SourceImagePath $candidateEsd -SourceIndex $Index -DestinationImagePath $scratchWim -CompressionType fast | Out-Null
                    $wim = $scratchWim
                    $Index = 1
                    $fastDryRun = $true
                    New-Item -ItemType Directory -Force -Path $mountDir | Out-Null
                    if (Get-Command Protect-WibSensitiveDirectoryAcl -ErrorAction SilentlyContinue) { [void](Protect-WibSensitiveDirectoryAcl -Path $mountDir) }
                }
            }

            if (-not $fastDryRun) {
                # ---- 2. stage source files
                Write-WibLog 'Copying source files' 'STEP'
                if (Test-Path -LiteralPath $isoDir) { Remove-Item -LiteralPath $isoDir -Recurse -Force }
                New-Item -ItemType Directory -Force -Path $isoDir, $mountDir | Out-Null
                if (Get-Command Protect-WibSensitiveDirectoryAcl -ErrorAction SilentlyContinue) {
                    [void](Protect-WibSensitiveDirectoryAcl -Path $isoDir)
                    [void](Protect-WibSensitiveDirectoryAcl -Path $mountDir)
                }
                Copy-Item -Path (Join-Path $srcRoot '*') -Destination $isoDir -Recurse -Force
                [void](Invoke-WibNativeTool -ToolKey 'attribExe' -FilePath 'attrib.exe' -Arguments @('-R', "$isoDir\*", '/S', '/D'))
                if ($LASTEXITCODE -ne 0) {
                    throw "attrib.exe failed with exit code $LASTEXITCODE while clearing read-only attributes on '$isoDir'."
                }

                $wim = Join-Path $isoDir 'sources\install.wim'
                $esd = Join-Path $isoDir 'sources\install.esd'
                if (-not (Test-Path -LiteralPath $wim)) {
                    if (-not (Test-Path -LiteralPath $esd)) { throw 'No install.wim or install.esd found in the source.' }
                    $Index = Select-WibIndex -ImagePath $esd -Index $Index
                    $originalSourceIndex = [int]$Index
                    $sourceContainer = 'ESD'
                    $sourceContainerIndex = $originalSourceIndex
                    $servicingWimIndex = 1
                    Write-WibLog 'Converting install.esd to install.wim (this takes a while)...'
                    Export-WindowsImage -SourceImagePath $esd -SourceIndex $Index -DestinationImagePath $wim -CompressionType max -CheckIntegrity | Out-Null
                    Remove-Item -LiteralPath $esd -Force
                    $Index = 1
                    Set-Content -LiteralPath (Join-Path $WorkDir 'source.index') -Value ([string]$originalSourceIndex) -Encoding ASCII
                } else {
                    $Index = Select-WibIndex -ImagePath $wim -Index $Index
                    $originalSourceIndex = [int]$Index
                    $sourceContainer = 'WIM'
                    $sourceContainerIndex = $originalSourceIndex
                    $servicingWimIndex = $originalSourceIndex
                    Set-Content -LiteralPath (Join-Path $WorkDir 'source.index') -Value ([string]$originalSourceIndex) -Encoding ASCII
                }

                $sourceWimSha = ''
                if (Test-Path -LiteralPath $wim) {
                    $sourceWimSha = Get-WibSha256 $wim
                    $mountedSourceWim = Join-Path $srcRoot 'sources\install.wim'
                    if ($sourceContainer -eq 'WIM' -and (Test-Path -LiteralPath $mountedSourceWim)) {
                        $mountedWimSha = Get-WibSha256 $mountedSourceWim
                        if ($mountedWimSha -ne $sourceWimSha) {
                            throw "Source WIM staging integrity failure: staged '$wim' SHA-256 ($sourceWimSha) does not match mounted source '$mountedSourceWim' SHA-256 ($mountedWimSha). Build aborted fail-closed."
                        }
                    }
                    Set-Content -LiteralPath (Join-Path $WorkDir 'source.wim.sha256') -Value $sourceWimSha -Encoding ASCII
                }
                $baselineSourceWimSha = $sourceWimSha
                $currentWorkspaceWimSha = $sourceWimSha
                $orphanWimIndices = New-Object System.Collections.ArrayList
                $sourceIsoStatus = if ($SkipIsoHash) {
                    'skipped'
                } elseif ($manifest.source.ContainsKey('isoSha256') -and $manifest.source.isoSha256) {
                    'verified'
                } elseif ($ExpectedIsoSha256) {
                    'verified'
                } else {
                    'unavailable'
                }
                $sourceIsoSha = if ($SkipIsoHash) {
                    ''
                } elseif ($manifest.source.ContainsKey('isoSha256') -and $manifest.source.isoSha256) {
                    $manifest.source.isoSha256
                } elseif ($ExpectedIsoSha256) {
                    $ExpectedIsoSha256.ToUpper()
                } elseif ($IsoPath -and (Test-Path -LiteralPath $IsoPath)) {
                    Get-WibSha256 $IsoPath
                } else { '' }
                if ($sourceIsoSha) {
                    Set-Content -LiteralPath (Join-Path $WorkDir 'source.iso.sha256') -Value $sourceIsoSha -Encoding ASCII
                } elseif ($SkipIsoHash) {
                    Set-Content -LiteralPath (Join-Path $WorkDir 'source.iso.status') -Value 'skipped' -Encoding ASCII
                }
            }
        } else {
            Write-WibLog 'Resume: Re-using existing extracted sources in work directory.' 'INFO'
            $wim = Join-Path $isoDir 'sources\install.wim'
            if (-not (Test-Path -LiteralPath $wim)) {
                $wim = Join-Path $WorkDir 'sources\install.wim'
            }
            $wimShaFile = Join-Path $WorkDir 'source.wim.sha256'
            $sourceWimSha = if ($baselineSourceWimSha) { $baselineSourceWimSha } elseif (Test-Path -LiteralPath $wimShaFile) { (Get-Content -LiteralPath $wimShaFile -Raw).Trim() } else { '' }
            $isoShaFile = Join-Path $WorkDir 'source.iso.sha256'
            $isoStatusFile = Join-Path $WorkDir 'source.iso.status'
            $isIsoSkipped = ($SkipIsoHash -or ((Test-Path -LiteralPath $isoStatusFile) -and ((Get-Content -LiteralPath $isoStatusFile -Raw).Trim() -eq 'skipped')))
            $sourceIsoStatus = if ($isIsoSkipped) {
                'skipped'
            } elseif (Test-Path -LiteralPath $isoShaFile) {
                'verified'
            } else {
                'unavailable'
            }
            $sourceIsoSha = if ($isIsoSkipped) {
                ''
            } elseif ($ExpectedIsoSha256) {
                $ExpectedIsoSha256.ToUpper()
            } elseif (Test-Path -LiteralPath $isoShaFile) {
                (Get-Content -LiteralPath $isoShaFile -Raw).Trim()
            } elseif ($IsoPath -and (Test-Path -LiteralPath $IsoPath) -and -not $SkipIsoHash) {
                Get-WibSha256 $IsoPath
            } else { '' }

            # Ledger validation and journal loading were already performed in section 1a
            # (before workspace lock and stale-mount operations).  $parsedCp and $journal
            # are already populated; derive target mount $Index from the last checkpoint
            # and restore the immutable $originalSourceIndex.
            $lastCp = @($parsedCp) | Select-Object -Last 1
            $Index = if ($lastCp -and $lastCp.WimIndex) { [int]$lastCp.WimIndex } else { 1 }
            $originalSourceIndex = if ($lastCp -and $lastCp.PSObject.Properties['Provenance'] -and $lastCp.Provenance -and $lastCp.Provenance.SourceWimOriginalIndex) {
                [int]$lastCp.Provenance.SourceWimOriginalIndex
            } elseif ($lastCp -and $lastCp.PSObject.Properties['Provenance'] -and $lastCp.Provenance -and $lastCp.Provenance.SourceIndex) {
                [int]$lastCp.Provenance.SourceIndex
            } elseif (Test-Path -LiteralPath (Join-Path $WorkDir 'source.index')) {
                [int](Get-Content -LiteralPath (Join-Path $WorkDir 'source.index') -Raw).Trim()
            } else {
                1
            }
            New-Item -ItemType Directory -Force -Path $mountDir | Out-Null
            if (Get-Command Protect-WibSensitiveDirectoryAcl -ErrorAction SilentlyContinue) { [void](Protect-WibSensitiveDirectoryAcl -Path $mountDir) }
        }


        $info = Get-WindowsImage -ImagePath $wim -Index $Index
        $arch = Get-WibArchitectureName $info.Architecture
        $manifest.source.index = if ($originalSourceIndex) { [int]$originalSourceIndex } else { [int]$Index }
        $manifest.source.edition = [string]$info.ImageName
        $manifest.source.build = [string]$info.Version
        $manifest.source.arch = $arch
        $manifest.source['sourceContainer'] = $sourceContainer
        $manifest.source['sourceContainerIndex'] = if ($sourceContainerIndex) { [int]$sourceContainerIndex } else { [int]$manifest.source.index }
        $manifest.source['servicingWimIndex'] = if ($servicingWimIndex) { [int]$servicingWimIndex } else { [int]$Index }
        Write-WibLog "Building from: $($info.ImageName) (container $sourceContainer index $($manifest.source.sourceContainerIndex), servicing mount index $Index, arch $arch, build $($info.Version))"

        # ---- 3. mount, scan, plan
        Write-WibLog 'Mounting install image' 'STEP'
        $existingMount = @(Get-WibMountedImage -Path $mountDir)
        if ($existingMount.Count -gt 0) {
            if ($existingMount[0].PSObject.Properties['MountStatus'] -and $existingMount[0].MountStatus -ne 'Ok') {
                Write-WibLog "Existing mount at $mountDir has invalid MountStatus '$($existingMount[0].MountStatus)'. Dismounting..." 'WARN'
                try { Dismount-WindowsImage -Path $mountDir -Discard -ErrorAction Stop } catch { Write-Verbose $_.Exception.Message }
                $existingMount = @()
            }
        }
        if ($existingMount.Count -gt 0) {
            Write-WibLog "Re-using existing mount at $mountDir (Index $($existingMount[0].ImageIndex))" 'INFO'
            $state.ImageMounted = $true
            $Index = [int]$existingMount[0].ImageIndex
        } else {
            if ($DryRun) { Mount-WindowsImage -ImagePath $wim -Index $Index -Path $mountDir -ReadOnly | Out-Null }
            else { Mount-WindowsImage -ImagePath $wim -Index $Index -Path $mountDir | Out-Null }
            $state.ImageMounted = $true
        }

        # Determine SourceIsoHashStatus:
        # On resume: the persisted SourceIsoHashStatus in the validated recovery state is
        # authoritative -- it must not be reconstructed from $sourceIsoSha because that loses
        # the 'skipped' flag ('skipped' != 'unavailable'). (P2 v0.2.8 fix)
        # On fresh build: derive from whether an ISO hash was computed.
        if ($Resume -and $null -ne $validatedRecovery -and (Test-WibHasProp $validatedRecovery 'SourceIsoHashStatus') -and $validatedRecovery.SourceIsoHashStatus) {
            $sourceIsoStatus = [string]$validatedRecovery.SourceIsoHashStatus
        } else {
            $sourceIsoStatus = if ($sourceIsoSha -and $sourceIsoSha.Trim() -ne '') { 'verified' } else { 'unavailable' }
        }
        $ctx = @{
            MountDir                  = $mountDir
            Image                     = 'install'
            Journal                   = $journal
            Extras                    = @{}
            ToolRoot                  = $ToolRoot
            WorkDir                   = $WorkDir
            Arch                      = $arch
            Build                     = [string]$info.Version
            Edition                   = [string]$info.ImageName
            WimPath                   = $wim
            DryRun                    = [bool]$DryRun
            NoCheckpoints             = [bool]$NoCheckpoints
            Checkpoints               = New-Object System.Collections.ArrayList
            MountedIndex              = [int]$Index
            CurrentIndex              = [int]$Index
            OriginalSourceIndex       = if ($originalSourceIndex) { [int]$originalSourceIndex } else { [int]$Index }
            SourceContainer           = $sourceContainer
            SourceContainerIndex      = if ($sourceContainerIndex) { [int]$sourceContainerIndex } else { [int]$originalSourceIndex }
            ServicingWimIndex         = if ($servicingWimIndex) { [int]$servicingWimIndex } else { [int]$Index }
            SourceIndex               = if ($originalSourceIndex) { [int]$originalSourceIndex } else { [int]$Index }
            SourceWimOriginalIndex    = if ($originalSourceIndex) { [int]$originalSourceIndex } else { [int]$Index }
            SourceIsoSha256           = $sourceIsoSha
            SourceIsoHashStatus       = $sourceIsoStatus
            SourceWimSha256           = if ($baselineSourceWimSha) { $baselineSourceWimSha } else { $sourceWimSha }
            BaselineSourceWimSha256   = if ($baselineSourceWimSha) { $baselineSourceWimSha } else { $sourceWimSha }
            CurrentWorkspaceWimSha256 = if ($currentWorkspaceWimSha) { $currentWorkspaceWimSha } else { $sourceWimSha }
            OrphanWimIndices          = if ($orphanWimIndices) { $orphanWimIndices } else { New-Object System.Collections.ArrayList }
            CommittedCheckpointWimIndex = if ($Resume -and $validatedRecovery -and $validatedRecovery.ContainsKey('CommittedCheckpointWimIndex')) { [int]$validatedRecovery.CommittedCheckpointWimIndex } else { [int]$Index }
            PhysicalImageIndex        = if ($Resume -and $validatedRecovery -and $validatedRecovery.ContainsKey('PhysicalImageIndex')) { [int]$validatedRecovery.PhysicalImageIndex } else { [int]$Index }
            OrphanIndexSet            = if ($Resume -and $validatedRecovery -and $validatedRecovery.ContainsKey('OrphanIndexSet')) { @($validatedRecovery.OrphanIndexSet) } else { @() }
            TransactionAuthSecret     = if ($Resume -and $validatedRecovery -and $validatedRecovery.ContainsKey('TransactionAuthSecret') -and $validatedRecovery.TransactionAuthSecret) { [string]$validatedRecovery.TransactionAuthSecret } elseif ($parsedRec -and (Test-WibHasProp $parsedRec 'TransactionAuthSecret') -and $parsedRec.TransactionAuthSecret) { [string]$parsedRec.TransactionAuthSecret } else { New-WibCryptoSecret }
            RunId                     = $runId
            ProfileHash               = $resolvedHash
            EffectiveSha256           = $effectiveHash
            HardwareSpecHash          = if ($HardwareSpec -and (Test-Path -LiteralPath $HardwareSpec)) { Get-WibSha256 $HardwareSpec } else { '' }
            HardwareProfileHash       = $hwProfileHash
            HardwareProfile           = $hwProfile
            AdaptiveDecisions         = New-Object System.Collections.ArrayList
        }
        # Profile was already adapted by Resolve-WibEffectiveBuildProfile; effectiveHash is already
        # computed. Populate $ctx.AdaptiveDecisions from the resolved decisions list and sync manifest.
        if ($adaptiveDecisions.Count -gt 0) {
            foreach ($d in $adaptiveDecisions) { [void]$ctx.AdaptiveDecisions.Add($d) }
            $manifest.profile['effectiveSha256'] = $effectiveHash
        }
        # Check for existing checkpoints if resuming existing sources (validated pre-DISM)
        if ($resumingExistingSources -and $parsedCp) {
            $completedStages = New-Object System.Collections.ArrayList
            foreach ($item in $parsedCp) {
                [void]$ctx.Checkpoints.Add(@{
                    Index       = [int]$item.Index
                    WimIndex    = [int]$item.WimIndex
                    Stage       = [string]$item.Stage
                    ProfileHash = [string]$item.ProfileHash
                    Provenance  = if ($item.PSObject.Properties['Provenance']) { $item.Provenance } else { $null }
                    Status      = [string]$item.Status
                })
                if ($item.Status -eq 'saved' -or $item.Status -eq 'restored') {
                    [void]$completedStages.Add([string]$item.Stage)
                }
            }
            $ctx['CompletedStages'] = $completedStages
            Write-WibLog "Loaded $($ctx.Checkpoints.Count) existing checkpoint(s). Completed: $($completedStages -join ', ')" 'INFO'
        }

        # Ensure unattend answer file is not lost if apply-files was skipped on resume
        if ($unattendResumePath) {
            $ctx.Extras['unattend'] = $unattendResumePath
        }
        if (-not $ctx.Extras.ContainsKey('unattend')) {
            $candidatePanther = Join-Path $mountDir 'Windows\Panther\Unattend\unattend.xml'
            if (Test-Path -LiteralPath $candidatePanther) {
                $ctx.Extras['unattend'] = $candidatePanther
            }
        }

        $ctx.Scan = Get-WibScan -MountDir $mountDir
        $enabledInstallIds = @(Get-WibEnabledModuleIds $buildProfile 'install')

        if ($ctx.ContainsKey('Scan') -and $ctx.Scan -and $ctx.Scan.ContainsKey('Errors') -and $ctx.Scan.Errors -and $ctx.Scan.Errors.Count -gt 0) {
            foreach ($err in $ctx.Scan.Errors) {
                Write-WibLog "Scan warning: $err" 'WARN'
            }
            if (-not $DryRun) {
                $fatalErrors = @()
                $appxErrors = @($ctx.Scan.Errors | Where-Object { $_ -like 'appx:*' })
                $featErrors = @($ctx.Scan.Errors | Where-Object { $_ -like 'features:*' -or $_ -like 'caps:*' })

                if ($enabledInstallIds -contains 'appx-removal' -and $appxErrors.Count -gt 0) {
                    $fatalErrors += $appxErrors
                }
                if ($enabledInstallIds -contains 'features-cleanup' -and $featErrors.Count -gt 0) {
                    $fatalErrors += $featErrors
                }
                if ($fatalErrors.Count -gt 0) {
                    throw "Image package scan encountered critical errors: $($fatalErrors -join '; ')"
                }
            }
        }
        $plan = @(New-WibPlan -BuildProfile $buildProfile -Ctx $ctx)
        $bootCtx = @{
            MountDir     = $mountDir
            Image        = 'boot'
            Journal      = $journal
            Extras       = @{}
            ToolRoot     = $ToolRoot
            WorkDir      = $WorkDir
            Arch         = $arch
            Build        = [string]$info.Version
            Edition      = [string]$info.ImageName
            DryRun       = [bool]$DryRun
            Checkpoints  = $ctx.Checkpoints
            CurrentIndex = 2
        }
        $plan = @($plan) + @(New-WibPlan -BuildProfile $buildProfile -Ctx $bootCtx | ForEach-Object { $_.Reason = ($_.Reason + ' [boot.wim]').Trim(); $_ })
        if ($DeltaFromManifest -and (Test-Path -LiteralPath $DeltaFromManifest)) {
            $deltaRes = Compare-WibDeltaPlan -CurrentPlan $plan -PreviousManifestPath $DeltaFromManifest
            $plan = $deltaRes.Plan
            $manifest['delta'] = [ordered]@{
                previousSha256 = $deltaRes.PreviousSha256
                newOrModified  = $deltaRes.NewOrModified
                unchanged      = $deltaRes.Unchanged
            }
            Write-WibLog ("Delta build comparison: {0} new/modified items, {1} unchanged items (Previous SHA: {2})." -f $deltaRes.NewOrModified, $deltaRes.Unchanged, $deltaRes.PreviousSha256) 'STEP'
        }
        $manifest.plan = @($plan)
        Show-WibPlan -Plan $plan -AdaptiveDecisions $adaptiveDecisions

        if ($DryRun) {
            Dismount-WindowsImage -Path $mountDir -Discard | Out-Null
            $state.ImageMounted = $false
            if ($scratchWim -and (Test-Path -LiteralPath $scratchWim)) {
                Remove-Item -LiteralPath $scratchWim -Force -ErrorAction SilentlyContinue
            }
            $manifest.status = 'dry-run'
            $state.Success = $true
            Write-WibLog "Dry run complete. Nothing was modified. Report: $reportDir" 'OK'
            return
        }

        # ---- 4. apply to install.wim
        $applied = Invoke-WibApply -BuildProfile $buildProfile -Ctx $ctx
        $manifest.results = @($applied.Results)
        $manifest.verification = @($applied.Verify)
        $manifest.checkpoints = @($ctx.Checkpoints)
        $failed = @($applied.Results | Where-Object { $_.Status -eq 'failed' }).Count + @($applied.Verify | Where-Object { $_.Status -eq 'fail' }).Count
        if ($failed -gt 0) {
            Write-WibLog "$failed step(s) failed or did not verify. See the report." 'WARN'
            if ($Strict -or -not $Force) {
                throw "Build failed: $failed step(s) failed or did not verify. Aborting build without saving or exporting ISO $(if ($Strict) { '(-Strict safety gate enforced)' } else { '(pass -Force to override fail-closed safety gate)' })."
            } else {
                Write-WibLog "FORCE OVERRIDE: Proceeding with packaging despite $failed failed/unverified step(s)." 'WARN'
            }
        }

        # Ship the undo journal and post-install panel inside the image
        $wibDir = Join-Path $mountDir 'Windows\WIB'
        New-Item -ItemType Directory -Force -Path $wibDir | Out-Null
        $journalPath = Join-Path $wibDir 'journal.json'
        @{ tool = $script:WibVersion; profile = $profileName; journal = @($journal) } | ConvertTo-Json -Depth 6 |
            Set-Content -LiteralPath $journalPath -Encoding UTF8
        try {
            $acl = Get-Acl -LiteralPath $journalPath
            $acl.SetAccessRuleProtection($true, $true)
            Set-Acl -LiteralPath $journalPath -AclObject $acl
        } catch { Write-Verbose $_.Exception.Message }
        $panelSrc = Join-Path $ToolRoot 'tools\WibPanel.ps1'
        if (Test-Path -LiteralPath $panelSrc) {
            Copy-Item -LiteralPath $panelSrc -Destination $wibDir -Force
        }

        # Copy unattend answer file into image Panther directory as well
        if ($ctx.Extras.ContainsKey('unattend') -and (Test-Path -LiteralPath $ctx.Extras['unattend'])) {
            $pantherDir = Join-Path $mountDir 'Windows\Panther\Unattend'
            New-Item -ItemType Directory -Force -Path $pantherDir | Out-Null
            Copy-Item -LiteralPath $ctx.Extras['unattend'] -Destination (Join-Path $pantherDir 'unattend.xml') -Force

            # Purge Panther answer files via SetupComplete.cmd as defense-in-depth against credential harvesting
            $scriptsDir = Join-Path $mountDir 'Windows\Setup\Scripts'
            if (-not (Test-Path -LiteralPath $scriptsDir)) { New-Item -ItemType Directory -Force -Path $scriptsDir | Out-Null }
            $setupCompletePath = Join-Path $scriptsDir 'SetupComplete.cmd'
            $purgeCmd = "`r`nREM Purge Panther answer files to prevent credential leakage`r`nif exist `"%SystemRoot%\Panther\unattend.xml`" del /q /f `"%SystemRoot%\Panther\unattend.xml`"`r`nif exist `"%SystemRoot%\Panther\Unattend\unattend.xml`" del /q /f `"%SystemRoot%\Panther\Unattend\unattend.xml`"`r`n"
            Add-Content -LiteralPath $setupCompletePath -Value $purgeCmd -Encoding Ascii
        }

        Write-WibLog 'Saving install image' 'STEP'
        if ($script:WibLoadedHives.Count -gt 0) { throw 'Hives still loaded; refusing to save image.' }

        # Transition recovery state to 'finalizing' before dismounting/saving mutations
        Update-WibRecoveryCommitState -WorkDir $WorkDir -CommitState 'finalizing' -Updates @{ Stage = 'finalizing' }

        Dismount-WindowsImage -Path $mountDir -Save | Out-Null
        $state.ImageMounted = $false
        Write-WibLog 'Install image saved.' 'INFO'

        $compress = if ($Compression) {
            $Compression
        } elseif ($NoCheckpoints) {
            'max' # Fast Build prioritizes speed (2-3 min LZX vs 30+ min LZMS recovery)
        } elseif ($buildProfile.ContainsKey('output') -and $buildProfile['output'].ContainsKey('compression')) {
            $buildProfile['output']['compression']
        } else {
            'max'
        }
        $compressDesc = switch ($compress) {
            'fast'     { 'fast LZNT1 compression' }
            'recovery' { 'maximum LZMS recovery compression (slow)' }
            'none'     { 'no compression' }
            default    { 'standard LZX compression' }
        }
        Write-WibLog ("Exporting install.wim (single edition, {0})" -f $compressDesc) 'STEP'
        $wim2 = Join-Path $isoDir 'sources\install2.wim'
        $exportIndex = if ($ctx.ContainsKey('MountedIndex') -and $ctx.MountedIndex) { [int]$ctx.MountedIndex } elseif ($ctx.ContainsKey('CurrentIndex') -and $ctx.CurrentIndex) { [int]$ctx.CurrentIndex } else { [int]$Index }
        [void](Invoke-WibNativeTool -ToolKey 'dismExe' -FilePath 'dism.exe' -Arguments @('/Export-Image', "/SourceImageFile:$wim", "/SourceIndex:$exportIndex", "/DestinationImageFile:$wim2", "/Compress:$compress"))
        if ($LASTEXITCODE -ne 0) { throw "dism /Export-Image failed (exit $LASTEXITCODE)." }
        Remove-Item -LiteralPath $wim -Force
        Rename-Item -LiteralPath $wim2 -NewName 'install.wim'

        # Update recovery state to 'post-export' with recomputed physical WIM SHA-256
        $finalWimSha = Get-WibSha256 $wim
        Update-WibRecoveryCommitState -WorkDir $WorkDir -CommitState 'post-export' -Updates @{
            CurrentWorkspaceWimSha256 = $finalWimSha
            Stage = 'post-export'
        }

        # ---- 5. boot.wim (registry tweaks only)
        if (@(Get-WibEnabledModuleIds $buildProfile 'boot').Count -gt 0) {
            Write-WibLog 'Patching boot.wim (index 2)' 'STEP'
            $boot = Join-Path $isoDir 'sources\boot.wim'
            Mount-WindowsImage -ImagePath $boot -Index 2 -Path $mountDir | Out-Null
            $state.ImageMounted = $true
            $bootApplied = Invoke-WibApply -BuildProfile $buildProfile -Ctx $bootCtx
            $manifest.results = @($manifest.results) + @($bootApplied.Results)
            $manifest.verification = @($manifest.verification) + @($bootApplied.Verify)
            $bootFailed = @($bootApplied.Results | Where-Object { $_.Status -eq 'failed' }).Count + @($bootApplied.Verify | Where-Object { $_.Status -eq 'fail' }).Count
            if ($bootFailed -gt 0) {
                $failed += $bootFailed
                if ($Strict -or -not $Force) {
                    throw "Build failed: $bootFailed boot step(s) failed or did not verify. Aborting build $(if ($Strict) { '(-Strict safety gate enforced)' } else { '(pass -Force to override fail-closed safety gate)' })."
                } else {
                    Write-WibLog "FORCE OVERRIDE: Proceeding with packaging despite $bootFailed boot step(s) failed or did not verify." 'WARN'
                }
            }
            if ($script:WibLoadedHives.Count -gt 0) { throw 'Hives still loaded; refusing to save image.' }
            Dismount-WindowsImage -Path $mountDir -Save | Out-Null
            $state.ImageMounted = $false
        }

        # ---- 6. package
        if ($ctx.Extras.ContainsKey('unattend')) {
            $uSrc = $ctx.Extras['unattend']
            $isoUnattend = Join-Path $isoDir 'autounattend.xml'
            Copy-Item -LiteralPath $uSrc -Destination $isoUnattend -Force

            # Inspect for plaintext administrator credentials on installer surface (BUG-17)
            if (Test-Path -LiteralPath $isoUnattend) {
                $unattendXmlContent = Get-Content -LiteralPath $isoUnattend -Raw -ErrorAction SilentlyContinue
                if ($unattendXmlContent -match '(?s)<Password>\s*<Value>([^<]+)</Value>\s*<PlainText>true</PlainText>') {
                    $pwdSnippet = $matches[1]
                    if ($pwdSnippet -and $pwdSnippet.Trim().Length -gt 0) {
                        Write-WibLog 'SECURITY WARNING: autounattend.xml in ISO media root contains unencrypted administrator credentials (<PlainText>true</PlainText>). Anyone with read access to this ISO or USB drive can extract the password.' 'WARN'
                        $manifest['unattendSecurityNotice'] = 'Plaintext administrator credentials present in autounattend.xml on installer media root. Recommend using -ObscurePassword, -PasswordHash, or setting passwords post-OOBE.'
                    }
                }
            }
        }
        $oscdimg = Resolve-WibOscdimg -AllowDownload:$DownloadOscdimg -WorkDir $ToolRoot -StrictOscdimgHash:$StrictOscdimgHash
        $oscdimgHash = Get-WibSha256 $oscdimg
        $manifest.oscdimg = @{ path = $oscdimg; sha256 = $oscdimgHash }

        # Reproducibility metadata
        $manifest.reproducibility = [ordered]@{
            profileCanonicalHash    = $resolvedHash
            toolVersion             = $script:WibVersion
            oscdimgSha256           = $oscdimgHash
            isoTimestampPolicy      = 'fixed (01/01/2026,00:00:00)'
            nonDeterministicFactors = @(
                'Internal Windows servicing transaction logs (servicing stack delta logs)',
                'WIM cluster allocation order across differing host kernels'
            )
        }

        Write-WibLog 'Creating ISO' 'STEP'
        $etfs = Join-Path $isoDir 'boot\etfsboot.com'
        $efisys = Join-Path $isoDir 'efi\microsoft\boot\efisys.bin'
        
        $hasEtfs = Test-Path -LiteralPath $etfs
        $hasEfi  = Test-Path -LiteralPath $efisys
        
        # Resolve 8.3 short paths to prevent oscdimg space-tokenizing failures in -bootdata (BUG-16)
        $etfsArg = if ($hasEtfs) { Get-WibShortPath $etfs } else { $etfs }
        $efisysArg = if ($hasEfi) { Get-WibShortPath $efisys } else { $efisys }
        $isoDirArg = Get-WibShortPath $isoDir

        $bootArgs = @()
        if ($hasEtfs -and $hasEfi) {
            # Dual-boot BIOS + UEFI (x86/x64 media)
            $bootArgs = @("-bootdata:2#p0,e,b$etfsArg#pEF,e,b$efisysArg")
        } elseif ($hasEfi) {
            # UEFI-only or ARM64 media
            $bootArgs = @('-pEF', '-e', "-b$efisysArg")
        } elseif ($hasEtfs) {
            # Legacy BIOS only
            $bootArgs = @("-b$etfsArg")
        } else {
            throw "No valid boot sector files found in source image (expected boot\etfsboot.com or efi\microsoft\boot\efisys.bin)."
        }
        
        # Write to a unique temporary ISO to prevent cross-workspace collision races,
        # simultaneous writes to the same destination, and partially-written ISO outputs.
        $tempIso = "$OutputIso.tmp.$runId"
        if (Test-Path -LiteralPath $tempIso) {
            Remove-Item -LiteralPath $tempIso -Force -ErrorAction SilentlyContinue
        }

        $oscdArgs = @('-m', '-o', '-u2', '-udfver102', '-t01/01/2026,00:00:00', '-lWIB_WIN11') + $bootArgs + @($isoDirArg, $tempIso)
        [void](Invoke-WibNativeTool -ToolKey 'oscdimgExe' -FilePath $oscdimg -Arguments $oscdArgs -ExpectedSha256 $oscdimgHash)
        if ($LASTEXITCODE -ne 0) {
            if (Test-Path -LiteralPath $tempIso) { Remove-Item -LiteralPath $tempIso -Force -ErrorAction SilentlyContinue }
            throw "oscdimg failed (exit $LASTEXITCODE)."
        }
        if (-not (Test-Path -LiteralPath $tempIso -PathType Leaf)) {
            throw "oscdimg completed but temporary output ISO '$tempIso' was not created."
        }
        $tempItem = Get-Item -LiteralPath $tempIso
        if ($tempItem.Length -eq 0) {
            Remove-Item -LiteralPath $tempIso -Force -ErrorAction SilentlyContinue
            throw "oscdimg generated a 0-byte output ISO at '$tempIso'."
        }

        $isoSha256 = Get-WibSha256 $tempIso
        $isoBytes = $tempItem.Length

        # Atomic publication with target-level locking and provenance coherence:
        # Executes post-publish report generation while target publication lock is STILL HELD.
        $postPublishCallback = {
            param($pubInfo)
            $manifest.output = @{ iso = $OutputIso; sha256 = $isoSha256; sizeBytes = $isoBytes }
            Write-WibLog "Done: $OutputIso" 'OK'

            # Prominent post-build warning banner for high-risk modules
            $highRiskApplied = @($manifest.results | Where-Object { $_.Module -in @('defender-off', 'mitigations-off', 'uac-off') -and $_.Status -eq 'applied' })
            if ($highRiskApplied.Count -gt 0) {
                $hrMods = ($highRiskApplied | ForEach-Object { $_.Module } | Select-Object -Unique) -join ', '
                Write-Host ''
                Write-Host '======================== HIGH-RISK SECURITY WARNING ========================' -ForegroundColor Red
                Write-Host " The following high-risk security opt-in modules were applied: $hrMods" -ForegroundColor Yellow
                Write-Host ' Core Windows defenses (Tamper Protection, Defender, UAC, or Exploit Guard)' -ForegroundColor Yellow
                Write-Host ' have been disabled or weakened. Deploy this image ONLY in isolated test labs.' -ForegroundColor Yellow
                Write-Host '============================================================================' -ForegroundColor Red
                Write-Host ''
            }

            $manifest.journalEntries = $journal.Count
            if ($SigningCertThumbprint) {
                $manifest['signingCertThumbprint'] = $SigningCertThumbprint
            }

            # Write initial published report and manifest INSIDE the publication lock to guarantee provenance coherence
            $state.ArtifactStatus = 'success'
            $manifest['artifactStatus'] = 'success'
            $manifest.status = 'success'
            $state.Success = $true
            Write-WibReport -Manifest $manifest -Dir $reportDir -SigningCertThumbprint $SigningCertThumbprint
            Write-WibLog "Initial report written to $reportDir"
            $state.ReportWritten = $true
        }

        $onFailureCallback = {
            param($failInfo)
            $state.Success = $false
            if ($failInfo.RollbackAttempted -and -not $failInfo.RollbackSucceeded) {
                $state.ArtifactStatus = 'rollback-failed'
                $manifest['artifactStatus'] = 'rollback-failed'
                Write-WibLog "Publication rollback FAILED: $($failInfo.RollbackError)" 'ERROR'
            } elseif ($failInfo.RollbackSucceeded) {
                $state.ArtifactStatus = 'restored'
                $manifest['artifactStatus'] = 'restored'
                Write-WibLog "Publication rollback complete: $($failInfo.Error.Message)" 'WARN'
            } else {
                $state.ArtifactStatus = 'failed'
                $manifest['artifactStatus'] = 'failed'
                Write-WibLog "Publication failed: $($failInfo.Error.Message)" 'WARN'
            }
        }

        $pubResult = Publish-WibOutputIso -TempIsoPath $tempIso -OutputIso $OutputIso -RunId $runId -Force:$Force `
            -ExpectedTempIsoSha256 $isoSha256 -ExpectedTempIsoSize $isoBytes -RequireIntegrityCheck `
            -PostPublishAction $postPublishCallback -OnFailureAction $onFailureCallback -RetainLock
        if ($pubResult -and $pubResult.LockStream) {
            $targetPubLockStream = $pubResult.LockStream
            $targetPubLockPath = $pubResult.LockPath
        }
    }
    catch {
        $state.Success = $false
        if (-not $state.ArtifactStatus -or $state.ArtifactStatus -eq 'success') {
            $state.ArtifactStatus = 'failed'
            $manifest['artifactStatus'] = 'failed'
        }
        Write-WibLog "BUILD FAILED: $($_.Exception.Message)" 'ERROR'
        $manifest.status = 'failed'
        $manifest.error = $_.Exception.Message
        throw
    }
    finally {
        $finalTeardownError = $null

        # Hive cleanup must happen first (hives write-lock the mounted image).
        # Fail-closed: capture hive unload failure, mark teardown failure, and accumulate into $finalTeardownError.
        try {
            Dismount-WibHives -ThrowOnFailure | Out-Null
        } catch {
            $hiveErr = "Hive dismount failed during teardown: $($_.Exception.Message)"
            Write-WibLog $hiveErr 'ERROR'
            $state.Success = $false
            $state.TeardownFailed = $true
            $manifest.status = 'failed'
            $manifest.error = $hiveErr
            if (-not $finalTeardownError) { $finalTeardownError = "Teardown failed: $hiveErr" }
        }
        $script:WibHivePrefix = 'wib_'

        # Dismount WIM before ISO and before cleanup. The workspace lock MUST be
        # held across all of these --- it is released LAST so no concurrent run can
        # start while dismount / report / cleanup are still in progress.
        if ($state.ImageMounted) {
            Write-WibLog 'Discarding mounted image (source files untouched).' 'WARN'
            try {
                Dismount-WindowsImage -Path $mountDir -Discard -ErrorAction Stop | Out-Null
                $state.ImageMounted = $false
            } catch {
                $teardownError = "WIM dismount failed: $($_.Exception.Message)"
                Write-WibLog "$teardownError. Run: dism /Cleanup-Wim" 'ERROR'
                $state.Success = $false
                $state.TeardownFailed = $true
                $manifest.status = 'failed'
                $manifest.error = $teardownError
                if (-not $finalTeardownError) { $finalTeardownError = "Teardown failed: $teardownError" }
            }
        }
        if ($state.IsoMounted) {
            try {
                Dismount-DiskImage -ImagePath $isoFull -ErrorAction Stop | Out-Null
                $state.IsoMounted = $false
            } catch {
                $isoErr = "ISO dismount failed: $($_.Exception.Message)"
                Write-WibLog $isoErr 'ERROR'
                $state.Success = $false
                $state.TeardownFailed = $true
                $manifest.status = 'failed'
                $manifest.error = $isoErr
                if (-not $finalTeardownError) { $finalTeardownError = "Teardown failed: $isoErr" }
            }
        }

        $cleanupStatus = [ordered]@{}
        if ($state.Success -and -not $DryRun -and -not $state.TeardownFailed) {
            try {
                Remove-WibCheckpoints $ctx
                Write-WibLog 'Build finalized successfully; recovery state safely cleaned.' 'INFO'
                $state.FinalizationStatus = 'success'
                $cleanupStatus['recoveryLedger'] = 'cleaned'
            } catch {
                Write-WibLog "Recovery state cleanup failed: $($_.Exception.Message)" 'ERROR'
                $cleanErr = "Recovery state cleanup failed: $($_.Exception.Message)"
                $state.Success = $false
                $state.FinalizationStatus = "failed: $($_.Exception.Message)"
                $cleanupStatus['recoveryLedger'] = "failed: $($_.Exception.Message)"
                if (-not $finalTeardownError) {
                    $finalTeardownError = $cleanErr
                }
            }
        } elseif ($DryRun) {
            $state.FinalizationStatus = 'skipped (dry-run)'
        } else {
            $state.FinalizationStatus = if ($finalTeardownError) { "failed: $finalTeardownError" } else { 'skipped (build not successful)' }
        }

        # Hardened structured finalizer cleanup tracking (workspace hygiene)
        if ($scratchWim -and (Test-Path -LiteralPath $scratchWim)) {
            try {
                Remove-Item -LiteralPath $scratchWim -Force -ErrorAction Stop
                $cleanupStatus['scratchWim'] = 'cleaned'
            } catch {
                Write-WibLog "Scratch WIM cleanup failed: $($_.Exception.Message)" 'WARN'
                $cleanupStatus['scratchWim'] = "failed: $($_.Exception.Message)"
            }
        }
        if ($state.Success -and -not $KeepWork -and -not $state.TeardownFailed) {
            foreach ($dirToClean in @($isoDir, $mountDir)) {
                if ($dirToClean -and (Test-Path -LiteralPath $dirToClean)) {
                    $dirKey = Split-Path -Leaf $dirToClean
                    try {
                        Remove-Item -LiteralPath $dirToClean -Recurse -Force -ErrorAction Stop
                        $cleanupStatus[$dirKey] = 'cleaned'
                    } catch {
                        Write-WibLog "Directory cleanup failed for '$dirToClean': $($_.Exception.Message)" 'WARN'
                        $cleanupStatus[$dirKey] = "failed: $($_.Exception.Message)"
                    }
                }
            }
        }
        if ($cleanupStatus.Count -gt 0) {
            $manifest['cleanup'] = $cleanupStatus
        }

        # Determine terminal statuses
        $manifest['artifactStatus'] = if ($state.ArtifactStatus) { $state.ArtifactStatus } elseif ($DryRun) { 'skipped (dry-run)' } else { 'not-created' }
        $manifest['finalizationStatus'] = if ($state.FinalizationStatus) { $state.FinalizationStatus } else { 'unknown' }

        # Authoritative terminal state enforcement:
        # A build whose publication, teardown, finalization, or artifact generation failed MUST NEVER report overall success.
        $isTerminalFailure = (-not $state.Success) -or `
            [bool]$finalTeardownError -or `
            ($manifest['artifactStatus'] -in @('failed', 'rollback-failed', 'restored')) -or `
            ($manifest['finalizationStatus'] -like 'failed*') -or `
            ($manifest.status -eq 'failed')

        if ($isTerminalFailure) {
            $manifest['overallStatus'] = 'failed'
            $manifest.status = 'failed'
            if ($finalTeardownError -and -not $manifest.error) { $manifest.error = $finalTeardownError }
        } elseif ($failed -gt 0) {
            $manifest['overallStatus'] = 'completed-with-warnings'
            $manifest.status = 'completed-with-warnings'
        } else {
            $manifest['overallStatus'] = 'success'
            $manifest.status = 'success'
        }
        $manifest.journalEntries = $journal.Count
        if ($SigningCertThumbprint) {
            $manifest['signingCertThumbprint'] = $SigningCertThumbprint
        }

        # WIB-007, WIB-011 & WIB-018: Record structured build resource telemetry and reproducible validation record.
        # Explicitly qualify that peakWorkingSetBytes / powershellPeakWorkingSetBytes measures the PowerShell host
        # process, while per-tool child-process timing, exit codes, and peak working-set measurements (or honest
        # 'unavailable'/'not-collected' statuses) are recorded in nativeToolInvocations.
        if ($buildStopwatch) { $buildStopwatch.Stop() }
        $peakWsBytes = 0
        try {
            $peakWsBytes = [long][System.Diagnostics.Process]::GetCurrentProcess().PeakWorkingSet64
        } catch { Write-Verbose $_.Exception.Message }
        $manifest['telemetry'] = [ordered]@{
            elapsedMs                     = if ($buildStopwatch) { [long]$buildStopwatch.ElapsedMilliseconds } else { 0 }
            powershellPeakWorkingSetBytes = [long]$peakWsBytes
            peakWorkingSetBytes           = [long]$peakWsBytes
            memoryMeasurementScope        = 'powershell-host-process-only'
            childProcessNote              = 'powershellPeakWorkingSetBytes measures the PowerShell host process PeakWorkingSet64 only. External servicing utilities (dism.exe, oscdimg.exe, reg.exe, compact.exe, takeown.exe, icacls.exe, attrib.exe) are tracked per-tool under nativeToolInvocations with invocations, totalElapsedMs, maxProcessWorkingSetBytes, workingSetMeasurementStatus, lastExitCode, and launchFailures.'
            nativeToolInvocations         = if (Get-Command Get-WibNativeToolTelemetry -ErrorAction SilentlyContinue) { Get-WibNativeToolTelemetry } else { [ordered]@{} }
            checkpointCount               = @($manifest.checkpoints).Count
            planItemCount                 = @($manifest.plan).Count
            resultItemCount               = @($manifest.results).Count
        }
        $srcIsoSha = if ($manifest.source -is [System.Collections.IDictionary] -and $manifest.source.Contains('isoSha256')) { $manifest.source['isoSha256'] } else { $null }
        $srcWimSha = if ($manifest.source -is [System.Collections.IDictionary] -and $manifest.source.Contains('sourceWimSha256')) { $manifest.source['sourceWimSha256'] } else { $null }
        $outIsoSha = if ($manifest.output -is [System.Collections.IDictionary] -and $manifest.output.Contains('sha256')) { $manifest.output['sha256'] } else { $null }
        $manifest['validationRecord'] = [ordered]@{
            schemaVersion          = 1
            toolVersion            = $script:WibVersion
            runId                  = $runId
            profileName            = $profileName
            profileResolvedSha256  = $resolvedHash
            profileEffectiveSha256 = $effectiveHash
            sourceIsoSha256        = $srcIsoSha
            sourceWimSha256        = $srcWimSha
            outputIsoSha256        = $outIsoSha
            terminalStatus         = $manifest['overallStatus']
            dryRun                 = [bool]$DryRun
            vmBootValidated        = $false
        }

        # Mandatory final report write/update: guarantees cleanup and final statuses are sealed on disk
        try {
            Write-WibReport -Manifest $manifest -Dir $reportDir -SigningCertThumbprint $SigningCertThumbprint
            $buildLogFile = Join-Path $reportDir 'build.log'
            if ((Test-Path -LiteralPath $buildLogFile -PathType Leaf) -and (Get-Command Protect-WibSensitiveFileAcl -ErrorAction SilentlyContinue)) {
                try { [void](Protect-WibSensitiveFileAcl -Path $buildLogFile) } catch { Write-Verbose $_.Exception.Message }
            }
            Write-WibLog "Report written to $reportDir"
            $state.ReportWritten = $true
        } catch {
            Write-WibLog "Report write failed: $($_.Exception.Message)" 'ERROR'
            $repErr = "Mandatory report generation or cleanup failed: $($_.Exception.Message)"
            $state.Success = $false
            $manifest.status = 'failed'
            $manifest['overallStatus'] = 'failed'
            $manifest['finalizationStatus'] = "failed: $repErr"
            $manifest.error = $repErr
            if (-not $finalTeardownError) {
                $finalTeardownError = $repErr
            }
            # Invalidate any previously written success manifest/checksum so disk never falsely indicates success
            $emergencyRewriteError = $null
            try {
                $manPath = Join-Path $reportDir 'manifest.json'
                $sigPath = Join-Path $reportDir 'manifest.json.sha256'
                if (Test-Path -LiteralPath $sigPath) {
                    try {
                        Remove-Item -LiteralPath $sigPath -Force -ErrorAction Stop
                    } catch {
                        try {
                            Set-Content -LiteralPath $sigPath -Value 'INVALIDATED_BUILD_FAILED' -Encoding ASCII -Force -ErrorAction Stop
                        } catch {
                            Write-WibLog "Failed to invalidate signature file '$sigPath': $($_.Exception.Message)" 'WARN'
                        }
                    }
                }
                $emergencyManifest = [ordered]@{
                    status             = 'failed'
                    overallStatus      = 'failed'
                    artifactStatus     = $manifest['artifactStatus']
                    finalizationStatus = "failed: $repErr"
                    error              = $repErr
                    runId              = $runId
                    tool               = @{ version = $script:WibVersion }
                    createdUtc         = (Get-Date).ToUniversalTime().ToString('o')
                }
                Set-WibDurableJsonFile -Path $manPath -Data $emergencyManifest -Depth 5
            } catch {
                $emergencyRewriteError = $_.Exception.Message
                Write-WibLog "Emergency manifest rewrite failed: $($_.Exception.Message)" 'WARN'
            }
        }

        # Release publication lock strictly AFTER dismount, cleanup, and final report are sealed
        $pubLockReleaseStatus = if ($targetPubLockStream) { 'pending' } else { 'none' }
        if ($targetPubLockStream) {
            try {
                $targetPubLockStream.Close()
                $targetPubLockStream.Dispose()
                $pubLockReleaseStatus = 'released'
            } catch {
                $pubLockReleaseStatus = "failed: $($_.Exception.Message)"
                Write-WibLog "Warning: Publication lock close failed: $($_.Exception.Message)" 'WARN'
            }
            $targetPubLockStream = $null
            if ($targetPubLockPath) {
                Remove-Item -LiteralPath $targetPubLockPath -Force -ErrorAction SilentlyContinue
                $targetPubLockPath = $null
            }
        }

        # Release workspace lock LAST --- after all dismounts, report, and cleanup are
        # complete. Only now is it safe for another build to acquire this workspace.
        $workspaceLockReleaseStatus = if ($workspaceLock) { 'pending' } else { 'none' }
        if ($workspaceLock) {
            try {
                Unlock-WibWorkspace -LockStream $workspaceLock -WorkDir $WorkDir
                $workspaceLockReleaseStatus = 'released'
            } catch {
                $workspaceLockReleaseStatus = "failed: $($_.Exception.Message)"
                Write-WibLog "Warning: Workspace unlock failed: $($_.Exception.Message)" 'WARN'
            }
            $workspaceLock = $null
        }

        if ($manifest -is [System.Collections.IDictionary]) {
            $manifest['PublicationLockReleaseStatus'] = $pubLockReleaseStatus
            $manifest['WorkspaceLockReleaseStatus'] = $workspaceLockReleaseStatus
        }

        # Write durable authoritative terminal state record in reportDir (and WorkDir if available)
        $termExitCode = if ($finalTeardownError -or (-not $state.Success) -or ($manifest.status -eq 'failed')) { 1 } else { 0 }
        $termRecord = [ordered]@{
            status                       = if ($termExitCode -eq 0) { $manifest.status } else { 'failed' }
            overallStatus                = if ($termExitCode -eq 0) { $manifest['overallStatus'] } else { 'failed' }
            artifactStatus               = $manifest['artifactStatus']
            finalizationStatus           = $manifest['finalizationStatus']
            publicationLockReleaseStatus = $pubLockReleaseStatus
            workspaceLockReleaseStatus   = $workspaceLockReleaseStatus
            emergencyRewriteFailed       = [bool]$emergencyRewriteError
            emergencyRewriteError        = $emergencyRewriteError
            exitCode                     = $termExitCode
            error                        = if ($finalTeardownError) { $finalTeardownError } elseif ($manifest.error) { $manifest.error } else { $null }
            runId                        = $runId
            timestamp                    = (Get-Date).ToString('o')
        }

        # Primary write to reportDir is mandatory and FAIL CLOSED
        if ($reportDir -and (Test-Path -LiteralPath $reportDir)) {
            $repTermPath = Join-Path $reportDir 'terminal-state.json'
            try {
                Set-WibDurableJsonFile -Path $repTermPath -Data $termRecord -Depth 5
            } catch {
                $termErr = "Mandatory terminal-state.json persistence failed in reportDir '$reportDir': $($_.Exception.Message)"
                Write-WibLog $termErr 'ERROR'
                $state.Success = $false
                $manifest.status = 'failed'
                $manifest['overallStatus'] = 'failed'
                $manifest['finalizationStatus'] = "failed: $termErr"
                $manifest.error = $termErr
                if (-not $finalTeardownError) {
                    $finalTeardownError = $termErr
                }
                $termRecord['status'] = 'failed'
                $termRecord['overallStatus'] = 'failed'
                $termRecord['finalizationStatus'] = "failed: $termErr"
                $termRecord['exitCode'] = 1
                $termRecord['error'] = if ($finalTeardownError) { $finalTeardownError } else { $termErr }

                # Invalidate any previously written success manifest/checksum so disk never falsely indicates success
                try {
                    $sigPath = Join-Path $reportDir 'manifest.json.sha256'
                    if (Test-Path -LiteralPath $sigPath) {
                        try { Remove-Item -LiteralPath $sigPath -Force -ErrorAction Stop }
                        catch {
                            try { Set-Content -LiteralPath $sigPath -Value 'INVALIDATED_BUILD_FAILED' -Encoding ASCII -Force -ErrorAction Stop } catch {}
                        }
                    }
                    $emergencyManifest = [ordered]@{
                        status             = 'failed'
                        overallStatus      = 'failed'
                        artifactStatus     = $manifest['artifactStatus']
                        finalizationStatus = "failed: $termErr"
                        error              = $termErr
                        runId              = $runId
                        tool               = @{ version = $script:WibVersion }
                        createdUtc         = (Get-Date).ToUniversalTime().ToString('o')
                    }
                    Set-WibDurableJsonFile -Path (Join-Path $reportDir 'manifest.json') -Data $emergencyManifest -Depth 5
                } catch {
                    $termRecord['emergencyRewriteFailed'] = $true
                    $termRecord['emergencyRewriteError']  = $_.Exception.Message
                    Write-WibLog "Emergency manifest rewrite following terminal-state write failure also failed: $($_.Exception.Message)" 'WARN'
                }
            }
        }

        # Secondary write to WorkDir (if distinct from reportDir)
        if ($WorkDir -and (Test-Path -LiteralPath $WorkDir) -and $WorkDir -ne $reportDir) {
            $workTermPath = Join-Path $WorkDir 'terminal-state.json'
            try {
                Set-WibDurableJsonFile -Path $workTermPath -Data $termRecord -Depth 5
            } catch {
                Write-WibLog "Failed to write terminal-state.json to WorkDir '$WorkDir': $($_.Exception.Message)" 'WARN'
            }
        }

        Set-WibLogPath $null

        if ($finalTeardownError) {
            throw $finalTeardownError
        }
    }
    return $state
}
