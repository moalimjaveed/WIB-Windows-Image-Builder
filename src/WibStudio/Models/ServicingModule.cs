using System.Collections.Generic;

namespace WibStudio.Models;

public enum RiskLevel
{
    Low,
    Medium,
    High
}

public enum ReversibilityType
{
    Journaled,
    Reinstallable,
    Permanent
}

public enum ServicingScope
{
    InstallWim,
    BootWim,
    WinPE,
    RegistryHive,
    MediaRoot,
    IsoMedia
}

public class ServicingModule
{
    public required string Id { get; set; }
    public required string Name { get; set; }
    public required string Category { get; set; }
    public RiskLevel Risk { get; set; }
    public ReversibilityType Reversibility { get; set; }
    public ServicingScope Scope { get; set; }
    public required string Description { get; set; }
    public required string TradeOffs { get; set; }
    public required string SecurityImplications { get; set; }
    public required List<string> TargetRegistryKeys { get; set; }
    public required string VerificationHook { get; set; }
    public bool IsActive { get; set; }

    public string RiskBadge => Risk switch
    {
        RiskLevel.Low => "Low Risk",
        RiskLevel.Medium => "Medium Risk",
        RiskLevel.High => "High Risk",
        _ => "Unknown"
    };

    public string ScopeBadge => Scope switch
    {
        ServicingScope.InstallWim => "Install.wim",
        ServicingScope.BootWim => "Boot.wim",
        ServicingScope.WinPE => "WinPE Setup",
        ServicingScope.RegistryHive => "Offline Hive",
        ServicingScope.MediaRoot => "Media Root",
        ServicingScope.IsoMedia => "ISO Media",
        _ => "General"
    };

    public string ReversibilityBadge => Reversibility switch
    {
        ReversibilityType.Journaled => "Journaled (.reg)",
        ReversibilityType.Reinstallable => "Reinstallable (Store)",
        ReversibilityType.Permanent => "Permanent (Media)",
        _ => "Standard"
    };
}
