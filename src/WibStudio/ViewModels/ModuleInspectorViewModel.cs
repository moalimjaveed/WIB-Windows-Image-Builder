using System;
using System.Collections.ObjectModel;
using System.Linq;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using WibStudio.Models;
using WibStudio.Services;

namespace WibStudio.ViewModels;

public partial class ModuleInspectorViewModel : ObservableObject
{
    private readonly ProfileCatalogService _catalogService;

    public ModuleInspectorViewModel(ProfileCatalogService catalogService)
    {
        _catalogService = catalogService;

        Profiles = new ObservableCollection<BuildProfile>(_catalogService.GetProfiles());
        _selectedProfile = Profiles[0];

        AllModules = new ObservableCollection<ServicingModule>(_catalogService.GetAllModules());
        FilteredModules = new ObservableCollection<ServicingModule>();

        ApplyProfileSelection();
        FilterModules();

        if (FilteredModules.Any())
        {
            SelectedModule = FilteredModules[0];
        }
    }

    public ObservableCollection<BuildProfile> Profiles { get; }

    private BuildProfile _selectedProfile;
    public BuildProfile SelectedProfile
    {
        get => _selectedProfile;
        set
        {
            if (SetProperty(ref _selectedProfile, value))
            {
                ApplyProfileSelection();
                FilterModules();
            }
        }
    }

    public ObservableCollection<ServicingModule> AllModules { get; }
    public ObservableCollection<ServicingModule> FilteredModules { get; }

    private ServicingModule? _selectedModule;
    public ServicingModule? SelectedModule
    {
        get => _selectedModule;
        set => SetProperty(ref _selectedModule, value);
    }

    private string _searchText = "";
    public string SearchText
    {
        get => _searchText;
        set
        {
            if (SetProperty(ref _searchText, value))
            {
                FilterModules();
            }
        }
    }

    private string _selectedRiskFilter = "All Risks";
    public string SelectedRiskFilter
    {
        get => _selectedRiskFilter;
        set
        {
            if (SetProperty(ref _selectedRiskFilter, value))
            {
                FilterModules();
            }
        }
    }

    public string[] RiskFilters { get; } = ["All Risks", "Low Risk", "Medium Risk", "High Risk"];

    [RelayCommand]
    private void ClearSearch()
    {
        SearchText = "";
        SelectedRiskFilter = "All Risks";
    }

    private void ApplyProfileSelection()
    {
        if (SelectedProfile == null) return;
        _catalogService.ApplyProfileToModules(SelectedProfile.Key, AllModules);
    }

    private void FilterModules()
    {
        FilteredModules.Clear();

        var query = AllModules.AsEnumerable();

        if (!string.IsNullOrWhiteSpace(SearchText))
        {
            string term = SearchText.Trim();
            query = query.Where(m =>
                m.Id.Contains(term, StringComparison.OrdinalIgnoreCase) ||
                m.Name.Contains(term, StringComparison.OrdinalIgnoreCase) ||
                m.Category.Contains(term, StringComparison.OrdinalIgnoreCase) ||
                m.Description.Contains(term, StringComparison.OrdinalIgnoreCase) ||
                m.ScopeBadge.Contains(term, StringComparison.OrdinalIgnoreCase));
        }

        if (SelectedRiskFilter == "Low Risk") query = query.Where(m => m.Risk == RiskLevel.Low);
        else if (SelectedRiskFilter == "Medium Risk") query = query.Where(m => m.Risk == RiskLevel.Medium);
        else if (SelectedRiskFilter == "High Risk") query = query.Where(m => m.Risk == RiskLevel.High);

        foreach (var mod in query)
        {
            FilteredModules.Add(mod);
        }

        if (SelectedModule == null || !FilteredModules.Contains(SelectedModule))
        {
            SelectedModule = FilteredModules.FirstOrDefault();
        }
    }
}
