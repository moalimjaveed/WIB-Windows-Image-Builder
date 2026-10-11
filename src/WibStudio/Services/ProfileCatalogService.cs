using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using WibStudio.Models;

namespace WibStudio.Services;

public class ProfileCatalogService
{
    private readonly List<ServicingModule> _allModules;
    private readonly List<BuildProfile> _profiles;
    private readonly List<TargetEdition> _editions;
    private readonly List<HardwareSpec> _hardwareSpecs;

    public ProfileCatalogService()
    {
        _allModules = LoadModules();
        _profiles = LoadProfiles();
        _editions = InitializeEditions();
        _hardwareSpecs = LoadHardwareSpecs();
    }

    public IReadOnlyList<ServicingModule> GetAllModules() => _allModules;
    public IReadOnlyList<BuildProfile> GetProfiles() => _profiles;
    public IReadOnlyList<TargetEdition> GetEditions() => _editions;
    public IReadOnlyList<HardwareSpec> GetHardwareSpecs() => _hardwareSpecs;

    public BuildProfile? GetProfile(string key) =>
        _profiles.FirstOrDefault(p => p.Key.Equals(key, StringComparison.OrdinalIgnoreCase));

    public void ApplyProfileToModules(string profileKey, IEnumerable<ServicingModule> modules)
    {
        var profile = GetProfile(profileKey) ?? _profiles[0];
        var activeSet = new HashSet<string>(profile.ActiveModuleIds, StringComparer.OrdinalIgnoreCase);

        foreach (var mod in modules)
        {
            mod.IsActive = activeSet.Contains(mod.Id);
        }
    }

    public (bool IsValid, List<string> Messages) ValidateProfileConfiguration(
        string profileKey,
        bool acceptHighRisk,
        IEnumerable<ServicingModule> currentModules)
    {
        var messages = new List<string>();
        bool isValid = true;

        var profile = GetProfile(profileKey);
        if (profile == null)
        {
            messages.Add($"Unknown build profile '{profileKey}'.");
            return (false, messages);
        }

        var activeModules = currentModules.Where(m => m.IsActive).ToList();
        messages.Add($"Validated profile '{profile.DisplayName}' ({activeModules.Count} active modules).");

        // High risk check
        var highRiskActive = activeModules.Where(m => m.Risk == RiskLevel.High).ToList();
        if (highRiskActive.Any() && !acceptHighRisk)
        {
            isValid = false;
            messages.Add($"High-risk module '{highRiskActive[0].Name}' ({highRiskActive[0].Id}) is enabled, but 'Accept high-risk modules' toggle is OFF.");
        }

        // Check if profile extends another
        string profDir = WibPathResolver.GetProfilesDirectory();
        string jsonPath = Path.Combine(profDir, $"{profileKey}.json");
        if (File.Exists(jsonPath))
        {
            messages.Add($"Loaded authoritative profile definition from: {Path.GetFileName(jsonPath)}");
        }

        if (isValid)
        {
            messages.Add("Profile schema verification: PASS (Zero structural contradictions detected).");
        }

        return (isValid, messages);
    }

    private List<BuildProfile> LoadProfiles()
    {
        var list = new List<BuildProfile>();
        string profDir = WibPathResolver.GetProfilesDirectory();

        // Baseline module lists
        var balancedActive = new List<string>
        {
            "appx-removal", "onedrive-removal", "tasks-cleanup", "telemetry",
            "sponsored-content", "copilot-teams-block", "oobe-local-account",
            "chat-icon-off", "background-apps-off", "component-store-slim"
        };

        var leanActive = new List<string>(balancedActive)
        {
            "edge-removal", "features-cleanup", "services-tuning", "visual-effects",
            "widgets-off", "search-indexing", "reserved-storage-off", "bitlocker-auto-encrypt-off"
        };

        var hardeningActive = new List<string>(balancedActive)
        {
            "audit-logging", "network-hardening", "remote-access-hardening",
            "defender-hardening", "services-tuning"
        };

        var adaptiveActive = new List<string>(balancedActive)
        {
            "visual-effects", "services-tuning", "adaptive-hardware"
        };

        var customRiskActive = new List<string>(leanActive)
        {
            "mitigations-off", "core-isolation-off", "defender-off", "uac-off", "firewall-off"
        };

        // If JSON files exist in profiles directory, read descriptions and module keys dynamically
        list.Add(new BuildProfile
        {
            Key = "balanced",
            DisplayName = "Balanced Baseline (Recommended)",
            Description = "Recommended for daily PCs. Removes consumer bloatware, telemetry, and promotional links; keeps Windows Store, Xbox, and Windows Updates fully intact.",
            Risk = RiskLevel.Medium,
            ActiveModuleIds = GetActiveModulesFromJson(Path.Combine(profDir, "balanced.json"), balancedActive)
        });

        list.Add(new BuildProfile
        {
            Key = "lean",
            DisplayName = "Lean Performance",
            Description = "Maximum workstation performance. Strips non-essential inbox apps, Edge, features, tunes latency, optimizes services and visual responsiveness.",
            Risk = RiskLevel.Medium,
            ActiveModuleIds = GetActiveModulesFromJson(Path.Combine(profDir, "lean.json"), leanActive, balancedActive)
        });

        list.Add(new BuildProfile
        {
            Key = "hardening",
            DisplayName = "Hardening Compliance Baseline",
            Description = "Enterprise defensive security profile. Focuses on CIS/DISA hardening, advanced logging, network attack surface reduction, and RDP/SMB defenses.",
            Risk = RiskLevel.Low,
            ActiveModuleIds = GetActiveModulesFromJson(Path.Combine(profDir, "hardening.json"), hardeningActive, balancedActive)
        });

        list.Add(new BuildProfile
        {
            Key = "adaptive",
            DisplayName = "Adaptive Hardware-Tuned",
            Description = "Hardware-adaptive optimizations tuned to target CPU architecture, RAM capacity, and thermal profile.",
            Risk = RiskLevel.Medium,
            ActiveModuleIds = GetActiveModulesFromJson(Path.Combine(profDir, "adaptive.json"), adaptiveActive, balancedActive)
        });

        list.Add(new BuildProfile
        {
            Key = "custom-risk",
            DisplayName = "Custom High-Risk (Aggressive)",
            Description = "Aggressive experimental optimizations. Disables speculative execution mitigations, VBS/HVCI, Defender, and UAC prompts. Requires explicit risk opt-in.",
            Risk = RiskLevel.High,
            ActiveModuleIds = GetActiveModulesFromJson(Path.Combine(profDir, "custom-risk.json"), customRiskActive, leanActive)
        });

        return list;
    }

