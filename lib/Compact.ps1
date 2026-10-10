# Core compression library for WIB (wib-compact).
# Wraps Windows compact.exe for first-party-only, safe NTFS/WOF file compression.
# Strict PowerShell 5.1 compatibility.

if (-not $script:WibVersion -and -not (Get-Command Get-WibSha256 -ErrorAction SilentlyContinue)) {
    if ($PSScriptRoot -and (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'Core.ps1'))) {
        . (Join-Path $PSScriptRoot 'Core.ps1')
    }
}

if (-not (Get-Command Format-WibBytes -ErrorAction SilentlyContinue)) {
    function Format-WibBytes {
        param([long]$Bytes)
        if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
        if ($Bytes -ge 1MB) { return ('{0:N1} MB' -f ($Bytes / 1MB)) }
        if ($Bytes -ge 1KB) { return ('{0:N0} KB' -f ($Bytes / 1KB)) }
        return "$Bytes B"
    }
}

$script:WibIncompressibleCache = @{}
$script:WibBeforeCompactMutationHook = $null

$script:WibCompactIncompressibleExtensions = @(
    # Archives / compressed containers
    '.zip', '.7z', '.rar', '.gz', '.bz2', '.xz', '.zst', '.tgz', '.cab',
    '.iso', '.wim', '.esd', '.vhd', '.vhdx', '.qcow2',
    # Video
    '.mp4', '.mkv', '.avi', '.mov', '.wmv', '.webm', '.flv', '.m4v',
    # Audio
    '.mp3', '.aac', '.ogg', '.flac', '.m4a', '.wma', '.opus',
    # Images
    '.jpg', '.jpeg', '.png', '.gif', '.webp', '.avif', '.heic',
    # Compressed document / package formats
    '.docx', '.xlsx', '.pptx', '.apk', '.jar', '.msix', '.appx'
)

if (-not ([System.Management.Automation.PSTypeName]'WibNativeFileHelper').Type) {
    try {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class WibNativeFileHelper {
    [DllImport("kernel32.dll", EntryPoint = "GetCompressedFileSizeW", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern uint GetCompressedFileSizeW(string lpFileName, out uint lpFileSizeHigh);

    public static long GetCompressedSize(string path) {
        uint high = 0;
        uint low = GetCompressedFileSizeW(path, out high);
        if (low == 0xFFFFFFFF && Marshal.GetLastWin32Error() != 0) {
            return -1;
        }
        return ((long)high << 32) | (long)low;
    }
}
'@ -ErrorAction SilentlyContinue
    } catch { Write-Verbose $_.Exception.Message }
}

$script:WibSystemExclusionPaths = @(
    'C:\Windows',
    'C:\Windows\System32',
    'pagefile.sys',
    'swapfile.sys',
    'hiberfil.sys',
    'dumpstack.log',
    '$Recycle.Bin',
    'System Volume Information'
)

function Get-WibCompactAlgorithmRecommendation {
    [CmdletBinding()]
    param(
        $HardwareProfile
    )

    if (-not $HardwareProfile) {
        if (Get-Command Get-WibHardwareProfile -ErrorAction SilentlyContinue) {
            $HardwareProfile = Get-WibHardwareProfile
        } else {
            return @{
                Algorithm = 'XPRESS8K'
                Reason    = 'Standard balanced algorithm (hardware profile not available).'
            }
        }
    }

    # 1. HDD or low-power CPU (<= 2 cores)
    if ((-not $HardwareProfile.IsSSD) -or ($HardwareProfile.CpuCores -le 2)) {
        return @{
            Algorithm = 'XPRESS4K'
            Reason    = "Fastest decompression with lowest CPU overhead (Storage: $($HardwareProfile.StorageType), CPU cores: $($HardwareProfile.CpuCores))."
        }
    }

    # 2. High-performance workstation / desktop with >= 8 cores and fast SSD
    if ($HardwareProfile.IsSSD -and ($HardwareProfile.CpuCores -ge 8) -and ($HardwareProfile.FormFactor -ne 'laptop')) {
        return @{
            Algorithm = 'LZX'
            Reason    = "Maximum compression ratio with fast multi-core decompression (Storage: $($HardwareProfile.StorageType), CPU cores: $($HardwareProfile.CpuCores))."
        }
    }

    # 3. Modern SSD with 4-6 cores
    return @{
        Algorithm = 'XPRESS8K'
        Reason    = "Optimal balance of compression ratio and real-time read speed (Storage: $($HardwareProfile.StorageType), CPU cores: $($HardwareProfile.CpuCores))."
    }
}

function Test-WibDirectStorage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return @{ IsDirectStorage = $false; Files = @() }
    }

    $dsFiles = @()
    try {
        $found = Get-ChildItem -LiteralPath $Path -Filter 'dstorage*.dll' -Recurse -File -Force -ErrorAction SilentlyContinue
        if ($found) {
            $dsFiles = @($found | ForEach-Object { $_.FullName })
        }
    } catch { Write-Verbose $_.Exception.Message }

    @{
        IsDirectStorage = ($dsFiles.Count -gt 0)
        Files           = $dsFiles
        Warning         = if ($dsFiles.Count -gt 0) {
            "DirectStorage runtime detected ($($dsFiles.Count) file(s)). WOF filesystem compression may degrade or conflict with DirectStorage GPU/NVMe decompression pipelines."
        } else { '' }
    }
}

