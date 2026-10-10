# Registry-driven and post-step modules. Tweak data adapted from tiny11builder (MIT) and reorganised
# into small, individually toggleable modules.

$cdm = 'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'

# ------------------------------------------------------------------ privacy
Register-WibModule -Id 'telemetry' -Order 30 -Risk 'low' -Reversibility 'journal' `
    -Description 'Reduce telemetry and personalisation data collection. Note: AllowTelemetry=0 is fully honoured on Enterprise/Education; Home/Pro treat it as the minimum level.' `
    -Tradeoff 'Restricts telemetry, speech privacy, ink/typing data collection, and disables dmwappushservice. Fully honoured on Enterprise/Education; Home/Pro set to minimum.' `
    -Schema @{} `
    -Tweaks @(
        (New-WibTweak NTUSER 'Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' DWord 0),
        (New-WibTweak NTUSER 'Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' DWord 0),
        (New-WibTweak NTUSER 'Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy' 'HasAccepted' DWord 0),
        (New-WibTweak NTUSER 'Software\Microsoft\Input\TIPC' 'Enabled' DWord 0),
        (New-WibTweak NTUSER 'Software\Microsoft\InputPersonalization' 'RestrictImplicitInkCollection' DWord 1),
        (New-WibTweak NTUSER 'Software\Microsoft\InputPersonalization' 'RestrictImplicitTextCollection' DWord 1),
        (New-WibTweak NTUSER 'Software\Microsoft\InputPersonalization\TrainedDataStore' 'HarvestContacts' DWord 0),
        (New-WibTweak NTUSER 'Software\Microsoft\Personalization\Settings' 'AcceptedPrivacyPolicy' DWord 0),
        (New-WibTweak SOFTWARE 'Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' DWord 0),
        (New-WibTweak SYSTEM 'ControlSet001\Services\dmwappushservice' 'Start' DWord 4)
    )

Register-WibModule -Id 'sponsored-content' -Order 31 -Risk 'low' -Reversibility 'journal' `
    -Description 'Turn off sponsored apps, Start suggestions, consumer features and silent app installs.' `
    -Tradeoff 'Turns off sponsored app suggestions, Content Delivery Manager silent installs, and pre-pinned start menu apps.' `
    -Schema @{} `
    -Tweaks @(
        (New-WibTweak NTUSER $cdm 'OemPreInstalledAppsEnabled' DWord 0),
        (New-WibTweak NTUSER $cdm 'PreInstalledAppsEnabled' DWord 0),
        (New-WibTweak NTUSER $cdm 'SilentInstalledAppsEnabled' DWord 0),
        (New-WibTweak NTUSER $cdm 'ContentDeliveryAllowed' DWord 0),
        (New-WibTweak NTUSER $cdm 'FeatureManagementEnabled' DWord 0),
        (New-WibTweak NTUSER $cdm 'PreInstalledAppsEverEnabled' DWord 0),
        (New-WibTweak NTUSER $cdm 'SoftLandingEnabled' DWord 0),
        (New-WibTweak NTUSER $cdm 'SubscribedContentEnabled' DWord 0),
        (New-WibTweak NTUSER $cdm 'SubscribedContent-310093Enabled' DWord 0),
        (New-WibTweak NTUSER $cdm 'SubscribedContent-338388Enabled' DWord 0),
        (New-WibTweak NTUSER $cdm 'SubscribedContent-338389Enabled' DWord 0),
        (New-WibTweak NTUSER $cdm 'SubscribedContent-338393Enabled' DWord 0),
        (New-WibTweak NTUSER $cdm 'SubscribedContent-353694Enabled' DWord 0),
        (New-WibTweak NTUSER $cdm 'SubscribedContent-353696Enabled' DWord 0),
        (New-WibTweak NTUSER $cdm 'SystemPaneSuggestionsEnabled' DWord 0),
        (New-WibTweak NTUSER "$cdm\Subscriptions" -Action DeleteKey),
        (New-WibTweak NTUSER "$cdm\SuggestedApps" -Action DeleteKey),
        (New-WibTweak SOFTWARE 'Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' DWord 1),
        (New-WibTweak SOFTWARE 'Policies\Microsoft\Windows\CloudContent' 'DisableConsumerAccountStateContent' DWord 1),
        (New-WibTweak SOFTWARE 'Policies\Microsoft\Windows\CloudContent' 'DisableCloudOptimizedContent' DWord 1),
        (New-WibTweak SOFTWARE 'Microsoft\PolicyManager\current\device\Start' 'ConfigureStartPins' String '{"pinnedList": [{}]}'),
        (New-WibTweak SOFTWARE 'Policies\Microsoft\PushToInstall' 'DisablePushToInstall' DWord 1),
        (New-WibTweak SOFTWARE 'Policies\Microsoft\MRT' 'DontOfferThroughWUAU' DWord 1)
    )

