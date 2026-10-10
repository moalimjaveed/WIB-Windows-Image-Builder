# Hardware profiling and adaptive decision engine for WIB.
# Strict PowerShell 5.1 compatibility.

function Get-WibHardwareProfileHash {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$HardwareProfile)

    $toHash = [ordered]@{}
    $props = @('RamGB', 'StorageType', 'IsSSD', 'CpuCores', 'CpuName', 'GpuType', 'IsIntegratedGpu', 'GpuName', 'FormFactor', 'Source', 'Confidence')
    foreach ($p in $props) {
        $val = $null
        if ($HardwareProfile -is [System.Collections.IDictionary]) {
            if ($HardwareProfile.Contains($p)) { $val = $HardwareProfile[$p] }
        } elseif ($null -ne $HardwareProfile.PSObject.Properties[$p]) {
            $val = $HardwareProfile.$p
        }
        $toHash[$p] = $val
    }

    $json = ConvertTo-WibCanonicalJson $toHash
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $hasher = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hashBytes = $hasher.ComputeHash($bytes)
        $sb = New-Object System.Text.StringBuilder
        foreach ($b in $hashBytes) { [void]$sb.Append($b.ToString('x2')) }
        return $sb.ToString()
    } finally {
        $hasher.Dispose()
    }
}

