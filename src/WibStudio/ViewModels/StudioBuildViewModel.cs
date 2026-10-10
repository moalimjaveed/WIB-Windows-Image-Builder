using System;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Threading;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Microsoft.Win32;
using WibStudio.Models;
using WibStudio.Services;

namespace WibStudio.ViewModels;

public partial class StudioBuildViewModel : ObservableObject
{
    private readonly SystemDiagnosticsService _diagnosticsService;
    private readonly ProfileCatalogService _catalogService;
    private readonly ImageBuildService _buildService;
    private readonly DispatcherTimer _timer;
    private DateTime _buildStartTime;
    private CancellationTokenSource? _cts;

    public StudioBuildViewModel(
        SystemDiagnosticsService diagnosticsService,
        ProfileCatalogService catalogService,
        ImageBuildService buildService)
    {
        _diagnosticsService = diagnosticsService;
        _catalogService = catalogService;
        _buildService = buildService;

        _buildService.LogReceived += OnLogReceived;
        _buildService.ProgressChanged += OnProgressChanged;

        _timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        _timer.Tick += (_, _) =>
        {
            if (IsBusy)
            {
                var elapsed = DateTime.Now - _buildStartTime;
                ElapsedTimeText = $"Elapsed: {elapsed:mm\\:ss}";
            }
        };

        // Initialize collections
        Profiles = new ObservableCollection<BuildProfile>(_catalogService.GetProfiles());
        Editions = new ObservableCollection<TargetEdition>(_catalogService.GetEditions());
        HardwareSpecs = new ObservableCollection<HardwareSpec>(_catalogService.GetHardwareSpecs());
        LogEntries = new ObservableCollection<LogEntry>();

        // Set defaults
        SelectedProfile = Profiles[0];
        SelectedEdition = Editions[0];
        SelectedHardware = HardwareSpecs[0];

        WorkspacePath = @"C:\WIB\work";

        UpdatePreflight();
        AppendInitialBanner();
    }

    #region Properties

    private string _isoPath = "";
    public string IsoPath
    {
        get => _isoPath;
        set
        {
            if (SetProperty(ref _isoPath, value))
            {
                UpdatePreflight();
                StartBuildCommand.NotifyCanExecuteChanged();
                PreviewPlanCommand.NotifyCanExecuteChanged();
            }
        }
    }

    private string _workspacePath = @"C:\WIB\work";
    public string WorkspacePath
    {
        get => _workspacePath;
        set
        {
            if (SetProperty(ref _workspacePath, value))
            {
                UpdatePreflight();
            }
        }
    }

    public ObservableCollection<BuildProfile> Profiles { get; }

    private BuildProfile _selectedProfile = null!;
    public BuildProfile SelectedProfile
    {
        get => _selectedProfile;
        set
        {
            if (SetProperty(ref _selectedProfile, value))
            {
                OnPropertyChanged(nameof(ProfileHelperText));
                OnPropertyChanged(nameof(ActiveProfileSummary));
            }
        }
    }

    public ObservableCollection<TargetEdition> Editions { get; }

    private TargetEdition _selectedEdition = null!;
    public TargetEdition SelectedEdition
    {
        get => _selectedEdition;
        set => SetProperty(ref _selectedEdition, value);
    }

    public ObservableCollection<HardwareSpec> HardwareSpecs { get; }

    private HardwareSpec _selectedHardware = null!;
    public HardwareSpec SelectedHardware
    {
        get => _selectedHardware;
        set => SetProperty(ref _selectedHardware, value);
    }

    public string ProfileHelperText => SelectedProfile?.SummaryText ?? "";

    // Toggles
    private bool _isDryRun;
    public bool IsDryRun
    {
        get => _isDryRun;
        set => SetProperty(ref _isDryRun, value);
    }

    private bool _resumeFromCheckpoint;
    public bool ResumeFromCheckpoint
    {
        get => _resumeFromCheckpoint;
        set => SetProperty(ref _resumeFromCheckpoint, value);
    }

    private bool _downloadSignedOscdimg = true;
    public bool DownloadSignedOscdimg
    {
        get => _downloadSignedOscdimg;
        set => SetProperty(ref _downloadSignedOscdimg, value);
    }

    private bool _acceptHighRiskModules;
    public bool AcceptHighRiskModules
    {
        get => _acceptHighRiskModules;
        set => SetProperty(ref _acceptHighRiskModules, value);
    }

    private bool _skipIsoHashVerification;
    public bool SkipIsoHashVerification
    {
        get => _skipIsoHashVerification;
        set => SetProperty(ref _skipIsoHashVerification, value);
    }

