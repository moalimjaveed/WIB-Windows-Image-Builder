using WibStudio.Services;
using WibStudio.ViewModels;
using Wpf.Ui.Appearance;
using Wpf.Ui.Controls;

namespace WibStudio;

public partial class MainWindow : FluentWindow
{
    public MainWindow()
    {
        InitializeComponent();

        // Initialize Services
        var diagnosticsService = new SystemDiagnosticsService();
        var catalogService = new ProfileCatalogService();
        var buildService = new ImageBuildService();
        var artifactService = new ArtifactService();

        // Initialize ViewModels
        var studioBuildVm = new StudioBuildViewModel(diagnosticsService, catalogService, buildService);
        var moduleInspectorVm = new ModuleInspectorViewModel(catalogService);
        var artifactsVm = new ArtifactsViewModel(artifactService, studioBuildVm);

        var mainVm = new MainViewModel(diagnosticsService, studioBuildVm, moduleInspectorVm, artifactsVm);
        DataContext = mainVm;

        // Apply dark theme initially as per Fluent 2 spec
        ApplicationThemeManager.Apply(ApplicationTheme.Dark);
    }
}