function Get-WibHardwareProfile {
    [CmdletBinding()]
    param(
        [string]$SpecPath = ''
    )

    # 1. User-supplied target hardware specification file
    if ($SpecPath) {
        if (-not (Test-Path -LiteralPath $SpecPath)) {
            throw "Hardware spec file not found: $SpecPath"
        }
        Write-WibLog "Loading hardware profile from spec file: $SpecPath" 'INFO'
        $raw = Get-Content -LiteralPath $SpecPath -Raw | ConvertFrom-Json
        $spec = ConvertTo-WibHashtable $raw

        $target = $spec
        if ($spec.ContainsKey('targetHardware') -and ($spec['targetHardware'] -is [System.Collections.IDictionary])) {
            $target = $spec['targetHardware']
        }

        $ramGB = 8
        if ($target.ContainsKey('ramGB') -and $null -ne $target['ramGB']) {
            $ramGB = [double]$target['ramGB']
        }

        $storageType = 'SSD'
        if ($target.ContainsKey('storageType') -and $target['storageType']) {
            $storageType = [string]$target['storageType']
        }
        $isSSD = ($storageType -in @('SSD', 'NVMe'))

        $cpuCores = 4
        if ($target.ContainsKey('cpuCores') -and $null -ne $target['cpuCores']) {
            $cpuCores = [int]$target['cpuCores']
        }

        $cpuName = 'Custom Processor'
        if ($target.ContainsKey('cpuName') -and $target['cpuName']) {
            $cpuName = [string]$target['cpuName']
        }

        $gpuType = 'discrete'
        if ($target.ContainsKey('gpuType') -and $target['gpuType']) {
            $gpuType = [string]$target['gpuType']
        }
        $isIntegrated = ($gpuType.ToLower() -eq 'integrated')

        $gpuName = if ($isIntegrated) { 'Integrated Graphics' } else { 'Dedicated Graphics' }
        if ($target.ContainsKey('gpuName') -and $target['gpuName']) {
            $gpuName = [string]$target['gpuName']
        }

        $formFactor = 'desktop'
        if ($target.ContainsKey('formFactor') -and $target['formFactor']) {
            $formFactor = [string]$target['formFactor']
        }

        $confidence = 'high'
        if ($target.ContainsKey('confidence') -and $target['confidence']) {
            $confidence = [string]$target['confidence']
        }

        $hwObj = [PSCustomObject]@{
            Source              = 'spec-file'
            Confidence          = $confidence
            SpecFile            = $SpecPath
            RamGB               = $ramGB
            StorageType         = $storageType
            IsSSD               = $isSSD
            CpuCores            = $cpuCores
            CpuName             = $cpuName
            GpuType             = $gpuType
            IsIntegratedGpu     = $isIntegrated
            GpuName             = $gpuName
            FormFactor          = $formFactor.ToLower()
            HardwareProfileHash = ''
        }
        $hwObj.HardwareProfileHash = Get-WibHardwareProfileHash -HardwareProfile $hwObj
        return $hwObj
    }

    # 2. Query live host system hardware via CIM / WMI
    $isVm = $false
    $vmHost = ''
    try {
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
        if ($cs) {
            if ($cs.HypervisorPresent -or ($cs.Model -match 'Virtual|VMware|VirtualBox|KVM|QEMU|Hyper-V')) {
                $isVm = $true
                $vmHost = if ($cs.Model) { [string]$cs.Model } else { 'Hypervisor' }
            }
        }
        if (-not $isVm) {
            $bios = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
            if ($bios -and ($bios.Version -match 'VBOX|VMware|QEMU|Virtual' -or $bios.SerialNumber -match 'VMware|Virtual')) {
                $isVm = $true
                $vmHost = 'Virtual Machine'
            }
        }
    } catch { Write-Verbose $_.Exception.Message }

    if ($isVm) {
        Write-WibLog "Host is running inside a virtual machine ($vmHost). Live-host adaptive profiling reflects VM virtual resources. For targeting physical bare-metal hardware, supply -HardwareSpec <spec.json>." 'WARN'
    }

    $ramProbeOk = $false
    $ramGB = 8.0
    try {
        $memSum = (Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue | Measure-Object -Property Capacity -Sum).Sum
        if ($memSum -and $memSum -gt 0) {
            $ramGB = [math]::Round($memSum / 1GB, 1)
            $ramProbeOk = $true
        } else {
            $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
            if ($cs -and $cs.TotalPhysicalMemory) {
                $ramGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
                $ramProbeOk = $true
            }
        }
    } catch { Write-Verbose $_.Exception.Message }

    $storageProbeOk = $false
    $storageType = 'SSD'
    $isSSD = $true
    try {
        $disks = Get-CimInstance -Namespace root\Microsoft\Windows\Storage -ClassName MSFT_PhysicalDisk -ErrorAction SilentlyContinue
        if ($disks) {
            $storageProbeOk = $true
            $ssdCount = ($disks | Where-Object { $_.MediaType -in @(4, 5) -or $_.BusType -eq 17 -or ($null -ne $_.SpindleSpeed -and $_.SpindleSpeed -eq 0) }).Count
            if ($ssdCount -gt 0) {
                $isSSD = $true
                $storageType = 'SSD'
            } else {
                $isSSD = $false
                $storageType = 'HDD'
            }
        } else {
            $drives = Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue
            if ($drives) {
                $storageProbeOk = $true
                $modelMatch = ($drives | Where-Object { $_.Model -match 'SSD|NVMe|Solid State' }).Count
                if ($modelMatch -gt 0) {
                    $isSSD = $true
                    $storageType = 'SSD'
                } else {
                    $isSSD = $false
                    $storageType = 'HDD'
                }
            }
        }
    } catch { Write-Verbose $_.Exception.Message }

    $cpuProbeOk = $false
    $cpuCores = 4
    $cpuName = 'Generic Processor'
    try {
        $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cpu -and $cpu.NumberOfCores) {
            $cpuCores = [int]$cpu.NumberOfCores
            $cpuName = [string]$cpu.Name
            $cpuProbeOk = $true
        }
    } catch { Write-Verbose $_.Exception.Message }

    $gpuProbeOk = $false
    $isIntegrated = $false
    $gpuName = 'Generic GPU'
    try {
        $gpu = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($gpu -and $gpu.Name) {
            $gpuName = [string]$gpu.Name
            $gpuProbeOk = $true
            $isDiscrete = ($gpuName -match 'NVIDIA|GeForce|RTX|Quadro|Radeon RX|Radeon Pro|Arc A')
            $isIntegrated = ($gpuName -match 'Intel\(R\) (HD|UHD|Iris)' -or $gpuName -match 'AMD Radeon\(TM\) Graphics' -or $gpuName -match 'Basic Display' -or -not $isDiscrete)
        }
    } catch { Write-Verbose $_.Exception.Message }
    $gpuType = if ($isIntegrated) { 'integrated' } else { 'discrete' }

    $formFactorProbeOk = $false
    $formFactor = 'desktop'
    try {
        $enc = Get-CimInstance Win32_SystemEnclosure -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($enc -and $enc.ChassisTypes) {
            $formFactorProbeOk = $true
            $portableTypes = @(8, 9, 10, 11, 12, 14, 30, 31, 32) # Laptop, Notebook, Sub-notebook, etc.
            foreach ($ct in $enc.ChassisTypes) {
                if ($portableTypes -contains $ct) {
                    $formFactor = 'laptop'
                    break
                }
            }
        }
    } catch { Write-Verbose $_.Exception.Message }

    # Strict multi-component probe confidence evaluation:
    # All 5 component probes (RAM, storage, CPU, GPU, form factor) must succeed for 'high' confidence.
    # If critical probes (RAM, CPU) failed: 'unknown'.
    # If secondary probes (storage, GPU, form factor) failed or running in VM: 'provisional'.
    $confidence = 'high'
    if (-not $ramProbeOk -or -not $cpuProbeOk) {
        $confidence = 'unknown'
    } elseif ($isVm -or -not $storageProbeOk -or -not $gpuProbeOk -or -not $formFactorProbeOk) {
        $confidence = 'provisional'
    }

    $hwObj = [PSCustomObject]@{
        Source              = 'live-host'
        Confidence          = $confidence
        SpecFile            = $null
        IsVm                = $isVm
        VmHost              = $vmHost
        RamGB               = $ramGB
        StorageType         = $storageType
        IsSSD               = $isSSD
        CpuCores            = $cpuCores
        CpuName             = $cpuName
        GpuType             = $gpuType
        IsIntegratedGpu     = $isIntegrated
        GpuName             = $gpuName
        FormFactor          = $formFactor.ToLower()
        HardwareProfileHash = ''
    }
    $hwObj.HardwareProfileHash = Get-WibHardwareProfileHash -HardwareProfile $hwObj
    return $hwObj
}

