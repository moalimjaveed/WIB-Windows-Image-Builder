namespace WibStudio.Models;

public class TargetEdition
{
    public int Index { get; set; }
    public required string DisplayName { get; set; }
    public required string EditionName { get; set; }
    public required string Architecture { get; set; }
    public required string Description { get; set; }
}
