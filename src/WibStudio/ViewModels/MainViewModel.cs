using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using System.Windows.Media;
using WibStudio.Services;
using Wpf.Ui.Appearance;
using Wpf.Ui.Controls;

namespace WibStudio.ViewModels;

public partial class MainViewModel : ObservableObject
{
    private readonly SystemDiagnosticsService _diagnosticsService;

    public MainViewModel(
        SystemDiagnosticsService diagnosticsService,
        StudioBuildViewModel studioBuildVm,
        ModuleInspectorViewModel moduleInspectorVm,
        ArtifactsViewModel artifactsVm)
    {
        _diagnosticsService = diagnosticsService;
        StudioBuildVm = studioBuildVm;
        ModuleInspectorVm = moduleInspectorVm;
        ArtifactsVm = artifactsVm;

        IsElevated = _diagnosticsService.IsElevated();
        PrivilegeText = IsElevated
            ? "Elevated Session (Administrator Servicing Active)"
            : "Standard User (Preview Mode)";

        IsDarkTheme = true;
    }

    public StudioBuildViewModel StudioBuildVm { get; }
    public ModuleInspectorViewModel ModuleInspectorVm { get; }
    public ArtifactsViewModel ArtifactsVm { get; }

    public bool IsElevated { get; }
    public string PrivilegeText { get; }

    public SolidColorBrush PrivilegeBadgeBackground => IsElevated
        ? (IsDarkTheme ? new SolidColorBrush(Color.FromRgb(0x14, 0x29, 0x1E)) : new SolidColorBrush(Color.FromRgb(0xDC, 0xFC, 0xE7)))
        : (IsDarkTheme ? new SolidColorBrush(Color.FromRgb(0x2A, 0x1E, 0x11)) : new SolidColorBrush(Color.FromRgb(0xFE, 0xF3, 0xC7)));

    public SolidColorBrush PrivilegeBadgeBorder => IsElevated
        ? (IsDarkTheme ? new SolidColorBrush(Color.FromRgb(0x16, 0xA3, 0x4A)) : new SolidColorBrush(Color.FromRgb(0x86, 0xEF, 0xAC)))
        : (IsDarkTheme ? new SolidColorBrush(Color.FromRgb(0xD9, 0x77, 0x06)) : new SolidColorBrush(Color.FromRgb(0xFC, 0xD3, 0x4D)));

    public SolidColorBrush PrivilegeBadgeForeground => IsElevated
        ? (IsDarkTheme ? new SolidColorBrush(Color.FromRgb(0x4A, 0xDE, 0x80)) : new SolidColorBrush(Color.FromRgb(0x15, 0x80, 0x3D)))
        : (IsDarkTheme ? new SolidColorBrush(Color.FromRgb(0xF5, 0x9E, 0x0B)) : new SolidColorBrush(Color.FromRgb(0xB4, 0x53, 0x09)));

    public SymbolRegular PrivilegeIconSymbol => IsElevated ? SymbolRegular.ShieldCheckmark24 : SymbolRegular.Warning24;

    public SolidColorBrush VersionBadgeBackground => IsDarkTheme
        ? new SolidColorBrush(Color.FromRgb(0x1E, 0x29, 0x3B))
        : new SolidColorBrush(Color.FromRgb(0xE0, 0xF2, 0xFE));

    public SolidColorBrush VersionBadgeBorder => IsDarkTheme
        ? new SolidColorBrush(Color.FromRgb(0x33, 0x41, 0x55))
        : new SolidColorBrush(Color.FromRgb(0xBA, 0xE6, 0xFD));

    public SolidColorBrush VersionBadgeForeground => IsDarkTheme
        ? new SolidColorBrush(Color.FromRgb(0x38, 0xBD, 0xF8))
        : new SolidColorBrush(Color.FromRgb(0x02, 0x84, 0xC7));

    private int _selectedTabIndex;
    public int SelectedTabIndex
    {
        get => _selectedTabIndex;
        set
        {
            if (SetProperty(ref _selectedTabIndex, value))
            {
                // If switching to artifacts, refresh them automatically
                if (value == 2)
                {
                    ArtifactsVm.RefreshArtifacts();
                }
            }
        }
    }

    private bool _isDarkTheme = true;
    public bool IsDarkTheme
    {
        get => _isDarkTheme;
        set
        {
            if (SetProperty(ref _isDarkTheme, value))
            {
                ApplicationThemeManager.Apply(value ? ApplicationTheme.Dark : ApplicationTheme.Light);
                OnPropertyChanged(nameof(PrivilegeBadgeBackground));
                OnPropertyChanged(nameof(PrivilegeBadgeBorder));
                OnPropertyChanged(nameof(PrivilegeBadgeForeground));
                OnPropertyChanged(nameof(VersionBadgeBackground));
                OnPropertyChanged(nameof(VersionBadgeBorder));
                OnPropertyChanged(nameof(VersionBadgeForeground));
                StudioBuildVm.IsDarkTheme = value;
            }
        }
    }

    [RelayCommand]
    private void ToggleTheme()
    {
        IsDarkTheme = !IsDarkTheme;
    }

    [RelayCommand]
    private void SelectTab(string indexStr)
    {
        if (int.TryParse(indexStr, out int idx))
        {
            SelectedTabIndex = idx;
        }
    }
}
