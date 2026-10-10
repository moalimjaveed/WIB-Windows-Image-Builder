using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using WibStudio.Services;
using Wpf.Ui.Appearance;

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
