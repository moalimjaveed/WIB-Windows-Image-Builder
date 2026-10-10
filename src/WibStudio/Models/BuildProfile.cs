using System.Collections.Generic;

namespace WibStudio.Models;

public class BuildProfile
{
    public required string Key { get; set; }
    public required string DisplayName { get; set; }
    public required string Description { get; set; }
    public RiskLevel Risk { get; set; }
    public required List<string> ActiveModuleIds { get; set; }

    public string RiskText => Risk switch
    {
        RiskLevel.Low => "Low",
        RiskLevel.Medium => "Medium",
        RiskLevel.High => "High",
        _ => "Unknown"
    };

    public string SummaryText => $"Risk: {RiskText} | {ActiveModuleIds.Count} of 19 active";
}