function Resolve-WibAdaptiveDecisions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$HardwareProfile,
        [Parameter(Mandatory)][hashtable]$BuildProfile
    )

    $decisions = New-Object System.Collections.ArrayList

    # 1. RAM Rule
    if ($HardwareProfile.RamGB -ge 16) {
        [void]$decisions.Add([ordered]@{
            Signal   = 'RAM Capacity'
            Value    = "$($HardwareProfile.RamGB) GB"
            Module   = 'adaptive-memory'
            Decision = 'Keep kernel and drivers resident in RAM (DisablePagingExecutive)'
            Reason   = "High RAM capacity ($($HardwareProfile.RamGB) GB) - prevents paging executive components to disk under memory plenty."
            Tweaks   = @(
                (New-WibTweak SYSTEM 'ControlSet001\Control\Session Manager\Memory Management' 'DisablePagingExecutive' DWord 1)
            )
        })
    } elseif ($HardwareProfile.RamGB -lt 8) {
        [void]$decisions.Add([ordered]@{
            Signal   = 'RAM Capacity'
            Value    = "$($HardwareProfile.RamGB) GB"
            Module   = 'background-apps-off'
            Decision = 'Enforce background apps denial & conserve physical memory'
            Reason   = "Low RAM capacity ($($HardwareProfile.RamGB) GB) - conserves physical RAM for foreground applications."
            Tweaks   = @(
                (New-WibTweak SOFTWARE 'Policies\Microsoft\Windows\AppPrivacy' 'LetAppsRunInBackground' DWord 2)
            )
        })
    } else {
        [void]$decisions.Add([ordered]@{
            Signal   = 'RAM Capacity'
            Value    = "$($HardwareProfile.RamGB) GB"
            Module   = 'adaptive-memory'
            Decision = 'Standard memory manager defaults retained'
            Reason   = "Balanced RAM capacity ($($HardwareProfile.RamGB) GB) - default memory compression balance is optimal."
            Tweaks   = @()
        })
    }

    # 2. Storage Rule (SysMain / SuperFetch)
    if ($HardwareProfile.IsSSD) {
        [void]$decisions.Add([ordered]@{
            Signal   = 'Storage Type'
            Value    = $HardwareProfile.StorageType
            Module   = 'services-tuning'
            Decision = 'Disable SysMain (SuperFetch) service'
            Reason   = "Fast solid-state storage ($($HardwareProfile.StorageType)) - eliminates unnecessary flash write wear and background prefetch caching."
            Tweaks   = @(
                (New-WibTweak SYSTEM 'ControlSet001\Services\SysMain' 'Start' DWord 4)
            )
        })
    } else {
        [void]$decisions.Add([ordered]@{
            Signal   = 'Storage Type'
            Value    = $HardwareProfile.StorageType
            Module   = 'services-tuning'
            Decision = 'Keep SysMain (SuperFetch) service enabled'
            Reason   = "Rotating mechanical storage ($($HardwareProfile.StorageType)) - block prefetching significantly improves random seek performance."
            Tweaks   = @(
                (New-WibTweak SYSTEM 'ControlSet001\Services\SysMain' 'Start' DWord 2)
            )
        })
    }

    # 3. GPU Rule (Visual Effects)
    if ($HardwareProfile.IsIntegratedGpu) {
        [void]$decisions.Add([ordered]@{
            Signal   = 'GPU Subsystem'
            Value    = "$($HardwareProfile.GpuName) (Integrated)"
            Module   = 'visual-effects'
            Decision = 'Disable transparency and window animations'
            Reason   = "Integrated GPU detected ($($HardwareProfile.GpuName)) - reduces shared unified memory bandwidth pressure and compositor latency."
            Settings = @{ disableTransparency = $true; disableAnimations = $true }
            Tweaks   = @(
                (New-WibTweak NTUSER 'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' DWord 0),
                (New-WibTweak NTUSER 'Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' DWord 2),
                (New-WibTweak NTUSER 'Control Panel\Desktop\WindowMetrics' 'MinAnimate' String '0'),
                (New-WibTweak NTUSER 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarAnimations' DWord 0)
            )
        })
    } else {
        [void]$decisions.Add([ordered]@{
            Signal   = 'GPU Subsystem'
            Value    = "$($HardwareProfile.GpuName) (Discrete)"
            Module   = 'visual-effects'
            Decision = 'Preserve compositor visual effects'
            Reason   = "Discrete GPU detected ($($HardwareProfile.GpuName)) - dedicated VRAM handles visual effects without degrading CPU memory bus."
            Settings = @{ disableTransparency = $false; disableAnimations = $false }
            Tweaks   = @()
        })
    }

    # 4. Form Factor / Power Rule
    if ($HardwareProfile.FormFactor -eq 'laptop') {
        [void]$decisions.Add([ordered]@{
            Signal   = 'Form Factor'
            Value    = 'Laptop / Mobile'
            Module   = 'power-tuning'
            Decision = 'Preserve battery saver and dynamic CPU power scaling'
            Reason   = 'Mobile battery-powered device detected - avoids forcing high-power CPU states that degrade battery life.'
            Tweaks   = @(
                (New-WibTweak SOFTWARE 'Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'SystemResponsiveness' DWord 20)
            )
        })
    } else {
        [void]$decisions.Add([ordered]@{
            Signal   = 'Form Factor'
            Value    = 'Desktop / Workstation'
            Module   = 'power-tuning'
            Decision = 'Tune desktop responsiveness'
            Reason   = 'Mains-powered desktop detected - no battery degradation constraints.'
            Tweaks   = @(
                (New-WibTweak SOFTWARE 'Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'SystemResponsiveness' DWord 10)
            )
        })
    }

    return @($decisions)
}

function Invoke-WibAdaptiveDecisions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Decisions,
        [Parameter(Mandatory)][hashtable]$BuildProfile,
        [Parameter(Mandatory)]$Ctx
    )

    if (-not $Ctx.ContainsKey('AdaptiveDecisions') -or $Ctx.AdaptiveDecisions -isnot [System.Collections.ArrayList]) {
        $existing = if ($Ctx.ContainsKey('AdaptiveDecisions') -and $Ctx.AdaptiveDecisions) { @($Ctx.AdaptiveDecisions) } else { @() }
        $Ctx['AdaptiveDecisions'] = New-Object System.Collections.ArrayList
        foreach ($item in $existing) { [void]$Ctx.AdaptiveDecisions.Add($item) }
    }

    foreach ($d in $Decisions) {
        [void]$Ctx.AdaptiveDecisions.Add($d)

        # Apply module setting overrides if provided
        $dSettings = $null
        $dModule = $null
        if ($d -is [System.Collections.IDictionary]) {
            if ($d.Contains('Settings')) { $dSettings = $d['Settings'] }
            if ($d.Contains('Module')) { $dModule = $d['Module'] }
        } elseif ($null -ne $d.PSObject) {
            if ($d.PSObject.Properties['Settings']) { $dSettings = $d.Settings }
            if ($d.PSObject.Properties['Module']) { $dModule = $d.Module }
        }

        if ($dSettings -and $dModule) {
            $modId = [string]$dModule
            if (-not $BuildProfile['modules'].ContainsKey($modId)) {
                $BuildProfile['modules'][$modId] = @{ enabled = $true }
            }
            if ($dSettings -is [System.Collections.IDictionary]) {
                foreach ($k in $dSettings.Keys) {
                    $BuildProfile['modules'][$modId][$k] = $dSettings[$k]
                }
            }
        }
    }
}

Set-Alias -Name Apply-WibAdaptiveDecisions -Value Invoke-WibAdaptiveDecisions -ErrorAction SilentlyContinue
