#Requires -Version 5.1
<#
.SYNOPSIS
    Automated VM validation and benchmarking for Windows Image Builder (WIB).
    Measures boot time, idle RAM, idle CPU, and disk used on Hyper-V Gen 2 VMs.
    Compares stock Windows 11 vs. WIB-optimized image and computes real deltas.

.DESCRIPTION
    Strict rule: publish only numbers the benchmark produced.
    Report disk savings separately from RAM savings.
#>

[CmdletBinding()]
param(
    [string]$StockIsoPath,
    [string]$BuiltIsoPath,
    [string]$StockVhdx,
    [string]$BuiltVhdx,
    [string]$VmPrefix = 'WibBench',
    [string]$SwitchName = 'Default Switch',
    [string]$OutputDir = 'reports\benchmarks',
    [int]$SettlePeriodSeconds = 60,
    [System.Management.Automation.PSCredential]$Credential = $null,
    [switch]$Mock,
    [hashtable]$MockData = @{}
)

$ErrorActionPreference = 'Stop'

function Get-WibVmMeasurements {
    param(
        [string]$IsoPath,
        [string]$VhdxPath,
        [string]$VmName,
        [switch]$IsMock,
        [hashtable]$MockOverride,
        [System.Management.Automation.PSCredential]$Credential = $null
    )

    if ($IsMock) {
        Write-Host "  [MOCK] Measuring simulated metrics for $VmName..." -ForegroundColor Cyan
        $bootSec = 38.5
        $idleRamMB = 2850
        $idleCpuPct = 4.8
        $diskUsedGB = 22.4

        if ($MockOverride -and $MockOverride.ContainsKey('bootTimeSec')) { $bootSec = [double]$MockOverride['bootTimeSec'] }
        if ($MockOverride -and $MockOverride.ContainsKey('idleRamMB'))   { $idleRamMB = [double]$MockOverride['idleRamMB'] }
        if ($MockOverride -and $MockOverride.ContainsKey('idleCpuPct'))  { $idleCpuPct = [double]$MockOverride['idleCpuPct'] }
        if ($MockOverride -and $MockOverride.ContainsKey('diskUsedGB'))  { $diskUsedGB = [double]$MockOverride['diskUsedGB'] }

        return [PSCustomObject]@{
            VmName          = $VmName
            IsoPath         = $IsoPath
            VhdxPath        = $VhdxPath
            BootTimeSeconds = $bootSec
            IdleRamMB       = $idleRamMB
            IdleCpuPercent  = $idleCpuPct
            DiskUsedGB      = $diskUsedGB
        }
    }

    # Real Hyper-V measurement path
    if (-not (Get-Command Get-VM -ErrorAction SilentlyContinue)) {
        throw 'Hyper-V PowerShell module not found. Enable Hyper-V or run with -Mock for simulation testing.'
    }

    Write-Host "  Initializing Hyper-V Gen 2 VM: $VmName..." -ForegroundColor Cyan
    $diffDisk = $null
    if ($VhdxPath -and (Test-Path -LiteralPath $VhdxPath)) {
        $diffDir = Join-Path $OutputDir 'diff-disks'
        if (-not (Test-Path -LiteralPath $diffDir)) { New-Item -ItemType Directory -Force -Path $diffDir | Out-Null }
        $diffDisk = Join-Path $diffDir "$VmName-diff.vhdx"
        if (Test-Path -LiteralPath $diffDisk) { Remove-Item -LiteralPath $diffDisk -Force -ErrorAction SilentlyContinue }
        if (Get-Command New-VHD -ErrorAction SilentlyContinue) {
            New-VHD -ParentPath $VhdxPath -Path $diffDisk -Differencing | Out-Null
        }
    }

    # VM startup and measurement logic via PowerShell Direct
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Start-VM -Name $VmName | Out-Null
    
    # Wait for guest OS heartbeat
    do {
        Start-Sleep -Seconds 2
        $vmObj = Get-VM -Name $VmName
        $heartbeat = ($vmObj | Get-VMIntegrationService | Where-Object { $_.Name -eq 'Heartbeat' }).PrimaryStatusDescription
    } while ($heartbeat -ne 'OK' -and $sw.Elapsed.TotalSeconds -lt 300)
    
    $sw.Stop()
    $bootSeconds = [math]::Round($sw.Elapsed.TotalSeconds, 1)

    Write-Host "  Waiting $SettlePeriodSeconds seconds for idle settling..." -ForegroundColor Gray
    Start-Sleep -Seconds $SettlePeriodSeconds

    # Measure memory and CPU metrics using median of 3 samples
    $cpuSamples = New-Object System.Collections.ArrayList
    $ramSamples = New-Object System.Collections.ArrayList
    for ($s = 0; $s -lt 3; $s++) {
        if ($s -gt 0) { Start-Sleep -Seconds 2 }
        $vmMetrics = Get-VM -Name $VmName
        [void]$cpuSamples.Add([math]::Round($vmMetrics.CPUUsage, 1))
        [void]$ramSamples.Add([math]::Round($vmMetrics.MemoryAssigned / 1MB, 0))
    }
    $sortedCpu = @($cpuSamples | Sort-Object)
    $sortedRam = @($ramSamples | Sort-Object)
    $cpuUsagePct = $sortedCpu[1]
    $assignedRamMB = $sortedRam[1]
    $diskGB = $null

    # Query guest OS metrics using CIM via PowerShell Direct
    try {
        $icParams = @{
            VMName = $VmName
            ScriptBlock = {
                $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
                $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction SilentlyContinue
                $usedRam = $null
                if ($os -and $os.TotalVisibleMemorySize -and $os.FreePhysicalMemory) {
                    $usedRam = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1KB, 0)
                }
                $usedDisk = $null
                if ($disk -and $disk.Size -and $disk.FreeSpace) {
                    $usedDisk = [math]::Round(($disk.Size - $disk.FreeSpace) / 1GB, 2)
                }
                [PSCustomObject]@{
                    UsedRamMB  = $usedRam
                    UsedDiskGB = $usedDisk
                }
            }
            ErrorAction = 'SilentlyContinue'
        }
        if ($Credential) {
            $icParams['Credential'] = $Credential
        }
        $guestMetrics = Invoke-Command @icParams
        if ($guestMetrics) {
            if ($guestMetrics.UsedRamMB -ne $null -and $guestMetrics.UsedRamMB -gt 0) {
                $assignedRamMB = [double]$guestMetrics.UsedRamMB
            }
            if ($guestMetrics.UsedDiskGB -ne $null -and $guestMetrics.UsedDiskGB -gt 0) {
                $diskGB = [double]$guestMetrics.UsedDiskGB
            }
        }
    } catch {
        Write-Verbose $_.Exception.Message
    }

    if ($diffDisk -and (Test-Path -LiteralPath $diffDisk)) {
        try {
            Stop-VM -Name $VmName -TurnOff -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $diffDisk -Force -ErrorAction SilentlyContinue
        } catch {
            Write-Verbose $_.Exception.Message
        }
    }

    [PSCustomObject]@{
        VmName          = $VmName
        IsoPath         = $IsoPath
        VhdxPath        = $VhdxPath
        BootTimeSeconds = $bootSeconds
        IdleRamMB       = $assignedRamMB
        IdleCpuPercent  = $cpuUsagePct
        DiskUsedGB      = $diskGB
    }
}

