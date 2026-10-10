# Enterprise Hardening Modules for WIB (Phase 6).
# Focuses on defensive posture, CIS/DISA security baselines, and threat reduction.
# Strict PowerShell 5.1 compatibility.

# ------------------------------------------------------------------ audit-logging
Register-WibModule -Id 'audit-logging' -Order 65 -Risk 'low' -Reversibility 'permanent' `
    -Description 'Enable PowerShell Script Block Logging, Module Logging, and Process Creation CommandLine Auditing.' `
    -Tradeoff 'Captures all executed PowerShell script code and process launch command lines for security incident forensics. Increases Event Log storage volume in Security.evtx and PowerShell/Operational.' `
    -HardwareHint 'Negligible CPU overhead on modern systems; recommended for all enterprise and security-sensitive workstations.' `
    -Schema @{
        scriptBlockLogging  = 'bool'
        moduleLogging       = 'bool'
        commandLineAuditing = 'bool'
    } `
    -TweakProvider {
        param($S)
        $t = @()
        $sb = $true; if ($S.ContainsKey('scriptBlockLogging')) { $sb = [bool]$S['scriptBlockLogging'] }
        $mod = $true; if ($S.ContainsKey('moduleLogging')) { $mod = [bool]$S['moduleLogging'] }
        $cmd = $true; if ($S.ContainsKey('commandLineAuditing')) { $cmd = [bool]$S['commandLineAuditing'] }

        if ($sb) {
            $t += (New-WibTweak SOFTWARE 'Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging' 'EnableScriptBlockLogging' DWord 1)
        }
        if ($mod) {
            $t += (New-WibTweak SOFTWARE 'Policies\Microsoft\Windows\PowerShell\ModuleLogging' 'EnableModuleLogging' DWord 1)
            $t += (New-WibTweak SOFTWARE 'Policies\Microsoft\Windows\PowerShell\ModuleLogging\ModuleNames' '*' String '*')
        }
        if ($cmd) {
            $t += (New-WibTweak SOFTWARE 'Microsoft\Windows\CurrentVersion\Policies\System\Audit' 'ProcessCreationIncludeCmdLine_Enabled' DWord 1)
            $t += (New-WibTweak SYSTEM 'ControlSet001\Control\Lsa' 'SCENoApplyLegacyAuditPolicy' DWord 1)
        }
        $t
    } `
    -Plan {
        param($Ctx, $S)
        $cmd = $true; if ($S.ContainsKey('commandLineAuditing')) { $cmd = [bool]$S['commandLineAuditing'] }
        $items = @()
        if ($cmd) {
            $items += (New-WibPlanItem 'audit-logging' 'Enable Process Creation auditing' 'SetupComplete.cmd' 'invoke auditpol Process Creation subcategory' -Reversibility 'permanent')
        }
        $items
    } `
    -Post {
        param($Ctx, $S)
        $cmd = $true; if ($S.ContainsKey('commandLineAuditing')) { $cmd = [bool]$S['commandLineAuditing'] }
        if ($cmd -and $Ctx.ContainsKey('MountDir') -and (Test-Path -LiteralPath $Ctx.MountDir)) {
            $scriptsDir = Join-Path $Ctx.MountDir 'Windows\Setup\Scripts'
            if (-not (Test-Path -LiteralPath $scriptsDir)) {
                New-Item -ItemType Directory -Force -Path $scriptsDir | Out-Null
            }
            $cmdPath = Join-Path $scriptsDir 'SetupComplete.cmd'
            $line = 'auditpol.exe /set /subcategory:"Process Creation" /success:enable /failure:enable'
            if (Test-Path -LiteralPath $cmdPath) {
                Add-Content -LiteralPath $cmdPath -Value "`r`n$line" -Encoding ASCII
            } else {
                Set-Content -LiteralPath $cmdPath -Value "@echo off`r`n$line`r`n" -Encoding ASCII
            }
            return @(New-WibResult 'audit-logging' 'SetupComplete.cmd' 'applied' 'configured auditpol Process Creation auditing')
        }
        return @()
    }

# ------------------------------------------------------------------ network-hardening
Register-WibModule -Id 'network-hardening' -Order 66 -Risk 'medium' -Reversibility 'journal' `
    -Description 'Harden legacy networking: disable LLMNR, WPAD proxy auto-discovery, and enforce SMB client signing.' `
    -Tradeoff 'Disables Link-Local Multicast Name Resolution (LLMNR) and WPAD to mitigate credential interception and NTLM relay attacks. Enforces SMB client signing which mitigates relay attacks but breaks connectivity to legacy SMB shares or NAS devices without signing support. Legacy local networks lacking local DNS may experience hostname lookup failures.' `
    -HardwareHint 'Essential network hygiene against LAN reconnaissance and rogue responder poisoning.' `
    -Schema @{
        disableLlmnr      = 'bool'
        disableWpad       = 'bool'
        requireSmbSigning = 'bool'
    } `
    -TweakProvider {
        param($S)
        $t = @()
        $llmnr = $true; if ($S.ContainsKey('disableLlmnr')) { $llmnr = [bool]$S['disableLlmnr'] }
        $wpad = $true;  if ($S.ContainsKey('disableWpad')) { $wpad = [bool]$S['disableWpad'] }
        $smb = $true;   if ($S.ContainsKey('requireSmbSigning')) { $smb = [bool]$S['requireSmbSigning'] }

        if ($llmnr) {
            $t += (New-WibTweak SOFTWARE 'Policies\Microsoft\Windows NT\DNSClient' 'EnableMulticast' DWord 0)
        }
        if ($wpad) {
            $t += (New-WibTweak SOFTWARE 'Microsoft\Windows\CurrentVersion\Internet Settings\WinHttp' 'DisableWpad' DWord 1)
        }
        if ($smb) {
            $t += (New-WibTweak SYSTEM 'ControlSet001\Services\LanmanWorkstation\Parameters' 'RequireSecuritySignature' DWord 1)
        }
        $t
    }

