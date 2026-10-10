namespace WibStudio.Models;

public class HardwareSpec
{
    public required string Id { get; set; }
    public required string Name { get; set; }
    public required string Cpu { get; set; }
    public int RamGb { get; set; }
    public required string Gpu { get; set; }
    public required string OptimizationsSummary { get; set; }
    public bool IsLiveHost { get; set; }

    public string DisplaySummary => $"{Name} ({Cpu} • {RamGb} GB RAM • {Gpu})";
}
