using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using WibStudio.Models;

namespace WibStudio.Services;

public class ArtifactService
{
    public List<BuildArtifact> LoadArtifacts(string workspacePath)
    {
        var searchDirs = new List<string>();

        // 1. Workspace reports directory
        string wsReports = Path.Combine(workspacePath, "reports");
        if (Directory.Exists(wsReports)) searchDirs.Add(wsReports);

        // 2. Repository root reports directory
        string repoReports = WibPathResolver.GetReportsDirectory();
        if (Directory.Exists(repoReports) && !searchDirs.Contains(repoReports))
        {
            searchDirs.Add(repoReports);
        }

        var list = new List<BuildArtifact>();

        foreach (var dir in searchDirs)
        {
            try
            {
                var dirInfo = new DirectoryInfo(dir);

                // Collect files from root
                foreach (var fi in dirInfo.GetFiles())
                {
                    AddArtifact(list, fi, "");
                }

                // Collect files from timestamped session subdirectories (most recent 5 directories)
                foreach (var subDir in dirInfo.GetDirectories().OrderByDescending(d => d.LastWriteTime).Take(8))
                {
                    foreach (var fi in subDir.GetFiles())
                    {
                        AddArtifact(list, fi, subDir.Name);
                    }
                }
            }
            catch
            {
            }
        }

        return list.OrderByDescending(a => a.LastModified).ToList();
    }

    private static void AddArtifact(List<BuildArtifact> list, FileInfo fi, string folderContext)
    {
        string ext = fi.Extension.ToLowerInvariant();
        string typeName = ext switch
        {
            ".json" when fi.Name.Contains("manifest") => "JSON Servicing Manifest",
            ".json" when fi.Name.Contains("terminal") => "Terminal Execution State",
            ".json" => "JSON Data File",
            ".log" => "Servicing Console Log",
            ".html" => "HTML Verification Report",
            ".reg" => "Registry Reversibility Journal",
            ".xml" => "Unattend Configuration",
            ".sha256" => "Cryptographic Hash Digest",
            _ => "Servicing Artifact"
        };

        string preview = "";
        try
        {
            using var stream = fi.OpenRead();
            using var reader = new StreamReader(stream);
            char[] buffer = new char[65536];
            int read = reader.ReadBlock(buffer, 0, buffer.Length);
            preview = new string(buffer, 0, read);
        }
        catch (Exception ex)
        {
            preview = $"[Error reading file: {ex.Message}]";
        }

        string displayName = string.IsNullOrEmpty(folderContext)
            ? fi.Name
            : $"{folderContext} / {fi.Name}";

        list.Add(new BuildArtifact
        {
            FileName = displayName,
            FilePath = fi.FullName,
            SizeBytes = fi.Length,
            SizeFormatted = FormatFileSize(fi.Length),
            LastModified = fi.LastWriteTime,
            FileType = typeName,
            Status = "Verified Clean",
            ContentPreview = preview
        });
    }

    private static string FormatFileSize(long bytes)
    {
        if (bytes < 1024) return $"{bytes} B";
        if (bytes < 1024 * 1024) return $"{Math.Round(bytes / 1024.0, 1)} KB";
        return $"{Math.Round(bytes / (1024.0 * 1024.0), 2)} MB";
    }
}