    // Preflight Summary Bar
    private string _preflightPrivilege = "Administrator";
    public string PreflightPrivilege
    {
        get => _preflightPrivilege;
        set => SetProperty(ref _preflightPrivilege, value);
    }

    private string _preflightIsoSummary = "Not selected";
    public string PreflightIsoSummary
    {
        get => _preflightIsoSummary;
        set => SetProperty(ref _preflightIsoSummary, value);
    }

    private string _preflightWorkspaceSummary = "Checking...";
    public string PreflightWorkspaceSummary
    {
        get => _preflightWorkspaceSummary;
        set => SetProperty(ref _preflightWorkspaceSummary, value);
    }

    private bool _isLowDiskSpace;
    public bool IsLowDiskSpace
    {
        get => _isLowDiskSpace;
        set => SetProperty(ref _isLowDiskSpace, value);
    }

    public string ActiveProfileSummary => $"{SelectedProfile?.Key ?? "balanced"} ({SelectedProfile?.SummaryText ?? ""})";

    // Activity & Diagnostics Console
    private string _statusText = "Status: Idle - configure inputs and choose Preview Plan or Start Build";
    public string StatusText
    {
        get => _statusText;
        set => SetProperty(ref _statusText, value);
    }

    private string _elapsedTimeText = "Elapsed: 00:00";
    public string ElapsedTimeText
    {
        get => _elapsedTimeText;
        set => SetProperty(ref _elapsedTimeText, value);
    }

    private double _progressValue;
    public double ProgressValue
    {
        get => _progressValue;
        set => SetProperty(ref _progressValue, value);
    }

    private bool _isBusy;
    public bool IsBusy
    {
        get => _isBusy;
        set
        {
            if (SetProperty(ref _isBusy, value))
            {
                OnPropertyChanged(nameof(IsNotBusy));
                StartBuildCommand.NotifyCanExecuteChanged();
                PreviewPlanCommand.NotifyCanExecuteChanged();
                CancelCommand.NotifyCanExecuteChanged();
            }
        }
    }

    public bool IsNotBusy => !IsBusy;

    public ObservableCollection<LogEntry> LogEntries { get; }

    #endregion

    #region Commands

    [RelayCommand]
    private void BrowseIso()
    {
        var dialog = new OpenFileDialog
        {
            Title = "Select Official Windows 11 Source ISO",
            Filter = "Windows Disc Image (*.iso)|*.iso|All Files (*.*)|*.*",
            CheckFileExists = true
        };

        if (dialog.ShowDialog() == true)
        {
            IsoPath = dialog.FileName;
        }
    }

    [RelayCommand]
    private void BrowseWorkspace()
    {
        var dialog = new OpenFolderDialog
        {
            Title = "Select Staging Workspace Directory"
        };

        if (dialog.ShowDialog() == true)
        {
            WorkspacePath = dialog.FolderName;
        }
    }

    [RelayCommand(CanExecute = nameof(CanStartPreviewOrBuild))]
    private async Task PreviewPlanAsync()
    {
        await ExecuteWorkflowAsync(isDryRun: true);
    }

    [RelayCommand(CanExecute = nameof(CanStartPreviewOrBuild))]
    private async Task StartBuildAsync()
    {
        bool isElevated = _diagnosticsService.IsElevated();
        if (!isElevated && !IsDryRun)
        {
            var result = MessageBox.Show(
                "Windows 11 DISM image mounting requires Administrator privileges for live servicing.\n\n" +
                "Would you like to run in Dry-Run Simulation Mode instead to preview the exact servicing actions safely without elevation?",
                "Administrator Elevation Notice",
                MessageBoxButton.YesNo,
                MessageBoxImage.Information);

            if (result == MessageBoxResult.Yes)
            {
                IsDryRun = true;
            }
            else
            {
                return;
            }
        }

        await ExecuteWorkflowAsync(isDryRun: IsDryRun);
    }

    private bool CanStartPreviewOrBuild() => !IsBusy && !string.IsNullOrWhiteSpace(IsoPath);

    [RelayCommand]
    private void ValidateProfile()
    {
        var (isValid, messages) = _catalogService.ValidateProfileConfiguration(
            SelectedProfile.Key,
            AcceptHighRiskModules,
            _catalogService.GetAllModules());

        LogEntries.Add(new LogEntry
        {
            Timestamp = DateTime.Now,
            Level = isValid ? LogLevel.Success : LogLevel.Warning,
            Message = "--- PROFILE VALIDATION AUDIT ---"
        });

        foreach (var msg in messages)
        {
            LogEntries.Add(new LogEntry
            {
                Timestamp = DateTime.Now,
                Level = isValid ? LogLevel.Info : LogLevel.Warning,
                Message = msg
            });
        }
    }

