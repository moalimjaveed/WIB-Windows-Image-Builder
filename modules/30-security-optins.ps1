# High-Risk Opt-In Modules for WIB.
# NEVER allowed in balanced, lean, or adaptive profiles.
# Requires explicit -AcceptRisk flag to validate and apply.
# Strict PowerShell 5.1 compatibility.

# ------------------------------------------------------------------ mitigations-off
Register-WibModule -Id 'mitigations-off' -Order 70 -Risk 'high' -Reversibility 'journal' `
    -Description 'Disable speculative execution CPU side-channel mitigations (Spectre, Meltdown, MDS).' `
    -Tradeoff 'Recovers CPU instruction throughput on older processor microarchitectures (5-15% latency reduction), but leaves the operating system vulnerable to speculative execution attacks from untrusted processes or browser tabs.' `
    -HardwareHint 'Provides noticeable throughput gains on older CPUs (pre-Intel 10th Gen, pre-AMD Zen 3); minimal benefit on modern CPUs with silicon-level mitigations.' `
    -Schema @{} `
    -Tweaks @(
        (New-WibTweak SYSTEM 'ControlSet001\Control\Session Manager\Memory Management' 'FeatureSettingsOverride' DWord 3),
        (New-WibTweak SYSTEM 'ControlSet001\Control\Session Manager\Memory Management' 'FeatureSettingsOverrideMask' DWord 3)
    )

# ------------------------------------------------------------------ defender-off
Register-WibModule -Id 'defender-off' -Order 71 -Risk 'high' -Reversibility 'journal' `
    -Description 'Disable Microsoft Defender Antivirus and real-time monitoring via group policy.' `
    -Tradeoff 'Completely disables Defender real-time scanning, cloud protection, and scheduled scans, freeing idle CPU and disk I/O. Note: DisableAntiSpyware policy is ignored by Windows on modern builds when Tamper Protection is enabled. LEAVES THE SYSTEM UNPROTECTED against malware unless an alternative antivirus solution is actively installed.' `
    -HardwareHint 'Significantly reduces background I/O on lower-tier storage; caution: catastrophic security exposure without replacement protection.' `
    -Schema @{} `
    -Tweaks @(
        (New-WibTweak SOFTWARE 'Policies\Microsoft\Windows Defender' 'DisableAntiSpyware' DWord 1),
        (New-WibTweak SOFTWARE 'Policies\Microsoft\Windows Defender\Real-Time Protection' 'DisableRealtimeMonitoring' DWord 1),
        (New-WibTweak SOFTWARE 'Policies\Microsoft\Windows Defender\Real-Time Protection' 'DisableBehaviorMonitoring' DWord 1),
        (New-WibTweak SOFTWARE 'Policies\Microsoft\Windows Defender\Real-Time Protection' 'DisableOnAccessProtection' DWord 1),
        (New-WibTweak SOFTWARE 'Policies\Microsoft\Windows Defender\Real-Time Protection' 'DisableScanOnRealtimeEnable' DWord 1)
    ) `
    -Plan {
        param($Ctx, $S)
        @(
            (New-WibPlanItem 'defender-off' 'Policy Override' 'Policies\Microsoft\Windows Defender' `
                -Reason 'WARNING: On Windows 11 and Windows 10 1903+, DisableAntiSpyware is strictly ignored by Microsoft Defender when Tamper Protection is active. Offline registry tweaks will not disable MsMpEng.exe unless Tamper Protection is disabled or a registered third-party antivirus is installed.' `
                -Reversibility 'journal')
        )
    }

# ------------------------------------------------------------------ core-isolation-off
Register-WibModule -Id 'core-isolation-off' -Order 72 -Risk 'high' -Reversibility 'journal' `
    -Description 'Disable Virtualization-Based Security (VBS) and Hypervisor-protected Code Integrity (HVCI).' `
    -Tradeoff 'Reduces virtualization CPU overhead and improves game minimum frame rates on older multi-core platforms. Disables hardware-enforced kernel code isolation.' `
    -HardwareHint 'Useful for competitive gaming rigs with older CPUs; disable with caution on machines handling sensitive data.' `
    -Schema @{} `
    -Tweaks @(
        (New-WibTweak SYSTEM 'ControlSet001\Control\DeviceGuard' 'EnableVirtualizationBasedSecurity' DWord 0),
        (New-WibTweak SYSTEM 'ControlSet001\Control\DeviceGuard' 'RequirePlatformSecurityFeatures' DWord 0),
        (New-WibTweak SYSTEM 'ControlSet001\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'Enabled' DWord 0)
    )

# ------------------------------------------------------------------ uac-off
Register-WibModule -Id 'uac-off' -Order 73 -Risk 'high' -Reversibility 'journal' `
    -Description 'Disable User Account Control (UAC) elevation prompts without breaking modern Windows apps.' `
    -Tradeoff 'Silences elevation prompts for administrators (ConsentPromptBehaviorAdmin=0) while keeping LUA enabled to prevent breaking modern Windows apps (Settings, Store, Notepad). Setting disableLua=true fully disables LUA but breaks all packaged/UWP applications.' `
    -HardwareHint 'Eliminates desktop switching latency for automated test benches and kiosk systems.' `
    -Schema @{ disableLua = 'bool' } `
    -TweakProvider {
        param($S)
        $tweaks = @(
            (New-WibTweak SOFTWARE 'Microsoft\Windows\CurrentVersion\Policies\System' 'ConsentPromptBehaviorAdmin' DWord 0)
        )
        if ($S -and $S.ContainsKey('disableLua') -and [bool]$S['disableLua']) {
            $tweaks += (New-WibTweak SOFTWARE 'Microsoft\Windows\CurrentVersion\Policies\System' 'EnableLUA' DWord 0)
        }
        $tweaks
    }

# ------------------------------------------------------------------ firewall-off
Register-WibModule -Id 'firewall-off' -Order 74 -Risk 'high' -Reversibility 'journal' `
    -Description 'Disable Windows Defender Firewall across all network profiles.' `
    -Tradeoff 'Disables packet filtering on Domain, Private, and Public network profiles. Eliminates networking stack overhead and port blocks, but leaves all listening TCP/UDP ports completely open to local network and internet scans.' `
    -HardwareHint 'Useful only in isolated closed test lab networks or specialized hardware testbenches.' `
    -Schema @{} `
    -Tweaks @(
        (New-WibTweak SYSTEM 'ControlSet001\Services\SharedAccess\Parameters\FirewallPolicy\StandardProfile' 'EnableFirewall' DWord 0),
        (New-WibTweak SYSTEM 'ControlSet001\Services\SharedAccess\Parameters\FirewallPolicy\DomainProfile' 'EnableFirewall' DWord 0),
        (New-WibTweak SYSTEM 'ControlSet001\Services\SharedAccess\Parameters\FirewallPolicy\PublicProfile' 'EnableFirewall' DWord 0)
    )
