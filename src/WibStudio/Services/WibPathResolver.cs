using System;
using System.IO;

namespace WibStudio.Services;

public static class WibPathResolver
{
    private static string? _cachedRoot;

    public static string GetWibRepositoryRoot()
    {
        if (_cachedRoot != null && Directory.Exists(_cachedRoot))
        {
            return _cachedRoot;
        }

        string[] candidateRoots =
        [
            // When running from tools\WibStudio
            Path.GetFullPath(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "..", "..")),
            // When running from wib root or dev output
            Path.GetFullPath(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "WIB")),
            Path.GetFullPath(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "..", "..", "WIB")),
            Path.GetFullPath(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "..", "..", "..", "WIB")),
            // Current working directory
            Path.GetFullPath(Directory.GetCurrentDirectory()),
            Path.GetFullPath(Path.Combine(Directory.GetCurrentDirectory(), "wib", "WIB")),
            Path.GetFullPath(Path.Combine(Directory.GetCurrentDirectory(), "WIB"))
        ];

        foreach (var dir in candidateRoots)
        {
            if (Directory.Exists(dir) && File.Exists(Path.Combine(dir, "build.ps1")))
            {
                _cachedRoot = dir;
                return dir;
            }
        }

        // Fallback to base directory
        _cachedRoot = AppDomain.CurrentDomain.BaseDirectory;
        return _cachedRoot;
    }

    public static string GetBuildScriptPath()
    {
        string root = GetWibRepositoryRoot();
        string script = Path.Combine(root, "build.ps1");
        if (File.Exists(script)) return script;
        return Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "build.ps1");
    }

    public static string GetProfilesDirectory()
    {
        string root = GetWibRepositoryRoot();
        string dir = Path.Combine(root, "profiles");
        if (Directory.Exists(dir)) return dir;
        return Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "profiles");
    }

    public static string GetModulesDirectory()
    {
        string root = GetWibRepositoryRoot();
        string dir = Path.Combine(root, "modules");
        if (Directory.Exists(dir)) return dir;
        return Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "modules");
    }

    public static string GetSpecsDirectory()
    {
        string root = GetWibRepositoryRoot();
        string dir = Path.Combine(root, "specs");
        if (Directory.Exists(dir)) return dir;
        return Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "specs");
    }

    public static string GetReportsDirectory()
    {
        string root = GetWibRepositoryRoot();
        string dir = Path.Combine(root, "reports");
        if (!Directory.Exists(dir))
        {
            Directory.CreateDirectory(dir);
        }
        return dir;
    }

    public static string GetDefaultWorkspaceDirectory()
    {
        string root = GetWibRepositoryRoot();
        string dir = Path.Combine(root, "work");
        return dir;
    }
}