function Test-WibIncompressibleFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FilePath
    )

    $normalized = $FilePath.ToLower()
    if ($script:WibIncompressibleCache.ContainsKey($normalized)) {
        return $script:WibIncompressibleCache[$normalized]
    }

    $ext = [System.IO.Path]::GetExtension($FilePath).ToLower()
    $isIncompressible = ($script:WibCompactIncompressibleExtensions -contains $ext)
    $script:WibIncompressibleCache[$normalized] = $isIncompressible
    return $isIncompressible
}

function Set-WibIncompressibleCacheEntry {
    param([string]$FilePath, [bool]$IsIncompressible = $true)
    $normalized = $FilePath.ToLower()
    $script:WibIncompressibleCache[$normalized] = $IsIncompressible
}

function Clear-WibIncompressibleCache {
    $script:WibIncompressibleCache.Clear()
}

function Test-WibSystemPathExclusion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    $full = [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
    if ([System.IO.Path]::GetPathRoot($full).TrimEnd('\') -ieq $full.TrimEnd('\')) {
        return @{ IsExcluded = $true; Reason = 'Drive root cannot be folder-compressed.' }
    }
    $winDir = [System.IO.Path]::GetFullPath($env:SystemRoot).TrimEnd('\')

    if ($full -ieq $winDir -or $full -ilike "$winDir\*") {
        return @{
            IsExcluded = $true
            Reason     = "Path '$Path' is within the Windows directory. Whole OS compression must use /CompactOS, not folder compression."
        }
    }

    $leaf = Split-Path -Leaf $full
    if ($script:WibSystemExclusionPaths -contains $leaf) {
        return @{
            IsExcluded = $true
            Reason     = "File or directory '$leaf' is a protected system entity."
        }
    }

    # Match path segments against protected / anti-cheat / runtime folders
    $protectedSegments = @(
        'WindowsApps', 'Windows Defender', 'EasyAntiCheat', 'BattlEye',
        'PunkBuster', 'Riot Vanguard', 'DirectStorage'
    )
    $segments = $full -split '[\\/]'
    foreach ($seg in $segments) {
        foreach ($prot in $protectedSegments) {
            if ($seg -ieq $prot) {
                return @{
                    IsExcluded = $true
                    Reason     = "Path contains protected or anti-cheat component '$seg'. Compressing may cause driver or runtime integrity failures."
                }
            }
        }
    }

    return @{ IsExcluded = $false; Reason = '' }
}

function Measure-WibFolderSavings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [ValidateSet('XPRESS4K', 'XPRESS8K', 'XPRESS16K', 'LZX', 'auto')][string]$Algorithm = 'auto',
        $HardwareProfile
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Path not found: $Path"
    }

    # Resolve algorithm
    $chosenAlgo = $Algorithm
    $algoReason = ''
    if ($chosenAlgo -eq 'auto') {
        $rec = Get-WibCompactAlgorithmRecommendation -HardwareProfile $HardwareProfile
        $chosenAlgo = $rec.Algorithm
        $algoReason = $rec.Reason
    }

    # Exclusion checks
    $sysEx = Test-WibSystemPathExclusion -Path $Path
    $ds = Test-WibDirectStorage -Path $Path

    # Query existing compact status via compact.exe /q /s
    $existing = Get-WibCompactStatus -Path $Path

    # Analyze individual files in the folder (stream via EnumerateFiles to minimize memory overhead)
    $totalFiles = 0
    $totalBytes = 0
    $compressibleBytes = 0
    $skippedBytes = 0
    $compressibleCount = 0
    $skippedCount = 0

    try {
        $fileEnum = [System.IO.Directory]::EnumerateFiles($Path, '*', [System.IO.SearchOption]::AllDirectories)
        foreach ($filePath in $fileEnum) {
            $totalFiles++
            try {
                $len = (New-Object System.IO.FileInfo($filePath)).Length
                $totalBytes += $len
                if (Test-WibIncompressibleFile -FilePath $filePath) {
                    $skippedBytes += $len
                    $skippedCount++
                } else {
                    $compressibleBytes += $len
                    $compressibleCount++
                }
            } catch { Write-Verbose $_.Exception.Message }
        }
    } catch {
        # Fallback to Get-ChildItem if EnumerateFiles encounters access issues
        $allFiles = Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue
        if ($allFiles) {
            foreach ($f in $allFiles) {
                $totalFiles++
                $len = [long]$f.Length
                $totalBytes += $len
                if (Test-WibIncompressibleFile -FilePath $f.FullName) {
                    $skippedBytes += $len
                    $skippedCount++
                } else {
                    $compressibleBytes += $len
                    $compressibleCount++
                }
            }
        }
    }

    # Estimated ratio per algorithm for compressible data:
    # XPRESS4K: ~1.4:1 (30% savings)
    # XPRESS8K: ~1.55:1 (35% savings)
    # XPRESS16K: ~1.7:1 (41% savings)
    # LZX: ~2.0:1 (50% savings)
    $savingsRate = 0.35
    switch ($chosenAlgo) {
        'XPRESS4K'  { $savingsRate = 0.30 }
        'XPRESS8K'  { $savingsRate = 0.35 }
        'XPRESS16K' { $savingsRate = 0.42 }
        'LZX'       { $savingsRate = 0.50 }
    }

    $estimatedSavingsBytes = [long][math]::Round($compressibleBytes * $savingsRate)
    $estimatedFinalBytes = $totalBytes - $estimatedSavingsBytes

    [PSCustomObject]@{
        Path                  = $Path
        Algorithm             = $chosenAlgo
        AlgorithmReason       = $algoReason
        TotalFiles            = $totalFiles
        CompressibleFiles     = $compressibleCount
        SkippedFiles          = $skippedCount
        TotalBytes            = $totalBytes
        CompressibleBytes     = $compressibleBytes
        SkippedBytes          = $skippedBytes
        EstimatedSavingsBytes = $estimatedSavingsBytes
        EstimatedFinalBytes   = $estimatedFinalBytes
        EstimatedRatio        = if ($totalBytes -gt 0) { [math]::Round($totalBytes / [math]::Max(1, $estimatedFinalBytes), 2) } else { 1.0 }
        IsDirectStorage       = $ds.IsDirectStorage
        DirectStorageWarning  = $ds.Warning
        IsSystemExcluded      = $sysEx.IsExcluded
        SystemExclusionReason = $sysEx.Reason
        CurrentStatus         = $existing
    }
}