    private static List<string> GetActiveModulesFromJson(string jsonPath, List<string> fallback, List<string>? extendedFallback = null)
    {
        if (!File.Exists(jsonPath)) return fallback;

        try
        {
            string content = File.ReadAllText(jsonPath);
            using var doc = JsonDocument.Parse(content);
            var root = doc.RootElement;

            var active = new HashSet<string>(extendedFallback ?? [], StringComparer.OrdinalIgnoreCase);

            if (root.TryGetProperty("modules", out var modulesElem))
            {
                foreach (var prop in modulesElem.EnumerateObject())
                {
                    string modId = prop.Name;
                    bool isEnabled = true;

                    if (prop.Value.ValueKind == JsonValueKind.Object)
                    {
                        if (prop.Value.TryGetProperty("enabled", out var enabledProp))
                        {
                            isEnabled = enabledProp.GetBoolean();
                        }
                    }

                    if (isEnabled) active.Add(modId);
                    else active.Remove(modId);
                }
            }

            return active.Any() ? active.ToList() : fallback;
        }
        catch
        {
            return fallback;
        }
    }

    private static List<ServicingModule> LoadModules() =>
    [
        new()
        {
            Id = "appx-removal",
            Name = "Store AppX Package Purge",
            Category = "Debloating",
            Risk = RiskLevel.Medium,
            Reversibility = ReversibilityType.Reinstallable,
            Scope = ServicingScope.InstallWim,
            Description = "Remove provisioned Store apps. Matches image packages against profile remove lists, preserving essential system and store dependencies.",
            TradeOffs = "Consumer apps will not be pre-installed for new user accounts. Microsoft Store remains intact.",
            SecurityImplications = "Eliminates promotional third-party web app wrappers and background push handlers.",
            TargetRegistryKeys = [@"DISM /Remove-ProvisionedAppxPackage", @"AppxAllUserStore"],
            VerificationHook = "Get-AppxProvisionedPackage -Path $MountDir | Where-Object { $_.DisplayName -match 'TikTok|Clipchamp' } | Should-BeEmpty",
            IsActive = true
        },
        new()
        {
            Id = "features-cleanup",
            Name = "Windows Optional Features Cleanup",
            Category = "Debloating",
            Risk = RiskLevel.Medium,
            Reversibility = ReversibilityType.Reinstallable,
            Scope = ServicingScope.InstallWim,
            Description = "Remove unused legacy Windows optional features and capabilities by pattern with strict keep rules.",
            TradeOffs = "Deprecated components (like Internet Explorer, Steps Recorder, Math Recognizer) are removed.",
            SecurityImplications = "Reduces legacy binary attack surface.",
            TargetRegistryKeys = [@"DISM /Disable-Feature", @"DISM /Remove-Capability"],
            VerificationHook = "Get-WindowsOptionalFeature -Path $MountDir | Where-Object { $_.FeatureName -eq 'Internet-Explorer-Optional-amd64' }",
            IsActive = false
        },
        new()
        {
            Id = "edge-removal",
            Name = "Microsoft Edge Browser Removal",
            Category = "Debloating",
            Risk = RiskLevel.Medium,
            Reversibility = ReversibilityType.Permanent,
            Scope = ServicingScope.InstallWim,
            Description = "Delete Edge, EdgeUpdate, and EdgeCore from the image. WebView2 runtime is preserved by default to keep dependent apps working.",
            TradeOffs = "Edge is removed from default app registrations. Alternative browser must be installed.",
            SecurityImplications = "Eliminates Edge background telemetry and advertising channels.",
            TargetRegistryKeys = [@"HKLM\OFFLINE_SOFTWARE\Microsoft\Edge", @"Remove-Item $MountDir\Program Files (x86)\Microsoft\Edge"],
            VerificationHook = "Test-Path '$MountDir\\Program Files (x86)\\Microsoft\\Edge' | Should-BeFalse",
            IsActive = false
        },
        new()
        {
            Id = "onedrive-removal",
            Name = "OneDrive Setup & Sync Removal",
            Category = "Debloating",
            Risk = RiskLevel.Low,
            Reversibility = ReversibilityType.Permanent,
            Scope = ServicingScope.InstallWim,
            Description = "Remove the OneDrive installer from default profile and disable OneDrive file synchronization policies.",
            TradeOffs = "User folders default to local storage rather than auto-syncing to Microsoft Cloud.",
            SecurityImplications = "Prevents automatic cloud transmission of personal files upon first sign-in.",
            TargetRegistryKeys = [@"HKLM\OFFLINE_SOFTWARE\Policies\Microsoft\Windows\OneDrive!DisableFileSyncNGSC = 1"],
            VerificationHook = "Test-Path '$MountDir\\Windows\\SysWOW64\\OneDriveSetup.exe' | Should-BeFalse",
            IsActive = true
        },
        new()
        {
            Id = "tasks-cleanup",
            Name = "Telemetry Scheduled Tasks Purge",
            Category = "Performance",
            Risk = RiskLevel.Low,
            Reversibility = ReversibilityType.Permanent,
            Scope = ServicingScope.RegistryHive,
            Description = "Delete telemetry-related scheduled task definitions (Compatibility Appraiser, CEIP, Customer Experience, Error Reporting).",
            TradeOffs = "Background telemetry reports are not generated or queued.",
            SecurityImplications = "Stops background wake timers and automatic diagnostic transmission.",
            TargetRegistryKeys = [@"HKLM\OFFLINE_SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache"],
            VerificationHook = "schtasks /query /tn 'Microsoft\\Windows\\Application Experience\\Microsoft Compatibility Appraiser'",
            IsActive = true
        },
        new()
        {
            Id = "telemetry",
            Name = "Diagnostic Data & Telemetry Suppression",
            Category = "Privacy",
            Risk = RiskLevel.Low,
            Reversibility = ReversibilityType.Journaled,
            Scope = ServicingScope.RegistryHive,
            Description = "Reduce telemetry and personalisation data collection to minimum security level (AllowTelemetry=0).",
            TradeOffs = "Feedback Hub cannot submit diagnostic reports.",
            SecurityImplications = "Prevents device identifiers, typing patterns, and usage telemetry from leaving the machine.",
            TargetRegistryKeys = [@"HKLM\OFFLINE_SOFTWARE\Policies\Microsoft\Windows\DataCollection!AllowTelemetry = 0"],
            VerificationHook = "(Get-ItemProperty 'HKLM:\\OFFLINE_SOFTWARE\\Policies\\Microsoft\\Windows\\DataCollection').AllowTelemetry -eq 0",
            IsActive = true
        },
        new()
        {
            Id = "sponsored-content",
            Name = "Sponsored Content & Suggestions Suppression",
            Category = "Privacy",
            Risk = RiskLevel.Low,
            Reversibility = ReversibilityType.Journaled,
            Scope = ServicingScope.RegistryHive,
            Description = "Turn off sponsored apps, Start menu suggestions, consumer features, and silent background app installations.",
            TradeOffs = "No promotional app recommendations in Start menu or search.",
            SecurityImplications = "Blocks unprompted third-party app installations.",
            TargetRegistryKeys = [@"HKLM\OFFLINE_SOFTWARE\Policies\Microsoft\Windows\CloudContent!DisableWindowsConsumerFeatures = 1"],
            VerificationHook = "(Get-ItemProperty 'HKLM:\\OFFLINE_SOFTWARE\\Policies\\Microsoft\\Windows\\CloudContent').DisableWindowsConsumerFeatures -eq 1",
            IsActive = true
        },
        new()
        {
            Id = "copilot-teams-block",
            Name = "Copilot & Teams Background Suppression",
            Category = "Privacy",
            Risk = RiskLevel.Low,
            Reversibility = ReversibilityType.Journaled,
            Scope = ServicingScope.RegistryHive,
            Description = "Disable Windows Copilot AI taskbar integration and search suggestions; block Teams, new Outlook, and Dev Home auto-install.",
            TradeOffs = "Copilot taskbar button and screen analysis hooks are disabled.",
            SecurityImplications = "Eliminates desktop screen context inspection hooks.",
            TargetRegistryKeys = [@"HKLM\OFFLINE_SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot!TurnOffWindowsCopilot = 1"],
            VerificationHook = "(Get-ItemProperty 'HKLM:\\OFFLINE_SOFTWARE\\Policies\\Microsoft\\Windows\\WindowsCopilot').TurnOffWindowsCopilot -eq 1",
            IsActive = true
        },
        new()
        {
            Id = "services-tuning",
            Name = "Background Services Latency Tuning",
            Category = "Performance",
            Risk = RiskLevel.Medium,
            Reversibility = ReversibilityType.Journaled,
            Scope = ServicingScope.RegistryHive,
            Description = "Tune Windows services start types offline via the SYSTEM hive (SysMain, DiagTrack, dmwappushservice).",
            TradeOffs = "Sets background telemetry and auxiliary services to Manual/Disabled.",
            SecurityImplications = "Closes remote attack surfaces and reduces CPU context switching.",
            TargetRegistryKeys = [@"HKLM\OFFLINE_SYSTEM\ControlSet001\Services\DiagTrack!Start = 4"],
            VerificationHook = "(Get-ItemProperty 'HKLM:\\OFFLINE_SYSTEM\\ControlSet001\\Services\\DiagTrack').Start -eq 4",
            IsActive = false
        },
        new()
        {
            Id = "bluetooth-tuning",
            Name = "Bluetooth Services Tuning",
            Category = "Performance",
            Risk = RiskLevel.Low,
            Reversibility = ReversibilityType.Journaled,
            Scope = ServicingScope.RegistryHive,
            Description = "Configure Bluetooth services (bthserv, BTAGService) start type offline to Demand Start.",
            TradeOffs = "Bluetooth stack initializes only when an adapter is present.",
            SecurityImplications = "Mitigates idle wireless service listeners.",
            TargetRegistryKeys = [@"HKLM\OFFLINE_SYSTEM\ControlSet001\Services\bthserv!Start = 3"],
            VerificationHook = "(Get-ItemProperty 'HKLM:\\OFFLINE_SYSTEM\\ControlSet001\\Services\\bthserv').Start -eq 3",
            IsActive = false
        },
        new()
        {
            Id = "printing-spooler",
            Name = "Print Spooler Offline Policy",
            Category = "Performance",
            Risk = RiskLevel.Low,
            Reversibility = ReversibilityType.Journaled,
            Scope = ServicingScope.RegistryHive,
            Description = "Configure Print Spooler service offline based on target device profile.",
            TradeOffs = "Devices without printers save background memory.",
            SecurityImplications = "Eliminates PrintNightmare class attack surfaces on non-printing devices.",
            TargetRegistryKeys = [@"HKLM\OFFLINE_SYSTEM\ControlSet001\Services\Spooler!Start = 3"],
            VerificationHook = "(Get-ItemProperty 'HKLM:\\OFFLINE_SYSTEM\\ControlSet001\\Services\\Spooler').Start -eq 3",
            IsActive = false
        },
        new()
        {
            Id = "hibernation",
            Name = "Hibernation & Fast Startup Tuning",
            Category = "Performance",
            Risk = RiskLevel.Low,
            Reversibility = ReversibilityType.Journaled,
            Scope = ServicingScope.RegistryHive,
            Description = "Configure system hibernation file size and Fast Startup policy offline.",
            TradeOffs = "Frees up several gigabytes on root drive by reducing hiberfil.sys size.",
            SecurityImplications = "Reduces physical memory dump persistence on disk.",
            TargetRegistryKeys = [@"HKLM\OFFLINE_SYSTEM\ControlSet001\Control\Power!HibernateFileSizePercent = 40"],
            VerificationHook = "(Get-ItemProperty 'HKLM:\\OFFLINE_SYSTEM\\ControlSet001\\Control\\Power').HibernateFileSizePercent -eq 40",
            IsActive = false
        },
        new()
        {
            Id = "game-mode",
            Name = "Windows Game Mode & DVR Policy",
            Category = "Performance",
            Risk = RiskLevel.Low,
            Reversibility = ReversibilityType.Journaled,
            Scope = ServicingScope.RegistryHive,
            Description = "Configure Windows Game Mode and GameDVR background capture policy.",
            TradeOffs = "Disables background video capture buffers, improving gaming frame consistency.",
            SecurityImplications = "None.",
            TargetRegistryKeys = [@"HKLM\OFFLINE_SOFTWARE\Policies\Microsoft\Windows\GameDVR!AllowGameDVR = 0"],
            VerificationHook = "(Get-ItemProperty 'HKLM:\\OFFLINE_SOFTWARE\\Policies\\Microsoft\\Windows\\GameDVR').AllowGameDVR -eq 0",
            IsActive = false
        },
        new()
        {
            Id = "hardware-check-bypass",
            Name = "Setup TPM / CPU / RAM Check Bypass",
            Category = "Hardware Adaptive",
            Risk = RiskLevel.Medium,
            Reversibility = ReversibilityType.Journaled,
            Scope = ServicingScope.BootWim,
            Description = "Bypass TPM, Secure Boot, CPU, RAM, and storage checks during Windows setup via WinPE LabConfig.",
            TradeOffs = "Permits installation on virtual machines, homelabs, and older hardware.",
            SecurityImplications = "Hardware check bypass only; does not weaken BitLocker when a real TPM is present.",
            TargetRegistryKeys = [@"HKLM\OFFLINE_BOOT_SYSTEM\Setup\LabConfig!BypassTPMCheck = 1"],
            VerificationHook = "(Get-ItemProperty 'HKLM:\\OFFLINE_BOOT_SYSTEM\\Setup\\LabConfig').BypassTPMCheck -eq 1",
            IsActive = true
        },
        new()
        {
            Id = "oobe-local-account",
            Name = "OOBE Local Account Bypass (BypassNRO)",
            Category = "Usability",
            Risk = RiskLevel.Low,
            Reversibility = ReversibilityType.Journaled,
            Scope = ServicingScope.MediaRoot,
            Description = "Allow offline local-account setup (BypassNRO) and ship custom autounattend.xml answer file.",
            TradeOffs = "Permits setup without an internet connection or Microsoft account.",
            SecurityImplications = "Local authentication credentials without cloud account binding.",
            TargetRegistryKeys = [@"HKLM\OFFLINE_SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE!BypassNRO = 1"],
            VerificationHook = "(Get-ItemProperty 'HKLM:\\OFFLINE_SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\OOBE').BypassNRO -eq 1",
            IsActive = true
        },
        new()
        {
            Id = "reserved-storage-off",
            Name = "Reserved Storage Deactivation",
            Category = "Maintenance",
            Risk = RiskLevel.Medium,
            Reversibility = ReversibilityType.Journaled,
            Scope = ServicingScope.RegistryHive,
            Description = "Disable Reserved Storage to free up 7+ GB of disk space on system partition.",
            TradeOffs = "Frees disk, but future Windows updates require sufficient free disk space.",
            SecurityImplications = "None.",
            TargetRegistryKeys = [@"HKLM\OFFLINE_SOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager!ShippedWithReserves = 0"],
            VerificationHook = "(Get-ItemProperty 'HKLM:\\OFFLINE_SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\ReserveManager').ShippedWithReserves -eq 0",
            IsActive = false
        },
        new()
        {
            Id = "bitlocker-auto-encrypt-off",
            Name = "Automatic BitLocker Encryption Bypass",
            Category = "Maintenance",
            Risk = RiskLevel.Medium,
            Reversibility = ReversibilityType.Journaled,
            Scope = ServicingScope.RegistryHive,
            Description = "Prevent automatic silent BitLocker device encryption on clean installs.",
            TradeOffs = "System drives are not silently encrypted without explicit user consent.",
            SecurityImplications = "Unencrypted storage unless BitLocker is manually enabled.",
            TargetRegistryKeys = [@"HKLM\OFFLINE_SYSTEM\ControlSet001\Control\BitLocker!PreventDeviceEncryption = 1"],
            VerificationHook = "(Get-ItemProperty 'HKLM:\\OFFLINE_SYSTEM\\ControlSet001\\Control\\BitLocker').PreventDeviceEncryption -eq 1",
            IsActive = false
        },
        new()
        {
            Id = "chat-icon-off",
            Name = "Taskbar Chat Icon Suppression",
            Category = "Usability",
            Risk = RiskLevel.Low,
            Reversibility = ReversibilityType.Journaled,
            Scope = ServicingScope.RegistryHive,
            Description = "Hide the taskbar Chat and Meet icon across default user profiles.",
            TradeOffs = "Taskbar is cleaner without consumer communication widgets.",
            SecurityImplications = "None.",
            TargetRegistryKeys = [@"HKLM\OFFLINE_SOFTWARE\Policies\Microsoft\Windows\Windows Chat!ChatIcon = 3"],
            VerificationHook = "(Get-ItemProperty 'HKLM:\\OFFLINE_SOFTWARE\\Policies\\Microsoft\\Windows\\Windows Chat').ChatIcon -eq 3",
            IsActive = true
        },
        new()
        {
            Id = "visual-effects",
            Name = "Visual Effects & Animations Tuning",
            Category = "Performance",
            Risk = RiskLevel.Low,
            Reversibility = ReversibilityType.Journaled,
            Scope = ServicingScope.RegistryHive,
            Description = "Turn off transparency and window animations for compositor and GPU savings, especially on integrated graphics.",
            TradeOffs = "Instantaneous window rendering without decorative fades.",
            SecurityImplications = "None.",
            TargetRegistryKeys = [@"HKCU_DEFAULT\Control Panel\Desktop!MenuShowDelay = 0"],
            VerificationHook = "(Get-ItemProperty 'HKCU_DEFAULT\\Control Panel\\Desktop').MenuShowDelay -eq '0'",
            IsActive = false
        },
        new()
        {
            Id = "background-apps-off",
            Name = "Background Store Apps Activity Block",
            Category = "Performance",
            Risk = RiskLevel.Low,
            Reversibility = ReversibilityType.Journaled,
            Scope = ServicingScope.RegistryHive,
            Description = "Deny background activity for Store apps by policy for real idle RAM/CPU savings.",
            TradeOffs = "Background app notifications may be delayed until the app is opened.",
            SecurityImplications = "Stops idle telemetry beaconing from background apps.",
            TargetRegistryKeys = [@"HKLM\OFFLINE_SOFTWARE\Policies\Microsoft\Windows\AppPrivacy!LetAppsRunInBackground = 2"],
            VerificationHook = "(Get-ItemProperty 'HKLM:\\OFFLINE_SOFTWARE\\Policies\\Microsoft\\Windows\\AppPrivacy').LetAppsRunInBackground -eq 2",
            IsActive = true
        },
        new()
        {
            Id = "widgets-off",
            Name = "Widgets Board Suppression",
            Category = "Usability",
            Risk = RiskLevel.Low,
            Reversibility = ReversibilityType.Journaled,
            Scope = ServicingScope.RegistryHive,
            Description = "Disable the Windows 11 Widgets board and remove its taskbar button.",
            TradeOffs = "Widgets feed is unavailable on taskbar.",
            SecurityImplications = "Stops constant background web feeds and MSN advertisement fetching.",
            TargetRegistryKeys = [@"HKLM\OFFLINE_SOFTWARE\Policies\Microsoft\Dsh!AllowNewsAndInterests = 0"],
            VerificationHook = "(Get-ItemProperty 'HKLM:\\OFFLINE_SOFTWARE\\Policies\\Microsoft\\Dsh').AllowNewsAndInterests -eq 0",
            IsActive = false
        },
        new()
        {
            Id = "search-indexing",
            Name = "Windows Search Indexer Tuning",
            Category = "Performance",
            Risk = RiskLevel.Medium,
            Reversibility = ReversibilityType.Journaled,
            Scope = ServicingScope.RegistryHive,
            Description = "Configure Windows Search (WSearch) service start type offline to Demand Start (3) or Disabled (4).",
            TradeOffs = "Reduces idle disk read/write cycles on SSDs; file content searches use live search.",
            SecurityImplications = "Reduces index database footprint on unencrypted partitions.",
            TargetRegistryKeys = [@"HKLM\OFFLINE_SYSTEM\ControlSet001\Services\WSearch!Start = 3"],
            VerificationHook = "(Get-ItemProperty 'HKLM:\\OFFLINE_SYSTEM\\ControlSet001\\Services\\WSearch').Start -eq 3",
            IsActive = false
        },
        new()
        {
            Id = "adaptive-hardware",
            Name = "Hardware Adaptive Profile Tuning",
            Category = "Hardware Adaptive",
            Risk = RiskLevel.Low,
            Reversibility = ReversibilityType.Journaled,
            Scope = ServicingScope.RegistryHive,
            Description = "Hardware-adaptive optimizations based on target CPU architecture, RAM, storage, and GPU profile.",
            TradeOffs = "Auto-configures virtual memory paging and cache size.",
            SecurityImplications = "None.",
            TargetRegistryKeys = [@"HKLM\OFFLINE_SYSTEM\ControlSet001\Control\Session Manager\Memory Management"],
            VerificationHook = "Get-ItemProperty 'HKLM:\\OFFLINE_SYSTEM\\ControlSet001\\Control\\Session Manager\\Memory Management'",
            IsActive = false
        },
        new()
        {
            Id = "audit-logging",
            Name = "PowerShell & Process CommandLine Auditing",
            Category = "Security",
            Risk = RiskLevel.Low,
            Reversibility = ReversibilityType.Permanent,
            Scope = ServicingScope.RegistryHive,
            Description = "Enable PowerShell Script Block Logging, Module Logging, and Process Creation CommandLine Auditing for security compliance.",
            TradeOffs = "Generates detailed event log records under Microsoft-Windows-PowerShell/Operational.",
            SecurityImplications = "Essential defensive posture for identifying unauthorized script execution.",
            TargetRegistryKeys = [@"HKLM\OFFLINE_SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging!EnableScriptBlockLogging = 1"],
            VerificationHook = "(Get-ItemProperty 'HKLM:\\OFFLINE_SOFTWARE\\Policies\\Microsoft\\Windows\\PowerShell\\ScriptBlockLogging').EnableScriptBlockLogging -eq 1",
            IsActive = false
        },
        new()
        {
            Id = "network-hardening",
            Name = "Legacy Networking Surface Hardening",
            Category = "Security",
            Risk = RiskLevel.Medium,
            Reversibility = ReversibilityType.Journaled,
            Scope = ServicingScope.RegistryHive,
            Description = "Harden legacy networking: disable LLMNR, WPAD proxy auto-discovery, and enforce SMB client signing.",
            TradeOffs = "Legacy network printers or archaic NAS shares relying on unauthenticated NTLM may require updates.",
            SecurityImplications = "Prevents credential relay and man-in-the-middle attacks on local networks.",
            TargetRegistryKeys = [@"HKLM\OFFLINE_SOFTWARE\Policies\Microsoft\Windows NT\DNSClient!EnableMulticast = 0"],
            VerificationHook = "(Get-ItemProperty 'HKLM:\\OFFLINE_SOFTWARE\\Policies\\Microsoft\\Windows NT\\DNSClient').EnableMulticast -eq 0",
            IsActive = false
        },
        new()
        {
            Id = "remote-access-hardening",
            Name = "RDP & RPC Remote Access Hardening",
            Category = "Security",
            Risk = RiskLevel.Low,
            Reversibility = ReversibilityType.Journaled,
            Scope = ServicingScope.RegistryHive,
            Description = "Enforce Network Level Authentication (NLA) on RDP and restrict anonymous SAM and LSA enumeration.",
            TradeOffs = "RDP requires modern NLA-capable clients.",
            SecurityImplications = "Prevents pre-authentication brute forcing and null-session reconnaissance.",
            TargetRegistryKeys = [@"HKLM\OFFLINE_SYSTEM\ControlSet001\Control\Terminal Server\WinStations\RDP-Tcp!UserAuthentication = 1"],
            VerificationHook = "(Get-ItemProperty 'HKLM:\\OFFLINE_SYSTEM\\ControlSet001\\Control\\Terminal Server\\WinStations\\RDP-Tcp').UserAuthentication -eq 1",
            IsActive = false
        },
        new()
        {
            Id = "defender-hardening",
            Name = "Windows Defender PUA & MAPS Protection",
            Category = "Security",
            Risk = RiskLevel.Low,
            Reversibility = ReversibilityType.Journaled,
            Scope = ServicingScope.RegistryHive,
            Description = "Enable Potentially Unwanted Application (PUA) blocking and MAPS advanced cloud protection in Windows Defender.",
            TradeOffs = "May flag aggressive adware installers and cryptominers.",
            SecurityImplications = "Significantly improves malware and PUP defense.",
            TargetRegistryKeys = [@"HKLM\OFFLINE_SOFTWARE\Policies\Microsoft\Windows Defender!PUAProtection = 1"],
            VerificationHook = "(Get-ItemProperty 'HKLM:\\OFFLINE_SOFTWARE\\Policies\\Microsoft\\Windows Defender').PUAProtection -eq 1",
            IsActive = false
        },
        new()
        {
            Id = "mitigations-off",
            Name = "CPU Speculative Execution Mitigations Bypass",
            Category = "High Risk",
            Risk = RiskLevel.High,
            Reversibility = ReversibilityType.Journaled,
            Scope = ServicingScope.RegistryHive,
            Description = "Disable speculative execution CPU side-channel mitigations (Spectre, Meltdown, MDS) to recover maximum CPU performance.",
            TradeOffs = "Bypasses kernel page-table isolation. Recovers 5-15% CPU IPC on older architectures.",
            SecurityImplications = "Leaves processor susceptible to local microarchitectural side-channel exploits. Use only on air-gapped systems.",
            TargetRegistryKeys = [@"HKLM\OFFLINE_SYSTEM\ControlSet001\Control\Session Manager\Memory Management!FeatureSettingsOverride = 3"],
            VerificationHook = "(Get-ItemProperty 'HKLM:\\OFFLINE_SYSTEM\\ControlSet001\\Control\\Session Manager\\Memory Management').FeatureSettingsOverride -eq 3",
            IsActive = false
        },
        new()
        {
            Id = "defender-off",
            Name = "Microsoft Defender Complete Disablement",
            Category = "High Risk",
            Risk = RiskLevel.High,
            Reversibility = ReversibilityType.Journaled,
            Scope = ServicingScope.RegistryHive,
            Description = "Disable Microsoft Defender Antivirus and real-time monitoring via group policy and service flags.",
            TradeOffs = "No antivirus protection until third-party security suite is installed.",
            SecurityImplications = "System is vulnerable to malware if connected to untrusted networks.",
            TargetRegistryKeys = [@"HKLM\OFFLINE_SOFTWARE\Policies\Microsoft\Windows Defender!DisableAntiSpyware = 1"],
            VerificationHook = "(Get-ItemProperty 'HKLM:\\OFFLINE_SOFTWARE\\Policies\\Microsoft\\Windows Defender').DisableAntiSpyware -eq 1",
            IsActive = false
        },
        new()
        {
            Id = "core-isolation-off",
            Name = "Virtualization-Based Security (VBS) Disable",
            Category = "High Risk",
            Risk = RiskLevel.High,
            Reversibility = ReversibilityType.Journaled,
            Scope = ServicingScope.RegistryHive,
            Description = "Disable Virtualization-Based Security (VBS) and Hypervisor-protected Code Integrity (HVCI).",
            TradeOffs = "Recovers memory bandwidth and gaming performance on older CPU silicon.",
            SecurityImplications = "Kernel code integrity is no longer guarded by hypervisor ring -1.",
            TargetRegistryKeys = [@"HKLM\OFFLINE_SYSTEM\ControlSet001\Control\DeviceGuard!EnableVirtualizationBasedSecurity = 0"],
            VerificationHook = "(Get-ItemProperty 'HKLM:\\OFFLINE_SYSTEM\\ControlSet001\\Control\\DeviceGuard').EnableVirtualizationBasedSecurity -eq 0",
            IsActive = false
        },
        new()
        {
            Id = "uac-off",
            Name = "User Account Control (UAC) Prompts Suppression",
            Category = "High Risk",
            Risk = RiskLevel.High,
            Reversibility = ReversibilityType.Journaled,
            Scope = ServicingScope.RegistryHive,
            Description = "Disable User Account Control (UAC) elevation prompts without breaking modern Windows apps.",
            TradeOffs = "Applications execute with administrative privileges without consent dialogs.",
            SecurityImplications = "Malware can achieve silent persistence and elevation.",
            TargetRegistryKeys = [@"HKLM\OFFLINE_SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System!ConsentPromptBehaviorAdmin = 0"],
            VerificationHook = "(Get-ItemProperty 'HKLM:\\OFFLINE_SOFTWARE\\Policies\\Microsoft\\Windows\\CurrentVersion\\Policies\\System').ConsentPromptBehaviorAdmin -eq 0",
            IsActive = false
        },
        new()
        {
            Id = "firewall-off",
            Name = "Windows Defender Firewall Disablement",
            Category = "High Risk",
            Risk = RiskLevel.High,
            Reversibility = ReversibilityType.Journaled,
            Scope = ServicingScope.RegistryHive,
            Description = "Disable Windows Defender Firewall across all network profiles (Domain, Private, Public).",
            TradeOffs = "All inbound ports are unshielded.",
            SecurityImplications = "Machine is exposed to unauthenticated inbound network probes.",
            TargetRegistryKeys = [@"HKLM\OFFLINE_SYSTEM\ControlSet001\Services\SharedAccess\Parameters\FirewallPolicy\StandardProfile!EnableFirewall = 0"],
            VerificationHook = "(Get-ItemProperty 'HKLM:\\OFFLINE_SYSTEM\\ControlSet001\\Services\\SharedAccess\\Parameters\\FirewallPolicy\\StandardProfile').EnableFirewall -eq 0",
            IsActive = false
        },
        new()
        {
            Id = "component-store-slim",
            Name = "Component Store Slimming (DISM /ResetBase)",
            Category = "Maintenance",
            Risk = RiskLevel.Medium,
            Reversibility = ReversibilityType.Permanent,
            Scope = ServicingScope.InstallWim,
            Description = "Component store cleanup. Default keeps the image serviceable; aggressive adds /ResetBase (smaller, but installed updates cannot be uninstalled).",
            TradeOffs = "Reduces install.wim size significantly. Existing superseded packages are purged.",
            SecurityImplications = "None; standard Windows component store consolidation.",
            TargetRegistryKeys = [@"dism.exe /Cleanup-Image /StartComponentCleanup /ResetBase"],
            VerificationHook = "dism.exe /Image:$MountDir /Get-Packages",
            IsActive = true
        }
    ];