    [RelayCommand(CanExecute = nameof(IsBusy))]
    private void Cancel()
    {
        _cts?.Cancel();
        StatusText = "Status: Cancellation requested...";
    }

    [RelayCommand]
    private void OpenReports()
    {
        string dir = Path.Combine(WorkspacePath, "reports");
        if (!Directory.Exists(dir))
        {
            Directory.CreateDirectory(dir);
        }

        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = dir,
                UseShellExecute = true
            });
        }
        catch (Exception ex)
        {
            MessageBox.Show($"Could not open reports directory: {ex.Message}", "Open Reports", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }

    [RelayCommand]
    private void ClearConsole()
    {
        LogEntries.Clear();
        AppendInitialBanner();
    }

    [RelayCommand]
    private void CopyConsole()
    {
        var sb = new StringBuilder();
        foreach (var entry in LogEntries)
        {
            sb.AppendLine(entry.FullFormattedLine);
        }

        try
        {
            Clipboard.SetText(sb.ToString());
            StatusText = "Status: Console logs copied to clipboard.";
        }
        catch
        {
            // Ignore clipboard lock
        }
    }

    #endregion

    #region Helpers

    private void UpdatePreflight()
    {
        bool isElevated = _diagnosticsService.IsElevated();
        PreflightPrivilege = isElevated ? "Administrator Active" : "Standard User (Preview)";

        var (_, _, isoSummary) = _diagnosticsService.CheckIsoFile(IsoPath);
        PreflightIsoSummary = isoSummary;

        var (freeGb, _, isLow) = _diagnosticsService.GetDriveSpace(WorkspacePath);
        PreflightWorkspaceSummary = $"{freeGb:F1} GB free";
        IsLowDiskSpace = isLow;
    }

    private void AppendInitialBanner()
    {
        LogEntries.Add(new LogEntry
        {
            Timestamp = DateTime.Now,
            Level = LogLevel.Info,
            Message = "Windows Image Builder Studio (WIB Studio) v1.0.0 Ready"
        });
        LogEntries.Add(new LogEntry
        {
            Timestamp = DateTime.Now,
            Level = LogLevel.Info,
            Message = "Configure source media and profile inputs above, then press 'Preview Plan' or 'Start Build'."
        });
    }

    private async Task ExecuteWorkflowAsync(bool isDryRun)
    {
        IsBusy = true;
        _cts = new CancellationTokenSource();
        _buildStartTime = DateTime.Now;
        _timer.Start();

        ProgressValue = 0;
        StatusText = isDryRun ? "Status: Running Dry-Run Simulation..." : "Status: Initializing DISM pipeline...";

        var options = new BuildExecutionOptions
        {
            IsoPath = IsoPath,
            WorkspacePath = WorkspacePath,
            Profile = SelectedProfile,
            Edition = SelectedEdition,
            Hardware = SelectedHardware,
            IsDryRun = isDryRun,
            ResumeFromCheckpoint = ResumeFromCheckpoint,
            DownloadSignedOscdimg = DownloadSignedOscdimg,
            AcceptHighRiskModules = AcceptHighRiskModules,
            SkipIsoHashVerification = SkipIsoHashVerification
        };

        try
        {
            bool success = await _buildService.ExecuteBuildAsync(options, _cts.Token);
            StatusText = success
                ? "Status: Completed successfully (Exit Code 0)"
                : "Status: Execution halted or cancelled";
        }
        catch (OperationCanceledException)
        {
            StatusText = "Status: Servicing cancelled by user.";
        }
        catch (Exception ex)
        {
            StatusText = $"Status: Execution error: {ex.Message}";
            LogEntries.Add(new LogEntry
            {
                Timestamp = DateTime.Now,
                Level = LogLevel.Error,
                Message = $"Unhandled Exception: {ex.Message}"
            });
        }
        finally
        {
            _timer.Stop();
            IsBusy = false;
            _cts.Dispose();
            _cts = null;
        }
    }

    private void OnLogReceived(LogEntry entry)
    {
        Application.Current?.Dispatcher?.Invoke(() =>
        {
            LogEntries.Add(entry);
        });
    }

    private void OnProgressChanged(double progress, string status)
    {
        Application.Current?.Dispatcher?.Invoke(() =>
        {
            ProgressValue = progress;
            StatusText = $"Status: {status}";
        });
    }

    #endregion
}
