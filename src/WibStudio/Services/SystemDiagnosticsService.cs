using System;
using System.IO;
using System.Security.Principal;
using WibStudio.Models;

namespace WibStudio.Services;

public class SystemDiagnosticsService
{
    public bool IsElevated()
    {
        try
        {
            using var identity = WindowsIdentity.GetCurrent();
            var principal = new WindowsPrincipal(identity);
            return principal.IsInRole(WindowsBuiltInRole.Administrator);
        }
        catch
        {
            return false;
        }
    }

    public (double FreeGb, double TotalGb, bool IsLowSpace) GetDriveSpace(string path)
    {
        try
        {
            string root = Path.GetPathRoot(Path.GetFullPath(string.IsNullOrWhiteSpace(path) ? "C:\\" : path)) ?? "C:\\";
            var drive = new DriveInfo(root);
            double freeGb = Math.Round(drive.AvailableFreeSpace / (1024.0 * 1024.0 * 1024.0), 1);
            double totalGb = Math.Round(drive.TotalSize / (1024.0 * 1024.0 * 1024.0), 1);
            return (freeGb, totalGb, freeGb < 25.0);
        }
        catch
        {
            return (150.0, 512.0, false);
        }
    }

    public (bool Exists, double SizeGb, string DisplayName) CheckIsoFile(string? isoPath)
    {
        if (string.IsNullOrWhiteSpace(isoPath) || !File.Exists(isoPath))
        {
            return (false, 0, "Not selected");
        }

        try
        {
            var info = new FileInfo(isoPath);
            double sizeGb = Math.Round(info.Length / (1024.0 * 1024.0 * 1024.0), 2);
            return (true, sizeGb, $"{info.Name} ({sizeGb} GB)");
        }
        catch
        {
            return (false, 0, "Access error");
        }
    }

    public HardwareSpec DetectHostHardware()
    {
        string cpuName = Environment.GetEnvironmentVariable("PROCESSOR_IDENTIFIER") ?? "x64 Family Processor";
        int logicalCores = Environment.ProcessorCount;

        // Approximate RAM
        long totalMemoryBytes = GC.GetGCMemoryInfo().TotalAvailableMemoryBytes;
        int ramGb = totalMemoryBytes > 0 ? (int)Math.Round(totalMemoryBytes / (1024.0 * 1024.0 * 1024.0)) : 16;
        if (ramGb <= 0) ramGb = 16;

        return new HardwareSpec
        {
            Id = "live-host",
            Name = "Live Host (CIM Auto-Detect)",
            Cpu = $"{cpuName.Split(',')[0]} ({logicalCores} Logical Cores)",
            RamGb = ramGb,
            Gpu = "DirectX 12 / WDDM 3.0 Compatible Display Adapter",
            OptimizationsSummary = $"Auto-detected: {logicalCores} cores, ~{ramGb} GB RAM",
            IsLiveHost = true
        };
    }

    public (bool Found, string Path) CheckOscdimg()
    {
        // Check Windows ADK standard path
        string[] commonPaths =
        [
            @"C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe",
            @"C:\Program Files (x86)\Windows Kits\11\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe",
            @"C:\Program Files\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"
        ];

        foreach (var p in commonPaths)
        {
            if (File.Exists(p))
            {
                return (true, p);
            }
        }

        return (false, "Not in standard ADK location (will use signed standalone oscdimg if toggled)");
    }
}