Register-WibModule -Id 'copilot-teams-block' -Order 32 -Risk 'low' -Reversibility 'journal' `
    -Description 'Disable Copilot and search suggestions; block Teams, new Outlook and Dev Home auto-install.' `
    -Tradeoff 'Disables Windows Copilot and blocks background installation of Teams, new Outlook, and Dev Home.' `
    -Schema @{} `
    -Tweaks @(
        (New-WibTweak SOFTWARE 'Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' DWord 1),
        (New-WibTweak SOFTWARE 'Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' DWord 1),
        (New-WibTweak SOFTWARE 'Policies\Microsoft\Teams' 'DisableInstallation' DWord 1),
        (New-WibTweak SOFTWARE 'Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler_Oobe\OutlookUpdate' 'workCompleted' DWord 1),
        (New-WibTweak SOFTWARE 'Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler\OutlookUpdate' 'workCompleted' DWord 1),
        (New-WibTweak SOFTWARE 'Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler\DevHomeUpdate' 'workCompleted' DWord 1),
        (New-WibTweak SOFTWARE 'Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\OutlookUpdate' -Action DeleteKey),
        (New-WibTweak SOFTWARE 'Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\DevHomeUpdate' -Action DeleteKey)
    )

# ------------------------------------------------------------------ services
Register-WibModule -Id 'services-tuning' -Order 35 -Risk 'medium' -Reversibility 'journal' `
    -Description 'Tune Windows services start types offline via the SYSTEM hive.' `
    -Tradeoff 'Disables or sets to manual specified background and telemetry services offline. Never touches core OS dependencies.' `
    -Schema @{ disableServices = 'array'; manualServices = 'array'; keepServices = 'array' } `
    -Validate { param($S) foreach ($n in @($S['disableServices']) + @($S['manualServices'])) { if ($n -and $n -notmatch '^[A-Za-z0-9_.\-]+$') { throw "Invalid service name '$n'." } } } `
    -TweakProvider {
        param($S)
        $tweaks = @()
        $neverTouch = Get-WibNeverTouchServices
        $toDisable = @('dmwappushservice', 'DiagTrack')
        if ($S.ContainsKey('disableServices') -and $S['disableServices']) { $toDisable = @($S['disableServices']) }
        $toManual = @()
        if ($S.ContainsKey('manualServices') -and $S['manualServices']) { $toManual = @($S['manualServices']) }
        $keep = @()
        if ($S.ContainsKey('keepServices') -and $S['keepServices']) { $keep = @($S['keepServices']) }

        foreach ($svc in $toDisable) {
            if ($neverTouch -contains $svc -or $keep -contains $svc) { continue }
            $tweaks += (New-WibTweak SYSTEM "ControlSet001\Services\$svc" 'Start' DWord 4)
        }
        foreach ($svc in $toManual) {
            if ($neverTouch -contains $svc -or $keep -contains $svc) { continue }
            $tweaks += (New-WibTweak SYSTEM "ControlSet001\Services\$svc" 'Start' DWord 3)
        }
        $tweaks
    }

Register-WibModule -Id 'bluetooth-tuning' -Order 36 -Risk 'low' -Reversibility 'journal' `
    -Description 'Configure Bluetooth services (bthserv, BTAGService) start type offline.' `
    -Tradeoff 'Disables or sets Bluetooth background services to manual. Frees memory if no Bluetooth peripherals are used.' `
    -HardwareHint 'Recommended on desktop PCs without Bluetooth adapters. Keep enabled on laptops or systems using wireless mice, keyboards, or headsets.' `
    -Schema @{ disableBluetooth = 'bool' } `
    -TweakProvider {
        param($S)
        $disable = $true
        if ($S.ContainsKey('disableBluetooth') -and $null -ne $S['disableBluetooth']) { $disable = [bool]$S['disableBluetooth'] }
        $startVal = if ($disable) { 4 } else { 3 }
        @(
            (New-WibTweak SYSTEM 'ControlSet001\Services\bthserv' 'Start' DWord $startVal),
            (New-WibTweak SYSTEM 'ControlSet001\Services\BTAGService' 'Start' DWord $startVal)
        )
    }

