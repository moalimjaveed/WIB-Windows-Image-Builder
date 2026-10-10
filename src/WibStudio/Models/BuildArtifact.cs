using System;

namespace WibStudio.Models;

public class BuildArtifact
{
    public required string FileName { get; set; }
    public required string FilePath { get; set; }
    public long SizeBytes { get; set; }
    public required string SizeFormatted { get; set; }
    public DateTime LastModified { get; set; }
    public required string FileType { get; set; }
    public required string Status { get; set; }
    public required string ContentPreview { get; set; }

    public string LastModifiedFormatted => LastModified.ToString("yyyy-MM-dd HH:mm:ss");
}