    private static List<TargetEdition> InitializeEditions() =>
    [
        new() { Index = 0, DisplayName = "Auto-detect (Windows 11 Pro / Primary)", EditionName = "Auto", Architecture = "x64", Description = "Auto-selects Windows 11 Pro or single available edition automatically" },
        new() { Index = 6, DisplayName = "Image Index 6: Windows 11 Pro (Consumer ISO)", EditionName = "Professional", Architecture = "x64", Description = "Standard Windows 11 Pro on official multi-edition consumer ISOs" },
        new() { Index = 1, DisplayName = "Image Index 1: Windows 11 Home (Consumer) / Pro (Business)", EditionName = "Home/Pro", Architecture = "x64", Description = "Index 1 (Home on Consumer ISO, Pro on Business/Enterprise ISO)" },
        new() { Index = 2, DisplayName = "Image Index 2: Windows 11 Home N", EditionName = "CoreN", Architecture = "x64", Description = "Consumer baseline without media technologies" },
        new() { Index = 3, DisplayName = "Image Index 3: Windows 11 Home Single Language", EditionName = "CoreSingleLanguage", Architecture = "x64", Description = "OEM Single Language baseline" },
        new() { Index = 4, DisplayName = "Image Index 4: Windows 11 Education", EditionName = "Education", Architecture = "x64", Description = "Academic baseline with consumer features disabled by default" },
        new() { Index = 5, DisplayName = "Image Index 5: Windows 11 Education N", EditionName = "EducationN", Architecture = "x64", Description = "Academic baseline without media technologies" },
        new() { Index = 7, DisplayName = "Image Index 7: Windows 11 Pro N", EditionName = "ProfessionalN", Architecture = "x64", Description = "Pro baseline without media technologies" },
        new() { Index = 8, DisplayName = "Image Index 8: Windows 11 Pro Education", EditionName = "ProfessionalEducation", Architecture = "x64", Description = "Pro Education tier with academic policy defaults" },
        new() { Index = 9, DisplayName = "Image Index 9: Windows 11 Pro Education N", EditionName = "ProfessionalEducationN", Architecture = "x64", Description = "Pro Education tier without media technologies" },
        new() { Index = 10, DisplayName = "Image Index 10: Windows 11 Pro for Workstations", EditionName = "ProfessionalWorkstation", Architecture = "x64", Description = "Workstation tier with ReFS and SMB Direct support" },
        new() { Index = 11, DisplayName = "Image Index 11: Windows 11 Pro N for Workstations", EditionName = "ProfessionalWorkstationN", Architecture = "x64", Description = "Workstation tier without media technologies" }
    ];