Register-WibModule -Id 'printing-spooler' -Order 37 -Risk 'low' -Reversibility 'journal' `
    -Description 'Configure Print Spooler service offline.' `
    -Tradeoff 'Disables the Print Spooler service. Frees memory and closes print spooler vulnerability surface, but disables all printing.' `
    -HardwareHint 'Safe for dedicated gaming setups and VMs; keep enabled if physical printers or Microsoft Print to PDF are required.' `
    -Schema @{ disableSpooler = 'bool' } `
    -TweakProvider {
        param($S)
        $disable = $true
        if ($S.ContainsKey('disableSpooler') -and $null -ne $S['disableSpooler']) { $disable = [bool]$S['disableSpooler'] }
        $startVal = if ($disable) { 4 } else { 2 }
        @(
            (New-WibTweak SYSTEM 'ControlSet001\Services\Spooler' 'Start' DWord $startVal)
        )
    }

Register-WibModule -Id 'hibernation' -Order 38 -Risk 'low' -Reversibility 'journal' `
    -Description 'Configure system hibernation and Fast Startup offline.' `
    -Tradeoff 'Disables hibernation and Fast Startup. Frees gigabytes of disk space matching system RAM, but disables sleep-to-hibernate transitions.' `
    -HardwareHint 'Significant disk space savings on high-RAM desktops by eliminating hiberfil.sys (sized up to RAM capacity); keep enabled on laptops for battery-safe hybrid sleep.' `
    -Schema @{ disableHibernation = 'bool' } `
    -TweakProvider {
        param($S)
        $disable = $true
        if ($S.ContainsKey('disableHibernation') -and $null -ne $S['disableHibernation']) { $disable = [bool]$S['disableHibernation'] }
        $val = if ($disable) { 0 } else { 1 }
        @(
            (New-WibTweak SYSTEM 'ControlSet001\Control\Power' 'HibernateEnabled' DWord $val),
            (New-WibTweak SYSTEM 'ControlSet001\Control\Session Manager\Power' 'HiberbootEnabled' DWord $val)
        )
    } `
    -Post {
        param($Ctx, $S)
        $disable = $true
        if ($S.ContainsKey('disableHibernation') -and $null -ne $S['disableHibernation']) { $disable = [bool]$S['disableHibernation'] }
        if ($disable -and $Ctx.ContainsKey('MountDir') -and (Test-Path -LiteralPath $Ctx.MountDir)) {
            $scriptsDir = Join-Path $Ctx.MountDir 'Windows\Setup\Scripts'
            if (-not (Test-Path -LiteralPath $scriptsDir)) {
                New-Item -ItemType Directory -Force -Path $scriptsDir | Out-Null
            }
            $cmdPath = Join-Path $scriptsDir 'SetupComplete.cmd'
            $line = 'powercfg /h off'
            if (Test-Path -LiteralPath $cmdPath) {
                Add-Content -LiteralPath $cmdPath -Value "`r`n$line" -Encoding ASCII
            } else {
                Set-Content -LiteralPath $cmdPath -Value "@echo off`r`n$line`r`n" -Encoding ASCII
            }
            New-WibResult 'hibernation' 'SetupComplete.cmd' 'applied' 'added powercfg /h off fallback'
        }
    }

Register-WibModule -Id 'game-mode' -Order 39 -Risk 'low' -Reversibility 'journal' `
    -Description 'Configure Windows Game Mode and GameDVR background capture policy.' `
    -Tradeoff 'Enforces Windows Game Mode to prioritize CPU and GPU resources for foreground games, and disables GameDVR background capture.' `
    -HardwareHint 'Recommended on gaming PCs to ensure background CPU and GPU tasks are throttled when gaming.' `
    -Schema @{ enableGameMode = 'bool' } `
    -TweakProvider {
        param($S)
        $enable = $true
        if ($S.ContainsKey('enableGameMode') -and $null -ne $S['enableGameMode']) { $enable = [bool]$S['enableGameMode'] }
        $val = if ($enable) { 1 } else { 0 }
        @(
            (New-WibTweak SOFTWARE 'Policies\Microsoft\Windows\GameBar' 'AllowAutoGameMode' DWord $val),
            (New-WibTweak NTUSER 'Software\Microsoft\GameBar' 'AutoGameModeEnabled' DWord $val),
            (New-WibTweak SOFTWARE 'Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR' DWord 0),
            (New-WibTweak NTUSER 'Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' DWord 0)
        )
    }