function Assert-WibCompactTargetIdentity {
    <#
    .SYNOPSIS
        Fail-closed containment, reparse-point, and 64-bit NTFS File ID verification for compact.exe targets (WIB-017).
        Requires both Assert-WibNoReparsePointsInTree and Get-WibKernelNodeIdentity to exist and succeed without
        any static [WibKernelPathHelper] downgrade or null/empty identity continuation.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$ExpectedRootId = ''
    )
    if (-not (Get-Command Assert-WibNoReparsePointsInTree -ErrorAction SilentlyContinue) -or
        -not (Get-Command Get-WibKernelNodeIdentity -ErrorAction SilentlyContinue)) {
        throw "SECURITY ERROR: Mandatory containment/identity helpers (Assert-WibNoReparsePointsInTree / Get-WibKernelNodeIdentity) are unavailable; refusing to execute compact.exe on unverified path '$Path'."
    }
    $resolvedTarget = [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $targetRoot = [System.IO.Path]::GetPathRoot($resolvedTarget)
    if ($targetRoot -and ($resolvedTarget -ieq $targetRoot.TrimEnd('\', '/'))) {
        throw "Safety Exclusion: Drive root '$resolvedTarget' cannot be folder-compressed or decompressed under any circumstances."
    }
    $parentBase = Split-Path -Parent $resolvedTarget
    if ([string]::IsNullOrWhiteSpace($parentBase)) {
        throw "SECURITY ERROR: Could not resolve parent base directory for compact target '$resolvedTarget'."
    }
    $resolvedTarget = Assert-WibNoReparsePointsInTree -Path $resolvedTarget -BaseDir $parentBase
    $nodeId = Get-WibKernelNodeIdentity -LiteralPath $resolvedTarget
    if ([string]::IsNullOrWhiteSpace($nodeId) -or $nodeId.StartsWith('REPARSE:', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Reparse point or kernel identity violation on compact target '$resolvedTarget' ($nodeId)."
    }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedRootId) -and ($nodeId -cne $ExpectedRootId)) {
        throw "TOCTOU node identity mismatch before compact operation on '$resolvedTarget': expected '$ExpectedRootId', found '$nodeId'. Aborting operation."
    }
    return @{
        Path   = $resolvedTarget
        RootId = $nodeId
    }
}

function Get-WibCompactStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    $p = (Resolve-Path -LiteralPath $Path).Path
    $compactArgs = @('/Q', "/S:$p")
    $output = Invoke-WibNativeTool -ToolKey 'compactExe' -FilePath 'compact.exe' -Arguments $compactArgs

    $compactExit = $LASTEXITCODE
    $compactSuccess = ($compactExit -eq 0)
    $compactError = ''
    if (-not $compactSuccess) {
        $errLine = ($output | Where-Object { $_ -match 'error|failed|denied|cannot|invalid|is not recognized' } | Select-Object -First 1)
        $compactError = if ($errLine) { ([string]$errLine).Trim() } else { "compact.exe query failed with exit code $compactExit." }
    }

    $totalFiles = 0
    $compFiles = 0
    $uncompFiles = 0
    $dataBytes = 0
    $storedBytes = 0
    $ratio = 1.0

    if ($compactSuccess) {
        foreach ($line in $output) {
            $str = [string]$line
            if ($str -match 'Of\s+([\d,\.]+)\s+files\s+within\s+([\d,\.]+)\s+directories') {
                $totalFiles = [int](($matches[1]) -replace '[,\.]','')
            }
            if ($str -match '([\d,\.]+)\s+are\s+compressed\s+and\s+([\d,\.]+)\s+are\s+not\s+compressed') {
                $compFiles = [int](($matches[1]) -replace '[,\.]','')
                $uncompFiles = [int](($matches[2]) -replace '[,\.]','')
            }
            if ($str -match '([\d,\.]+)\s+total\s+bytes\s+of\s+data\s+are\s+stored\s+in\s+([\d,\.]+)\s+bytes') {
                $dataBytes = [long](($matches[1]) -replace '[,\.]','')
                $storedBytes = [long](($matches[2]) -replace '[,\.]','')
            }
            if ($str -match 'The\s+compression\s+ratio\s+is\s+([\d\.]+)\s+to\s+1') {
                $ratio = [double]$matches[1]
            }
        }

        # Locale-independent fallback via P/Invoke GetCompressedFileSizeW if compact.exe parsing yielded 0
        if ($totalFiles -eq 0 -or $storedBytes -eq 0) {
            $dataBytes = 0
            $storedBytes = 0
            $compFiles = 0
            $uncompFiles = 0
            $totalFiles = 0

            try {
                $fileEnum = [System.IO.Directory]::EnumerateFiles($p, '*', [System.IO.SearchOption]::AllDirectories)
                foreach ($filePath in $fileEnum) {
                    $totalFiles++
                    try {
                        $flen = (New-Object System.IO.FileInfo($filePath)).Length
                        $dataBytes += $flen
                        $cSize = -1
                        if ([System.Management.Automation.PSTypeName]'WibNativeFileHelper'.Type) {
                            $cSize = [WibNativeFileHelper]::GetCompressedSize($filePath)
                        }
                        if ($cSize -ge 0) {
                            $storedBytes += $cSize
                            if ($cSize -lt $flen) { $compFiles++ } else { $uncompFiles++ }
                        } else {
                            $storedBytes += $flen
                            $uncompFiles++
                        }
                    } catch { Write-Verbose $_.Exception.Message }
                }
            } catch {
                $allF = Get-ChildItem -LiteralPath $p -Recurse -File -Force -ErrorAction SilentlyContinue
                if ($allF) {
                    $totalFiles = $allF.Count
                    foreach ($f in $allF) {
                        $flen = [long]$f.Length
                        $dataBytes += $flen
                        $cSize = -1
                        if ([System.Management.Automation.PSTypeName]'WibNativeFileHelper'.Type) {
                            $cSize = [WibNativeFileHelper]::GetCompressedSize($f.FullName)
                        }
                        if ($cSize -ge 0) {
                            $storedBytes += $cSize
                            if ($cSize -lt $flen) { $compFiles++ } else { $uncompFiles++ }
                        } else {
                            $storedBytes += $flen
                            $uncompFiles++
                        }
                    }
                }
            }

            if ($storedBytes -gt 0) {
                $ratio = [math]::Round([double]$dataBytes / [double]$storedBytes, 2)
            }
        }
    }

    $savedBytes = [math]::Max(0, ($dataBytes - $storedBytes))
    $compactState = if (-not $compactSuccess) {
        'error'
    } elseif ($compFiles -gt 0) {
        'compressed'
    } else {
        'uncompressed'
    }

    [PSCustomObject]@{
        Path              = $p
        TotalFiles        = $totalFiles
        CompressedFiles   = $compFiles
        UncompressedFiles = $uncompFiles
        OriginalBytes     = $dataBytes
        CompressedBytes   = $storedBytes
        SavedBytes        = $savedBytes
        Ratio             = $ratio
        ExitCode          = $compactExit
        Success           = $compactSuccess
        State             = $compactState
        Error             = $compactError
    }
}