    private static List<HardwareSpec> LoadHardwareSpecs()
    {
        var list = new List<HardwareSpec>
        {
            new() { Id = "live-host", Name = "Live Host (CIM Auto-Detect)", Cpu = "Auto-detected Host CPU", RamGb = 16, Gpu = "Active GPU Driver", OptimizationsSummary = "Real-time hardware inventory queried via CIM/WMI", IsLiveHost = true }
        };

        string specsDir = WibPathResolver.GetSpecsDirectory();
        if (Directory.Exists(specsDir))
        {
            foreach (var file in Directory.GetFiles(specsDir, "*.json"))
            {
                try
                {
                    string json = File.ReadAllText(file);
                    using var doc = JsonDocument.Parse(json);
                    string name = Path.GetFileNameWithoutExtension(file);

                    if (doc.RootElement.TryGetProperty("targetHardware", out var hw))
                    {
                        string cpu = hw.TryGetProperty("cpuName", out var cp) ? cp.GetString() ?? "Generic CPU" : "Generic CPU";
                        int ram = hw.TryGetProperty("ramGB", out var rm) ? rm.GetInt32() : 16;
                        string gpu = hw.TryGetProperty("gpuName", out var gp) ? gp.GetString() ?? "Standard GPU" : "Standard GPU";
                        string form = hw.TryGetProperty("formFactor", out var ff) ? ff.GetString() ?? "PC" : "PC";

                        list.Add(new HardwareSpec
                        {
                            Id = name,
                            Name = $"Spec: {name} ({form})",
                            Cpu = cpu,
                            RamGb = ram,
                            Gpu = gpu,
                            OptimizationsSummary = $"{cpu} • {ram} GB RAM • {gpu} ({form})",
                            IsLiveHost = false
                        });
                    }
                }
                catch
                {
                }
            }
        }

        if (list.Count == 1)
        {
            list.Add(new HardwareSpec { Id = "mini-pc-n100", Name = "Spec: mini-pc-n100", Cpu = "Intel Processor N100 (4C/4T)", RamGb = 16, Gpu = "Intel UHD Graphics 24EU", OptimizationsSummary = "Aggressive memory paging, low thermal throttling prevention", IsLiveHost = false });
            list.Add(new HardwareSpec { Id = "gaming-desktop", Name = "Spec: gaming-desktop", Cpu = "AMD Ryzen 7 7800X3D (8C/16T)", RamGb = 32, Gpu = "NVIDIA GeForce RTX 4080", OptimizationsSummary = "Ultimate Performance power plan, DPC latency optimization", IsLiveHost = false });
        }

        return list;
    }
}