# ------------------------------------------------------------------ compatibility / setup
Register-WibModule -Id 'hardware-check-bypass' -Order 40 -Risk 'medium' -Reversibility 'journal' -Scope @('install', 'boot') `
    -Description 'Bypass TPM / Secure Boot / CPU / RAM / storage checks during setup. Only needed for unsupported hardware.' `
    -Tradeoff 'Bypasses TPM 2.0, Secure Boot, CPU, RAM, and storage requirement checks during Windows setup. Intended for unsupported hardware.' `
    -Schema @{} `
    -Tweaks @(
        (New-WibTweak DEFAULT 'Control Panel\UnsupportedHardwareNotificationCache' 'SV1' DWord 0),
        (New-WibTweak DEFAULT 'Control Panel\UnsupportedHardwareNotificationCache' 'SV2' DWord 0),
        (New-WibTweak NTUSER 'Control Panel\UnsupportedHardwareNotificationCache' 'SV1' DWord 0),
        (New-WibTweak NTUSER 'Control Panel\UnsupportedHardwareNotificationCache' 'SV2' DWord 0),
        (New-WibTweak SYSTEM 'Setup\LabConfig' 'BypassCPUCheck' DWord 1),
        (New-WibTweak SYSTEM 'Setup\LabConfig' 'BypassRAMCheck' DWord 1),
        (New-WibTweak SYSTEM 'Setup\LabConfig' 'BypassSecureBootCheck' DWord 1),
        (New-WibTweak SYSTEM 'Setup\LabConfig' 'BypassStorageCheck' DWord 1),
        (New-WibTweak SYSTEM 'Setup\LabConfig' 'BypassTPMCheck' DWord 1),
        (New-WibTweak SYSTEM 'Setup\MoSetup' 'AllowUpgradesWithUnsupportedTPMOrCPU' DWord 1)
    )

