# Hardware Adaptation Reference

## Philosophy

A central differentiation of WIB is **hardware awareness**. Rather than applying a fixed set of aggressive tweaks that may degrade stability on low-end hardware or waste performance on high-end workstations, WIB tunes the target image to the actual capabilities of the target device.

Adaptive decisions are never hidden: every hardware-driven decision is recorded in the build manifest and report accompanied by human-readable reasoning (e.g. *"SysMain disabled: NVMe SSD detected"*).

## Hardware Signal Matrix

| Signal | Source | Value Thresholds | Adaptive Decision | Rationale |
|---|---|---|---|---|
| **RAM Capacity** | `Win32_PhysicalMemory` | `< 8 GB`<br>`8 – 16 GB`<br>`>= 32 GB` | Low: Enable memory compression, aggressive background apps.<br>High: Disable memory compression. | Memory compression trades CPU cycles to conserve physical RAM on memory-constrained systems, but introduces unnecessary CPU overhead when memory is plentiful. |
| **Storage Type** | `MSFT_PhysicalDisk` (MediaType) | `SSD` / `NVMe`<br>`HDD` | SSD: Disable SysMain.<br>HDD: Keep SysMain, light compression. | SysMain (SuperFetch) caches blocks for slow rotating disks; on fast NVMe drives it causes pointless flash write wear and background activity. |
| **CPU Architecture & Cores** | `Win32_Processor` | `< 4 cores`<br>`>= 8 cores` | Weak: XPRESS4K compression.<br>Strong: LZX / LZMS recovery compression. | Heavy compression algorithms impose noticeable decompression latency on weak or thermal-throttled CPUs. |
| **GPU Subsystem** | `Win32_VideoController` | Integrated (Intel HD/UHD)<br>Discrete (NVIDIA/AMD) | Integrated: Turn off transparency and window animations.<br>Discrete: Keep full visual effects. | Visual transparency and desktop window manager effects consume GPU memory bandwidth on unified shared memory architectures. |
| **Chassis / Form Factor** | `Win32_SystemEnclosure` | Laptop (`ChassisTypes` 8, 9, 10)<br>Desktop (`ChassisTypes` 3, 4, 6) | Laptop: Preserve battery saver and modern standby.<br>Desktop: Enable Ultimate Performance plan. | Power management tweaks should not sacrifice mobile battery longevity. |

## Querying Hardware Signals via CIM / WMI

```powershell
function Get-WibHardwareProfile {
    # 1. Total Physical RAM in GB
    $memBytes = (Get-CimInstance Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum).Sum
    $ramGB = [math]::Round($memBytes / 1GB, 1)

    # 2. Storage Media Type
    $disks = Get-CimInstance -Namespace root\Microsoft\Windows\Storage -ClassName MSFT_PhysicalDisk -ErrorAction SilentlyContinue
    $isSSD = $false
    if ($disks) {
        $isSSD = ($disks | Where-Object { $_.MediaType -in @(4, 5) }).Count -gt 0 # 4=SSD, 5=SCM
    }

    # 3. CPU Core Count
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $cores = $cpu.NumberOfCores
    $cpuName = $cpu.Name

    # 4. GPU Detection
    $gpu = Get-CimInstance Win32_VideoController | Select-Object -First 1
    $gpuName = $gpu.Name
    $isIntegrated = ($gpuName -match 'Intel\(R\) (HD|UHD|Iris)' -or $gpuName -match 'AMD Radeon\(TM\) Graphics')

    [PSCustomObject]@{
        RamGB        = $ramGB
        IsSSD        = $isSSD
        CpuCores     = $cores
        CpuName      = $cpuName
        GpuName      = $gpuName
        IsIntegrated = $isIntegrated
    }
}
```

## User-Supplied Target Hardware Specification (`--hardware-spec`)

When building an image on a high-end build workstation for deployment to an older or lower-spec target laptop, the user can supply a target spec file (`target-spec.json`) instead of querying the build host:

```json
{
  "targetHardware": {
    "ramGB": 4,
    "storageType": "HDD",
    "cpuCores": 2,
    "gpuType": "integrated",
    "formFactor": "laptop"
  }
}
```

The planner resolves decisions using the supplied specification, ensuring proper tuning regardless of host hardware.