function Invoke-WibFolderCompression {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [ValidateSet('XPRESS4K', 'XPRESS8K', 'XPRESS16K', 'LZX', 'auto')][string]$Algorithm = 'auto',
        [switch]$Force,
        [switch]$Recompress,
        [switch]$OverrideSafetyChecks,
        [switch]$ContinueOnNativeError,
        $HardwareProfile
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Target folder not found: $Path"
    }

    $target = (Resolve-Path -LiteralPath $Path).Path
    $targetRoot = [System.IO.Path]::GetPathRoot($target)
    if ($targetRoot -and ($target.TrimEnd('\', '/') -ieq $targetRoot.TrimEnd('\', '/'))) {
        throw "Safety Exclusion: Drive root '$target' cannot be folder-compressed under any circumstances."
    }

    # WIB-003, WIB-009, WIB-014 & WIB-017: Fail-closed containment, non-reparse tree check, and 64-bit NTFS File ID
    # verification before compression (non-overridable, no fallback downgrade).
    $initialIdentity = Assert-WibCompactTargetIdentity -Path $target
    $target = $initialIdentity.Path
    $expectedRootId = $initialIdentity.RootId

    # 1. System path check (requires explicit -OverrideSafetyChecks; -Force alone only controls /F recompression)
    $sysCheck = Test-WibSystemPathExclusion -Path $target
    if ($sysCheck.IsExcluded -and -not $OverrideSafetyChecks) {
        throw "Safety Exclusion: $($sysCheck.Reason) (Pass -OverrideSafetyChecks to explicitly override safety exclusions; -Force only controls /F recompression)."
    }

    # 2. DirectStorage check (requires explicit -OverrideSafetyChecks)
    $dsCheck = Test-WibDirectStorage -Path $target
    if ($dsCheck.IsDirectStorage -and -not $OverrideSafetyChecks) {
        throw "DirectStorage Warning: $($dsCheck.Warning) Pass -OverrideSafetyChecks to explicitly override."
    }

    # 3. Resolve Algorithm
    $algo = $Algorithm
    if ($algo -eq 'auto') {
        $algo = (Get-WibCompactAlgorithmRecommendation -HardwareProfile $HardwareProfile).Algorithm
    }

    Write-Host "Compressing folder '$target' using $algo..." -ForegroundColor Cyan

    if ($script:WibBeforeCompactMutationHook -is [scriptblock]) {
        & $script:WibBeforeCompactMutationHook $target 'compress'
    }

    # WIB-017: Re-verify root directory 64-bit NTFS File ID and absence of reparse points immediately before invoking compact.exe
    $verifiedIdentity = Assert-WibCompactTargetIdentity -Path $target -ExpectedRootId $expectedRootId
    $target = $verifiedIdentity.Path

    # Build compact.exe arguments using array splatting for safe path quoting
    $compactArgs = @('/C', "/S:$($target.TrimEnd('\'))", "/EXE:$algo", '/I', '/A')
    if ($Force -or $Recompress) {
        $compactArgs += '/F'
    }

    $compOut = Invoke-WibNativeTool -ToolKey 'compactExe' -FilePath 'compact.exe' -Arguments $compactArgs
    if ($compOut) { $compOut | ForEach-Object { Write-Verbose $_ } }
    $exit = $LASTEXITCODE
    if ($exit -ne 0) {
        if (-not $ContinueOnNativeError) {
            throw "compact.exe failed with exit code $exit while compressing '$target'. Pass -ContinueOnNativeError to inspect partial failure results without throwing."
        }
        Write-Warning "compact.exe exited with non-zero code $exit."
    }

    # Query result status independently of override flags
    $status = Get-WibCompactStatus -Path $target
    $opSuccess = [bool]($exit -eq 0 -and $null -ne $status -and $status.Success)
    $opState = if ($opSuccess) {
        $status.State
    } elseif ($exit -ne 0) {
        'failed'
    } else {
        'verification-failed'
    }

    if ($opSuccess) {
        Write-Host "Compression Complete. Ratio: $($status.Ratio):1, Saved: $(Format-WibBytes $status.SavedBytes)" -ForegroundColor Green
    } else {
        Write-Host "Compression finished with warnings/errors (ExitCode: $exit, State: $opState). Ratio: $($status.Ratio):1, Saved: $(Format-WibBytes $status.SavedBytes)" -ForegroundColor Yellow
    }

    return [PSCustomObject]@{
        Path             = $target
        Algorithm        = $algo
        ExitCode         = $exit
        Success          = $opSuccess
        State            = $opState
        SafetyOverridden = [bool]$OverrideSafetyChecks
        ContinuedOnError = [bool]($exit -ne 0 -and $ContinueOnNativeError)
        Status           = $status
    }
}

function Invoke-WibFolderDecompression {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$Force,
        [switch]$ContinueOnNativeError
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Target folder not found: $Path"
    }

    $target = (Resolve-Path -LiteralPath $Path).Path
    $targetRoot = [System.IO.Path]::GetPathRoot($target)
    if ($targetRoot -and ($target.TrimEnd('\', '/') -ieq $targetRoot.TrimEnd('\', '/'))) {
        throw "Safety Exclusion: Drive root '$target' cannot be folder-decompressed under any circumstances."
    }

    # WIB-017: Fail-closed containment, non-reparse tree check, and 64-bit NTFS File ID verification before decompression
    $initialIdentity = Assert-WibCompactTargetIdentity -Path $target
    $target = $initialIdentity.Path
    $expectedRootId = $initialIdentity.RootId

    Write-Host "Decompressing folder '$target'..." -ForegroundColor Cyan

    if ($script:WibBeforeCompactMutationHook -is [scriptblock]) {
        & $script:WibBeforeCompactMutationHook $target 'decompress'
    }

    # WIB-017: Re-verify root directory 64-bit NTFS File ID and absence of reparse points immediately before invoking compact.exe
    $verifiedIdentity = Assert-WibCompactTargetIdentity -Path $target -ExpectedRootId $expectedRootId
    $target = $verifiedIdentity.Path

    $compactArgs = @('/U', "/S:$($target.TrimEnd('\'))", '/EXE', '/I', '/A')
    if ($Force) {
        $compactArgs += '/F'
    }
    $decompOut = Invoke-WibNativeTool -ToolKey 'compactExe' -FilePath 'compact.exe' -Arguments $compactArgs
    if ($decompOut) { $decompOut | ForEach-Object { Write-Verbose $_ } }
    $exit = $LASTEXITCODE
    if ($exit -ne 0) {
        if (-not $ContinueOnNativeError) {
            throw "compact.exe failed with exit code $exit while decompressing '$target'. Pass -ContinueOnNativeError to inspect partial failure results without throwing."
        }
        Write-Warning "compact.exe exited with non-zero code $exit."
    }

    $status = Get-WibCompactStatus -Path $target
    $opSuccess = [bool]($exit -eq 0 -and $null -ne $status -and $status.Success)
    $opState = if ($opSuccess) {
        $status.State
    } elseif ($exit -ne 0) {
        'failed'
    } else {
        'verification-failed'
    }

    if ($opSuccess) {
        Write-Host "Decompression Complete." -ForegroundColor Green
    } else {
        Write-Host "Decompression finished with warnings/errors (ExitCode: $exit, State: $opState)." -ForegroundColor Yellow
    }

    return [PSCustomObject]@{
        Path             = $target
        ExitCode         = $exit
        Success          = $opSuccess
        State            = $opState
        ContinuedOnError = [bool]($exit -ne 0 -and $ContinueOnNativeError)
        Status           = $status
    }
}

function Invoke-WibCompactOS {
    [CmdletBinding()]
    param(
        [ValidateSet('query', 'always', 'never')][string]$Action = 'query',
        [string]$OfflineWinDir = '',
        [switch]$Force,
        [switch]$ContinueOnNativeError
    )

    $osArgs = @("/CompactOS:$Action")
    if ($OfflineWinDir) {
        $osArgs += "/WinDir:$OfflineWinDir"
    }

    Write-Host "Executing compact.exe $($osArgs -join ' ')..." -ForegroundColor Cyan
    $output = Invoke-WibNativeTool -ToolKey 'compactExe' -FilePath 'compact.exe' -Arguments $osArgs
    $exitCode = $LASTEXITCODE

    $state = 'unknown'
    $isSuccess = $false

    if ($Action -eq 'query') {
        # Native Windows exit codes for compact.exe /CompactOS:query:
        # Exit code 0   = system is in Compact state
        # Exit code 102 = system is not in Compact state
        if ($exitCode -eq 0) {
            $state = 'compact'
            $isSuccess = $true
        } elseif ($exitCode -eq 102) {
            $state = 'not-compact'
            $isSuccess = $true
        } else {
            $isSuccess = $false
        }
    } elseif ($Action -eq 'always') {
        if ($exitCode -eq 0) {
            $state = 'compact'
            $isSuccess = $true
        } else {
            $isSuccess = $false
        }
    } elseif ($Action -eq 'never') {
        if ($exitCode -eq 0) {
            $state = 'not-compact'
            $isSuccess = $true
        } else {
            $isSuccess = $false
        }
    }

    foreach ($line in $output) {
        $str = [string]$line
        Write-Host "  $str" -ForegroundColor Gray
        if ($state -eq 'unknown') {
            if ($str -match 'The\s+system\s+is\s+in\s+the\s+Compact\s+state' -or $str -match 'Completed\s+compressing\s+OS\s+binaries') {
                $state = 'compact'
                if ($exitCode -eq 0) { $isSuccess = $true }
            } elseif ($str -match 'The\s+system\s+is\s+not\s+in\s+the\s+Compact\s+state' -or $str -match 'Completed\s+uncompressing\s+OS\s+binaries') {
                $state = 'not-compact'
                if ($exitCode -eq 0 -or $exitCode -eq 102) { $isSuccess = $true }
            }
        }
    }

    if (-not $isSuccess -and -not $ContinueOnNativeError) {
        throw "compact.exe /CompactOS:$Action failed with exit code $exitCode (State: $state). Output: $($output -join ' ')"
    }

    [PSCustomObject]@{
        Action           = $Action
        State            = $state
        ExitCode         = $exitCode
        Success          = $isSuccess
        ContinuedOnError = [bool](-not $isSuccess -and $ContinueOnNativeError)
        Output           = ($output -join "`n")
    }
}

function Set-WibCompactWatcher {
    [CmdletBinding()]
    param(
        [ValidateSet('add', 'remove', 'list', 'enable', 'disable', 'run')][string]$Action = 'list',
        [string]$Path = '',
        [string]$Algorithm = 'XPRESS8K',
        [string]$ConfigDir = ''
    )

    if (-not $ConfigDir) {
        $ConfigDir = Join-Path $env:ProgramData 'WIB'
    }
    if (-not (Test-Path -LiteralPath $ConfigDir)) {
        New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null
        if ($ConfigDir -ieq (Join-Path $env:ProgramData 'WIB')) {
            try {
                $acl = Get-Acl -LiteralPath $ConfigDir
                $acl.SetAccessRuleProtection($true, $false)
                $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule('BUILTIN\Administrators', 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
                $systemRule = New-Object System.Security.AccessControl.FileSystemAccessRule('NT AUTHORITY\SYSTEM', 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
                $usersRule = New-Object System.Security.AccessControl.FileSystemAccessRule('BUILTIN\Users', 'ReadAndExecute', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
                $acl.AddAccessRule($adminRule)
                $acl.AddAccessRule($systemRule)
                $acl.AddAccessRule($usersRule)
                Set-Acl -LiteralPath $ConfigDir -AclObject $acl
            } catch { Write-Verbose $_.Exception.Message }
        }
    }

    $configFile = Join-Path $ConfigDir 'compact_watched_folders.json'
    $watched = New-Object System.Collections.ArrayList

    if (Test-Path -LiteralPath $configFile) {
        try {
            $raw = Get-Content -LiteralPath $configFile -Raw | ConvertFrom-Json
            if ($raw) {
                foreach ($item in $raw) {
                    [void]$watched.Add([PSCustomObject]@{
                        Path      = [string]$item.Path
                        Algorithm = [string]$item.Algorithm
                        AddedUtc  = [string]$item.AddedUtc
                    })
                }
            }
        } catch { Write-Verbose $_.Exception.Message }
    }

    switch ($Action) {
        'list' {
            return @($watched)
        }
        'add' {
            if (-not $Path) { throw 'Path is required for add action.' }
            $full = (Resolve-Path -LiteralPath $Path).Path
            $verified = Assert-WibCompactTargetIdentity -Path $full
            $full = $verified.Path
            # Enforce system and anti-cheat path exclusion
            $sysCheck = Test-WibSystemPathExclusion -Path $full
            if ($sysCheck.IsExcluded) {
                throw "Safety Exclusion: Cannot watch '$full': $($sysCheck.Reason)"
            }
            # Check if already present
            $existing = @($watched | Where-Object { $_.Path -ieq $full })
            if ($existing.Count -gt 0) {
                Write-Host "Path '$full' is already in the watch list." -ForegroundColor Yellow
                return @($watched)
            }
            [void]$watched.Add([PSCustomObject]@{
                Path      = $full
                Algorithm = $Algorithm
                AddedUtc  = (Get-Date).ToUniversalTime().ToString('o')
            })
            $watched | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $configFile -Encoding UTF8
            Write-Host "Added '$full' to watched compression folders." -ForegroundColor Green
            return @($watched)
        }
        'remove' {
            if (-not $Path) { throw 'Path is required for remove action.' }
            $full = $Path.TrimEnd('\')
            $filtered = New-Object System.Collections.ArrayList
            foreach ($item in $watched) {
                if ($item.Path.TrimEnd('\') -ine $full) {
                    [void]$filtered.Add($item)
                }
            }
            $filtered | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $configFile -Encoding UTF8
            Write-Host "Removed '$full' from watched compression folders." -ForegroundColor Green
            return @($filtered)
        }
        'run' {
            Write-Host "Running watcher sweep across $($watched.Count) folder(s)..." -ForegroundColor Cyan
            $results = New-Object System.Collections.ArrayList
            foreach ($item in $watched) {
                if (Test-Path -LiteralPath $item.Path) {
                    $sysCheck = Test-WibSystemPathExclusion -Path $item.Path
                    if ($sysCheck.IsExcluded) {
                        Write-Warning "Skipping protected/excluded folder '$($item.Path)': $($sysCheck.Reason)"
                        continue
                    }
                    try {
                        Write-Host "Checking watched folder: $($item.Path) ($($item.Algorithm))" -ForegroundColor Gray
                        # Compress newly added or changed uncompressed files without /F
                        $res = Invoke-WibFolderCompression -Path $item.Path -Algorithm $item.Algorithm
                        [void]$results.Add($res)
                    } catch {
                        Write-Warning "Failed compressing watched folder '$($item.Path)': $($_.Exception.Message)"
                    }
                } else {
                    Write-Warning "Watched folder missing: $($item.Path)"
                }
            }
            return @($results)
        }
        'enable' {
            $script = Join-Path (Split-Path -Parent $PSScriptRoot) 'tools\wib-compact.ps1'
            if (-not (Test-Path -LiteralPath $script)) { throw "wib-compact.ps1 not found: $script" }
            $act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script`" -Command watcher -WatcherAction run"
            $trg = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 3am
            Register-ScheduledTask -TaskName 'WibCompactWatcher' -Action $act -Trigger $trg -RunLevel Highest -Force | Out-Null
            Write-Host "Scheduled task 'WibCompactWatcher' registered to run weekly." -ForegroundColor Green
        }
        'disable' {
            Unregister-ScheduledTask -TaskName 'WibCompactWatcher' -Confirm:$false -ErrorAction SilentlyContinue
            Write-Host "Scheduled task 'WibCompactWatcher' removed." -ForegroundColor Green
        }
    }
}

Set-Alias -Name Manage-WibCompactWatcher -Value Set-WibCompactWatcher -ErrorAction SilentlyContinue