Register-WibModule -Id 'oobe-local-account' -Order 41 -Risk 'low' -Reversibility 'journal' `
    -Description 'Allow local-account setup (BypassNRO). Optionally ship your own autounattend.xml via setting unattendPath (never downloaded).' `
    -Tradeoff 'Enables BypassNRO to allow creating a local user account without a Microsoft account during OOBE setup.' `
    -Schema @{ unattendPath = 'string' } `
    -Tweaks @( (New-WibTweak SOFTWARE 'Microsoft\Windows\CurrentVersion\OOBE' 'BypassNRO' DWord 1) ) `
    -Plan {
        param($Ctx, $S)
        if ($S.ContainsKey('unattendPath') -and $S['unattendPath']) {
            $src = [string]$S['unattendPath']
            $base = if ($Ctx.ContainsKey('ToolRoot') -and $Ctx.ToolRoot) { $Ctx.ToolRoot } else { (Get-Location).Path }
            $resolved = Resolve-WibConfinedPath -Path $src -BaseDir $base -AllowedExtensions @('.xml')
            New-WibPlanItem 'oobe-local-account' 'Ship unattend file' $resolved '' -Reversibility 'journal'
        }
    } `
    -Apply {
        param($Ctx, $S)
        if (-not ($S.ContainsKey('unattendPath') -and $S['unattendPath'])) { return }
        $src = [string]$S['unattendPath']
        $base = if ($Ctx.ContainsKey('ToolRoot') -and $Ctx.ToolRoot) { $Ctx.ToolRoot } else { (Get-Location).Path }
        try {
            $src = Resolve-WibConfinedPath -Path $src -BaseDir $base -AllowedExtensions @('.xml')
        } catch {
            return (New-WibResult 'oobe-local-account' $src 'failed' $_.Exception.Message)
        }
        if (-not (Test-Path -LiteralPath $src -PathType Leaf)) { return (New-WibResult 'oobe-local-account' $src 'failed' 'unattend file not found or is a directory') }
        $dest = Join-Path $Ctx.MountDir 'Windows\Panther\Unattend'
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        Copy-Item -LiteralPath $src -Destination (Join-Path $dest 'unattend.xml') -Force
        $Ctx.Extras['unattend'] = $src
        New-WibResult 'oobe-local-account' $src 'applied' 'copied to Windows\Panther\Unattend and ISO root'
    }

# ------------------------------------------------------------------ system defaults
Register-WibModule -Id 'reserved-storage-off' -Order 50 -Risk 'medium' -Reversibility 'journal' `
    -Description 'Disable Reserved Storage (frees disk, but updates can fail on a nearly full drive).' `
    -Tradeoff 'Disables reserved disk space allocation (~7GB). Frees disk space, but cumulative updates may fail if the drive is nearly full.' `
    -Schema @{} `
    -Tweaks @( (New-WibTweak SOFTWARE 'Microsoft\Windows\CurrentVersion\ReserveManager' 'ShippedWithReserves' DWord 0) )

Register-WibModule -Id 'bitlocker-auto-encrypt-off' -Order 51 -Risk 'medium' -Reversibility 'journal' `
    -Description 'Prevent automatic BitLocker device encryption (security trade-off).' `
    -Tradeoff 'Prevents automatic BitLocker device encryption on new installations.' `
    -Schema @{} `
    -Tweaks @( (New-WibTweak SYSTEM 'ControlSet001\Control\BitLocker' 'PreventDeviceEncryption' DWord 1) )

