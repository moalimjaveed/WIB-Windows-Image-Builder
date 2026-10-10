# Windows Image Builder Studio (WIB Studio)

An authentic **Windows 11 Fluent 2** offline servicing utility built with **C# (.NET 8)**, **WPF**, and the **[WPF-UI](https://wpfui.lepo.co/)** library.

WIB Studio mounts an official Microsoft Windows 11 ISO in an isolated temporary sandbox, applies hardware-adaptive servicing profiles (debloating, telemetry shutdown, hardware check bypasses, latency optimizations), and outputs a bootable, bloat-free `.iso` file.

---

## Key Features & Visual Design

- **Authentic Windows 11 Fluent 2 Experience**: Native Mica material glass backdrop, rounded cards (8px radius, subtle 1px border), fluid layout responsiveness (1280×720 to 1920×1080), and automatic Dark / Light mode switching.
- **Top Header & Session Privilege Pill Badge**:
  - Automatically detects whether the session is running under Standard User (`Standard User (Preview Mode)`) or Administrator (`Elevated Session (Administrator Servicing Active)`).
- **Three-Tab Scientific Architecture**:
  1. **Studio & Build**: Main workspace with Preflight Summary Bar, Configuration Inputs, Profile & Hardware Selectors, Safety Toggles, Action Buttons, and a real-time dark diagnostics console (`#181B20`).
  2. **Module & Profile Inspector**: Interactive data table cataloging all 19 servicing modules with live risk badges, scopes, reversibility journals, search filters, and an in-depth detail card.
  3. **Build Artifacts & Reports**: Manifest, build log, verification report, and reversibility journal inspector with an embedded code previewer.
- **Seamless Script Connection**: Automatically detects and executes your custom `build.ps1` script in the background while streaming terminal logs in real time, or runs the built-in servicing engine.

---

## Project Structure

```text
wib/
├── WibStudio.csproj               # .NET 8 WPF project file (WPF-UI 4.0.3, CommunityToolkit.Mvvm)
├── App.xaml / App.xaml.cs          # WPF-UI theme & control dictionary merging
├── MainWindow.xaml / .cs           # FluentWindow with Mica backdrop, Header, and Tab Navigation
├── Models/
│   ├── ServicingModule.cs          # The 19 offline servicing module definitions & risk metadata
│   ├── BuildProfile.cs             # 5 build profiles (balanced, lean, adaptive, hardening, custom-risk)
│   ├── TargetEdition.cs            # Target Windows editions (Auto-detect, Pro, Home, Enterprise, etc.)
│   ├── HardwareSpec.cs             # CIM auto-detect host specs & hardware templates
│   ├── BuildArtifact.cs            # Manifest, report, journal, and log artifacts
│   └── LogEntry.cs                 # Real-time console log entries with color-coded severity
├── Services/
│   ├── SystemDiagnosticsService.cs # Elevation checks, disk quota calculation, and CIM/WMI hardware specs
│   ├── ProfileCatalogService.cs    # Authoritative module registry and profile dependency validator
│   ├── ImageBuildService.cs        # Asynchronous DISM pipeline & background PowerShell execution
│   └── ArtifactService.cs          # Reads and seeds reports (manifest.json, HTML reports, journal.reg)
├── ViewModels/
│   ├── MainViewModel.cs            # Coordinates header, privileges, theme, and tab routing
│   ├── StudioBuildViewModel.cs     # Main build dashboard, preflight summary, actions, and console stream
│   ├── ModuleInspectorViewModel.cs # Module catalog table, search filters, and detail card inspection
│   └── ArtifactsViewModel.cs       # Artifacts list, explorer launcher, and syntax previewer
├── Views/
│   ├── StudioBuildView.xaml / .cs  # Screen 1: Main build dashboard
│   ├── ModuleInspectorView.xaml / .cs # Screen 2: Module & profile inspector
│   └── ArtifactsView.xaml / .cs    # Screen 3: Build artifacts & reports
├── Resources/
│   ├── Styles.xaml                 # Windows 11 Fluent 2 card styles, brushes, and converters
│   └── Converters.cs               # Type-safe WPF value converters (Risk badges, Log levels, etc.)
└── dist/                           # Compiled release output
```

---

## 19 Servicing Modules Catalog

| Module ID | Category | Risk | Scope | Reversibility |
|---|---|---|---|---|
| `01-appx-removal` | Debloating | Low | Install.wim | Reinstallable (Store) |
| `02-telemetry-block` | Privacy | Low | Registry Hive | Journaled (.reg) |
| `03-edge-debloat` | Debloating | Low | Registry Hive | Journaled (.reg) |
| `04-copilot-disable` | Privacy | Low | Registry Hive | Journaled (.reg) |
| `05-recall-scrub` | Privacy | Medium | Install.wim | Journaled (.reg) |
| `06-onedrive-strip` | Debloating | Medium | Install.wim | Reinstallable |
| `07-defender-tune` | Security | Medium | Registry Hive | Journaled (.reg) |
| `08-services-optimize` | Performance | Medium | Registry Hive | Journaled (.reg) |
| `09-scheduled-tasks` | Performance | Low | Registry Hive | Journaled (.reg) |
| `10-hardware-tpm-bypass` | Hardware Adaptive | Low | Boot.wim / WinPE | Permanent (Media) |
| `11-ram-cpu-check-bypass` | Hardware Adaptive | Low | Boot.wim / WinPE | Permanent (Media) |
| `12-local-account-unattend` | Usability | Low | Media Root | Permanent (Media) |
| `13-pagefile-adaptive` | Performance | Medium | Registry Hive | Journaled (.reg) |
| `14-power-plan-ultimate` | Performance | Low | Registry Hive | Journaled (.reg) |
| `15-visual-fx-streamline` | Performance | Low | Registry Hive | Journaled (.reg) |
| `16-context-menu-classic` | Usability | Low | Registry Hive | Journaled (.reg) |
| `17-storage-sense-policy` | Maintenance | Low | Registry Hive | Journaled (.reg) |
| `18-cortana-websearch-purge` | Privacy | Low | Registry Hive | Journaled (.reg) |
| `19-oscdimg-packager` | ISO Master | Low | ISO Media | Permanent (Media) |

---

## Building and Running

### Prerequisites
- Windows 10/11 (x64)
- .NET 8.0 SDK

### CLI Build & Run
```powershell
# From the wib directory:
dotnet build

# Run in debug mode:
dotnet run

# Publish a production release:
dotnet publish -c Release -o dist
```

Alternatively, launch `wib\dist\WibStudio.exe` directly.