# ------------------------------------------------------------------ remote-access-hardening
Register-WibModule -Id 'remote-access-hardening' -Order 67 -Risk 'low' -Reversibility 'journal' `
    -Description 'Enforce Network Level Authentication (NLA) on RDP and restrict anonymous SAM and LSA enumeration.' `
    -Tradeoff 'Requires RDP clients to authenticate prior to establishing an interactive terminal session. Restricts anonymous null-session account scanning.' `
    -HardwareHint 'Standard defense-in-depth configuration for all network-connected systems.' `
    -Schema @{
        enforceNla          = 'bool'
        restrictAnonymousSam = 'bool'
    } `
    -TweakProvider {
        param($S)
        $t = @()
        $nla = $true; if ($S.ContainsKey('enforceNla')) { $nla = [bool]$S['enforceNla'] }
        $sam = $true; if ($S.ContainsKey('restrictAnonymousSam')) { $sam = [bool]$S['restrictAnonymousSam'] }

        if ($nla) {
            $t += (New-WibTweak SYSTEM 'ControlSet001\Control\Terminal Server\WinStations\RDP-Tcp' 'UserAuthentication' DWord 1)
        }
        if ($sam) {
            $t += (New-WibTweak SYSTEM 'ControlSet001\Control\Lsa' 'RestrictAnonymousSAM' DWord 1)
            $t += (New-WibTweak SYSTEM 'ControlSet001\Control\Lsa' 'RestrictAnonymous' DWord 1)
            $t += (New-WibTweak SYSTEM 'ControlSet001\Control\Lsa' 'EveryoneIncludesAnonymous' DWord 0)
        }
        $t
    }

# ------------------------------------------------------------------ defender-hardening
Register-WibModule -Id 'defender-hardening' -Order 68 -Risk 'low' -Reversibility 'journal' `
    -Description 'Enable Potentially Unwanted Application (PUA) blocking and MAPS cloud protection in Windows Defender.' `
    -Tradeoff 'Actively blocks bundlers, adware, and potentially unwanted software. Cloud protection submits anomalous metadata to Microsoft Defender SmartScreen.' `
    -HardwareHint 'Lightweight real-time protection enhancement without noticeable performance impact.' `
    -Schema @{
        puaProtection   = 'bool'
        cloudProtection = 'bool'
    } `
    -TweakProvider {
        param($S)
        $t = @()
        $pua = $true;   if ($S.ContainsKey('puaProtection')) { $pua = [bool]$S['puaProtection'] }
        $cloud = $true; if ($S.ContainsKey('cloudProtection')) { $cloud = [bool]$S['cloudProtection'] }

        if ($pua) {
            $t += (New-WibTweak SOFTWARE 'Policies\Microsoft\Windows Defender' 'PUAProtection' DWord 1)
        }
        if ($cloud) {
            $t += (New-WibTweak SOFTWARE 'Policies\Microsoft\Windows Defender\Spynet' 'SpynetReporting' DWord 2)
            $t += (New-WibTweak SOFTWARE 'Policies\Microsoft\Windows Defender\Spynet' 'SubmitSamplesConsent' DWord 1)
        }
        $t
    }