Register-WibModule -Id 'chat-icon-off' -Order 52 -Risk 'low' -Reversibility 'journal' `
    -Description 'Hide the taskbar Chat/Meet icon.' `
    -Tradeoff 'Hides the taskbar Chat/Meet icon.' `
    -Schema @{} `
    -Tweaks @(
        (New-WibTweak SOFTWARE 'Policies\Microsoft\Windows\Windows Chat' 'ChatIcon' DWord 3),
        (New-WibTweak NTUSER 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarMn' DWord 0)
    )

Register-WibModule -Id 'network-discovery' -Order 53 -Risk 'low' -Reversibility 'journal' `
    -Description 'Configure SSDP discovery and UPnP services offline.' `
    -Tradeoff 'Disables SSDP Discovery and UPnP services. Eliminates background multicast traffic and latency jitter; prevents discovering local network media devices.' `
    -HardwareHint 'Recommended on gaming PCs and isolated desktop workstations; keep enabled on local home networks sharing printers or media servers.' `
    -Schema @{ disableDiscovery = 'bool' } `
    -TweakProvider {
        param($S)
        $disable = $true
        if ($S.ContainsKey('disableDiscovery') -and $null -ne $S['disableDiscovery']) { $disable = [bool]$S['disableDiscovery'] }
        $val = if ($disable) { 4 } else { 3 }
        @(
            (New-WibTweak SYSTEM 'ControlSet001\Services\SSDPSRV' 'Start' DWord $val),
            (New-WibTweak SYSTEM 'ControlSet001\Services\upnphost' 'Start' DWord $val)
        )
    }

Register-WibModule -Id 'driver-updates-off' -Order 54 -Risk 'low' -Reversibility 'journal' `
    -Description 'Prevent Windows Update from automatically installing or replacing device drivers.' `
    -Tradeoff 'Blocks Windows Update from replacing GPU, chipset, or audio drivers with generic Microsoft WHQL drivers. Requires manual driver installation.' `
    -HardwareHint 'Recommended for discrete GPU gaming setups to prevent Windows Update from overwriting vendor drivers with generic WHQL versions.' `
    -Schema @{} `
    -Tweaks @(
        (New-WibTweak SOFTWARE 'Policies\Microsoft\Windows\WindowsUpdate' 'ExcludeWUDriversInQualityUpdate' DWord 1),
        (New-WibTweak SOFTWARE 'Microsoft\Windows\CurrentVersion\DriverSearching' 'SearchOrderConfig' DWord 0)
    )

Register-WibModule -Id 'timer-resolution' -Order 55 -Risk 'low' -Reversibility 'journal' `
    -Description 'Optimize global system timer resolution and dynamic tick behavior.' `
    -Tradeoff 'Optimizes global kernel timer resolution requests and minimizes input latency for gaming and real-time audio at the cost of slightly increased idle power draw.' `
    -HardwareHint 'Best on desktop PCs connected to AC power; caution on battery-powered laptops as higher timer frequency increases idle CPU power draw.' `
    -Schema @{} `
    -Tweaks @(
        (New-WibTweak SYSTEM 'ControlSet001\Control\Session Manager\kernel' 'GlobalTimerResolutionRequests' DWord 1)
    )

# ------------------------------------------------------------------ performance
Register-WibModule -Id 'visual-effects' -Order 60 -Risk 'low' -Reversibility 'journal' `
    -Description 'Turn off transparency and animations (real compositor/GPU savings, most noticeable on integrated graphics). Settings: disableTransparency, disableAnimations.' `
    -Tradeoff 'Turns off window animations and transparency effects. Yields compositor and GPU memory savings, especially noticeable on integrated GPUs.' `
    -Schema @{ disableTransparency = 'bool'; disableAnimations = 'bool' } `
    -TweakProvider {
        param($S)
        $t = @()
        $transparencyOff = $true; if ($S.ContainsKey('disableTransparency')) { $transparencyOff = [bool]$S['disableTransparency'] }
        $animationsOff = $true;   if ($S.ContainsKey('disableAnimations'))   { $animationsOff = [bool]$S['disableAnimations'] }
        if ($transparencyOff) {
            $t += (New-WibTweak NTUSER 'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' DWord 0)
        }
        if ($animationsOff) {
            $t += (New-WibTweak NTUSER 'Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' DWord 2)
            $t += (New-WibTweak NTUSER 'Control Panel\Desktop\WindowMetrics' 'MinAnimate' String '0')
            $t += (New-WibTweak NTUSER 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarAnimations' DWord 0)
            $t += (New-WibTweak NTUSER 'Control Panel\Desktop' 'UserPreferencesMask' Binary ([byte[]]@(0x90,0x12,0x03,0x80,0x10,0x00,0x00,0x00)))
        }
        $t
    }

Register-WibModule -Id 'background-apps-off' -Order 61 -Risk 'low' -Reversibility 'journal' `
    -Description 'Deny background activity for Store apps by policy (real idle RAM/CPU savings; delays app notifications).' `
    -Tradeoff 'Denies background activity for Store apps by policy. Saves idle RAM and CPU, but delays notifications until apps are opened.' `
    -Schema @{} `
    -Tweaks @( (New-WibTweak SOFTWARE 'Policies\Microsoft\Windows\AppPrivacy' 'LetAppsRunInBackground' DWord 2) )

Register-WibModule -Id 'widgets-off' -Order 62 -Risk 'low' -Reversibility 'journal' `
    -Description 'Disable the Widgets board and its taskbar button.' `
    -Tradeoff 'Disables the Windows Widgets board and taskbar button, freeing Edge WebView background processes.' `
    -Schema @{} `
    -Tweaks @(
        (New-WibTweak SOFTWARE 'Policies\Microsoft\Dsh' 'AllowNewsAndInterests' DWord 0),
        (New-WibTweak NTUSER 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarDa' DWord 0)
    )

Register-WibModule -Id 'search-indexing' -Order 63 -Risk 'medium' -Reversibility 'journal' `
    -Description 'Configure Windows Search (WSearch) service start type offline.' `
    -Tradeoff 'Disabling WSearch reduces background disk and CPU indexing overhead, especially beneficial on lower-end systems or SSD-light profiles. However, searches in File Explorer and Start Menu will be unindexed and slower.' `
    -Schema @{ startType = 'int' } `
    -Validate { param($S) if ($S.ContainsKey('startType') -and ([int]$S['startType'] -notin @(2, 3, 4))) { throw "search-indexing startType must be 2 (Automatic), 3 (Manual), or 4 (Disabled)." } } `
    -TweakProvider {
        param($S)
        $startType = 4
        if ($S.ContainsKey('startType') -and $null -ne $S['startType']) { $startType = [int]$S['startType'] }
        @(
            (New-WibTweak SYSTEM 'ControlSet001\Services\WSearch' 'Start' DWord $startType)
        )
    }

Register-WibModule -Id 'adaptive-hardware' -Order 64 -Risk 'low' -Reversibility 'journal' `
    -Description 'Hardware-adaptive optimizations based on target CPU, RAM, storage, and GPU profile.' `
    -Tradeoff 'Tuning of memory compression, prefetching, and power states dynamically selected based on target hardware metrics.' `
    -HardwareHint 'Evaluates target hardware and applies custom optimizations (e.g. SysMain disable on SSD, memory compression disable on >=16GB RAM).' `
    -Schema @{}

# ------------------------------------------------------------------ storage
Register-WibModule -Id 'component-store-slim' -Order 90 -Risk 'medium' -Reversibility 'permanent' `
    -Description 'Component store cleanup. Default keeps the image serviceable; aggressive=true adds /ResetBase (smaller, but installed updates can no longer be uninstalled).' `
    -Tradeoff 'Performs component store cleanup. Default keeps the image serviceable; aggressive=true adds /ResetBase (smaller, but installed updates can no longer be uninstalled).' `
    -Schema @{ aggressive = 'bool' } `
    -Post {
        param($Ctx, $S)
        $dismArgs = @("/Image:$($Ctx.MountDir)", '/Cleanup-Image', '/StartComponentCleanup')
        $aggr = $false; if ($S.ContainsKey('aggressive')) { $aggr = [bool]$S['aggressive'] }
        if ($aggr) { $dismArgs += '/ResetBase' }
        [void](Invoke-WibNativeTool -ToolKey 'dismExe' -FilePath 'dism.exe' -Arguments $dismArgs)
        if ($LASTEXITCODE -ne 0) { return (New-WibResult 'component-store-slim' ($dismArgs -join ' ') 'failed' "dism exit code $LASTEXITCODE") }
        New-WibResult 'component-store-slim' ($dismArgs -join ' ') 'applied'
    }