Write-Host '================ WIB VM BENCHMARK & VALIDATION ================' -ForegroundColor Cyan
if ($Mock) {
    Write-Host '*** SIMULATED DATA - NOT MEASURED ***' -ForegroundColor Yellow
}

$stamp = (Get-Date).ToString('yyyyMMdd_HHmmss')
if (-not (Test-Path -LiteralPath $OutputDir)) {
    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
}

$stockMock = @{}
$builtMock = @{}
if ($MockData.ContainsKey('stock')) { $stockMock = $MockData['stock'] }
if ($MockData.ContainsKey('built')) { $builtMock = $MockData['built'] }

function Format-WibMetric {
    param($val, [string]$suffix = '')
    if ($null -eq $val) { return 'N/A' }
    return "$val$suffix"
}

# 1. Measure Stock ISO / VHDX
Write-Host "`n[1/2] Benchmarking Stock Windows Image..." -ForegroundColor White
$stockResult = Get-WibVmMeasurements -IsoPath $StockIsoPath -VhdxPath $StockVhdx -VmName "${VmPrefix}_Stock" -IsMock:$Mock -MockOverride $stockMock -Credential $Credential

# 2. Measure Built (Optimized) ISO / VHDX
Write-Host "`n[2/2] Benchmarking WIB-Optimized Windows Image..." -ForegroundColor White
if ($Mock -and -not $builtMock.Count) {
    $builtMock = @{
        bootTimeSec = 21.2
        idleRamMB   = 1420
        idleCpuPct  = 1.2
        diskUsedGB  = 14.1
    }
}
$builtResult = Get-WibVmMeasurements -IsoPath $BuiltIsoPath -VhdxPath $BuiltVhdx -VmName "${VmPrefix}_Built" -IsMock:$Mock -MockOverride $builtMock -Credential $Credential

