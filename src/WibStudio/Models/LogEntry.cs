using System;

namespace WibStudio.Models;

public enum LogLevel
{
    Info,
    Success,
    Warning,
    Error,
    Dism,
    Step
}

public class LogEntry
{
    public DateTime Timestamp { get; set; } = DateTime.Now;
    public LogLevel Level { get; set; } = LogLevel.Info;
    public required string Message { get; set; }

    public string TimestampFormatted => Timestamp.ToString("HH:mm:ss.fff");

    public string LevelPrefix => Level switch
    {
        LogLevel.Info => "[INFO]   ",
        LogLevel.Success => "[SUCCESS]",
        LogLevel.Warning => "[WARN]   ",
        LogLevel.Error => "[ERROR]  ",
        LogLevel.Dism => "[DISM]   ",
        LogLevel.Step => "[STEP]   ",
        _ => "[LOG]    "
    };

    public string FullFormattedLine => $"{TimestampFormatted} {LevelPrefix} {Message}";
}
