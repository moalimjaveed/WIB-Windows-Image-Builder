using System;
using System.Windows;
using System.Windows.Input;
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

        // Ensure window fits within the user's available screen work area
        Loaded += (s, e) =>
        {
            var workArea = SystemParameters.WorkArea;
            if (Width > workArea.Width) Width = Math.Max(MinWidth, workArea.Width - 40);
            if (Height > workArea.Height) Height = Math.Max(MinHeight, workArea.Height - 40);
            Left = Math.Max(workArea.Left, workArea.Left + (workArea.Width - Width) / 2);
            Top = Math.Max(workArea.Top, workArea.Top + (workArea.Height - Height) / 2);
        };

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

    private void WindowHeader_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ClickCount == 2)
        {
            WindowState = WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized;
        }
        else if (e.LeftButton == MouseButtonState.Pressed)
        {
            try
            {
                DragMove();
            }
            catch
            {
            }
        }
    }
}