# 3. Compute Deltas (Strict: only publish real measured deltas)
$bootTimeDeltaSec = if ($stockResult.BootTimeSeconds -ne $null -and $builtResult.BootTimeSeconds -ne $null) {
    [math]::Round($stockResult.BootTimeSeconds - $builtResult.BootTimeSeconds, 1)
} else { $null }

$bootImprovementPct = if ($stockResult.BootTimeSeconds -and $stockResult.BootTimeSeconds -gt 0 -and $bootTimeDeltaSec -ne $null) {
    [math]::Round(($bootTimeDeltaSec / $stockResult.BootTimeSeconds) * 100, 1)
} else { $null }

$ramSavingsMB = if ($stockResult.IdleRamMB -ne $null -and $builtResult.IdleRamMB -ne $null) {
    [math]::Round($stockResult.IdleRamMB - $builtResult.IdleRamMB, 0)
} else { $null }

$ramSavingsPct = if ($stockResult.IdleRamMB -and $stockResult.IdleRamMB -gt 0 -and $ramSavingsMB -ne $null) {
    [math]::Round(($ramSavingsMB / $stockResult.IdleRamMB) * 100, 1)
} else { $null }

$diskSavingsGB = if ($stockResult.DiskUsedGB -ne $null -and $builtResult.DiskUsedGB -ne $null) {
    [math]::Round($stockResult.DiskUsedGB - $builtResult.DiskUsedGB, 2)
} else { $null }

$diskSavingsPct = if ($stockResult.DiskUsedGB -and $stockResult.DiskUsedGB -gt 0 -and $diskSavingsGB -ne $null) {
    [math]::Round(($diskSavingsGB / $stockResult.DiskUsedGB) * 100, 1)
} else { $null }

$cpuDeltaPct = if ($stockResult.IdleCpuPercent -ne $null -and $builtResult.IdleCpuPercent -ne $null) {
    [math]::Round($stockResult.IdleCpuPercent - $builtResult.IdleCpuPercent, 1)
} else { $null }

$benchmarkData = [ordered]@{
    benchmarkUtc = (Get-Date).ToUniversalTime().ToString('o')
    executionMode = if ($Mock) { 'simulated-mock' } else { 'live-hyperv' }
    isSimulated = [bool]$Mock
    banner = if ($Mock) { 'SIMULATED DATA - NOT MEASURED' } else { $null }
    settlePeriodSec = $SettlePeriodSeconds
    stock = [ordered]@{
        iso = $StockIsoPath
        vhdx = $StockVhdx
        bootTimeSeconds = $stockResult.BootTimeSeconds
        idleRamMB = $stockResult.IdleRamMB
        idleCpuPercent = $stockResult.IdleCpuPercent
        diskUsedGB = $stockResult.DiskUsedGB
    }
    built = [ordered]@{
        iso = $BuiltIsoPath
        vhdx = $BuiltVhdx
        bootTimeSeconds = $builtResult.BootTimeSeconds
        idleRamMB = $builtResult.IdleRamMB
        idleCpuPercent = $builtResult.IdleCpuPercent
        diskUsedGB = $builtResult.DiskUsedGB
    }
    deltas = [ordered]@{
        bootTimeFasterSeconds = $bootTimeDeltaSec
        bootImprovementPercent = $bootImprovementPct
        ramSavingsMB = $ramSavingsMB
        ramSavingsPercent = $ramSavingsPct
        diskSavingsGB = $diskSavingsGB
        diskSavingsPercent = $diskSavingsPct
        idleCpuReductionPercent = $cpuDeltaPct
    }
}

