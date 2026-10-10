using System;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Windows;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using WibStudio.Models;
using WibStudio.Services;

namespace WibStudio.ViewModels;

public partial class ArtifactsViewModel : ObservableObject
{
    private readonly ArtifactService _artifactService;
    private readonly StudioBuildViewModel _buildViewModel;

    public ArtifactsViewModel(ArtifactService artifactService, StudioBuildViewModel buildViewModel)
    {
        _artifactService = artifactService;
        _buildViewModel = buildViewModel;

        Artifacts = new ObservableCollection<BuildArtifact>();
        RefreshArtifacts();
    }

    public ObservableCollection<BuildArtifact> Artifacts { get; }

    private BuildArtifact? _selectedArtifact;
    public BuildArtifact? SelectedArtifact
    {
        get => _selectedArtifact;
        set => SetProperty(ref _selectedArtifact, value);
    }

    private string _notificationMessage = "";
    public string NotificationMessage
    {
        get => _notificationMessage;
        set => SetProperty(ref _notificationMessage, value);
    }

    [RelayCommand]
    public void RefreshArtifacts()
    {
        Artifacts.Clear();
        string workspace = _buildViewModel.WorkspacePath;
        var loaded = _artifactService.LoadArtifacts(workspace);

        foreach (var art in loaded)
        {
            Artifacts.Add(art);
        }

        if (SelectedArtifact == null || !Artifacts.Contains(SelectedArtifact))
        {
            SelectedArtifact = Artifacts.FirstOrDefault();
        }

        NotificationMessage = $"Loaded {Artifacts.Count} artifacts from reports directory.";
    }

    [RelayCommand]
    private void OpenInExplorer()
    {
        string dir = Path.Combine(_buildViewModel.WorkspacePath, "reports");
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
            MessageBox.Show($"Could not open directory: {ex.Message}", "Open in Explorer", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }

    [RelayCommand]
    private void CopyPreview()
    {
        if (SelectedArtifact == null || string.IsNullOrEmpty(SelectedArtifact.ContentPreview))
            return;

        try
        {
            Clipboard.SetText(SelectedArtifact.ContentPreview);
            NotificationMessage = $"Copied {SelectedArtifact.FileName} content to clipboard.";
        }
        catch
        {
        }
    }
}