# Write JSON and Markdown reports
$jsonPath = Join-Path $OutputDir "benchmark_$stamp.json"
$mdPath   = Join-Path $OutputDir "benchmark_$stamp.md"

$benchmarkData | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$mockBannerMd = ""
if ($Mock) {
    $mockBannerMd = @'
> [!WARNING]
> ## SIMULATED DATA - NOT MEASURED
> This benchmark report was generated in mock simulation mode. None of the figures below reflect real hardware or live virtual machine execution.

'@
}

$bootStockStr = Format-WibMetric $stockResult.BootTimeSeconds 's'
$bootBuiltStr = Format-WibMetric $builtResult.BootTimeSeconds 's'
$bootDeltaStr = if ($bootTimeDeltaSec -ne $null) { "-$bootTimeDeltaSec s" } else { "N/A" }
$bootImpStr   = if ($bootImprovementPct -ne $null) { "**+$bootImprovementPct% faster**" } else { "N/A" }

$ramStockStr = Format-WibMetric $stockResult.IdleRamMB ' MB'
$ramBuiltStr = Format-WibMetric $builtResult.IdleRamMB ' MB'
$ramDeltaStr = if ($ramSavingsMB -ne $null) { "-$ramSavingsMB MB" } else { "N/A" }
$ramImpStr   = if ($ramSavingsPct -ne $null) { "**-$ramSavingsPct% RAM used**" } else { "N/A" }

$cpuStockStr = Format-WibMetric $stockResult.IdleCpuPercent '%'
$cpuBuiltStr = Format-WibMetric $builtResult.IdleCpuPercent '%'
$cpuDeltaStr = if ($cpuDeltaPct -ne $null) { "-$cpuDeltaPct%" } else { "N/A" }

$diskStockStr = Format-WibMetric $stockResult.DiskUsedGB ' GB'
$diskBuiltStr = Format-WibMetric $builtResult.DiskUsedGB ' GB'
$diskDeltaStr = if ($diskSavingsGB -ne $null) { "-$diskSavingsGB GB" } else { "N/A" }
$diskImpStr   = if ($diskSavingsPct -ne $null) { "**-$diskSavingsPct% disk saved**" } else { "N/A" }

$mdContent = @"
# WIB VM Benchmark Report
$mockBannerMd
Generated: $($benchmarkData.benchmarkUtc)
Mode: $($benchmarkData.executionMode)

## Measurement Comparison

| Metric | Stock Windows 11 | WIB Optimized | Delta | Improvement |
|---|---|---|---|---|
| **Boot Time** | $bootStockStr | $bootBuiltStr | $bootDeltaStr | $bootImpStr |
| **Idle RAM (settled)** | $ramStockStr | $ramBuiltStr | $ramDeltaStr | $ramImpStr |
| **Idle CPU Utilization** | $cpuStockStr | $cpuBuiltStr | $cpuDeltaStr | Lower background load |
| **Disk Space Consumed** | $diskStockStr | $diskBuiltStr | $diskDeltaStr | $diskImpStr |

> Note: Disk savings and RAM savings are reported separately per WIB measurement principles.
"@
$mdContent | Set-Content -LiteralPath $mdPath -Encoding UTF8

Write-Host "`n================ BENCHMARK RESULTS ================" -ForegroundColor Green
Write-Host ("  Boot Time: {0} -> {1} (Delta: {2}, {3})" -f $bootStockStr, $bootBuiltStr, $bootDeltaStr, $bootImpStr)
Write-Host ("  Idle RAM:  {0} -> {1} (Delta: {2}, {3})" -f $ramStockStr, $ramBuiltStr, $ramDeltaStr, $ramImpStr)
Write-Host ("  Disk Used: {0} -> {1} (Delta: {2}, {3})" -f $diskStockStr, $diskBuiltStr, $diskDeltaStr, $diskImpStr)
Write-Host ("  Reports:   $jsonPath, $mdPath") -ForegroundColor Gray
Write-Host "===================================================" -ForegroundColor Green

return $benchmarkData
