#Requires -Version 5.1
<#
.SYNOPSIS
    WIB Builder Studio - Professional Windows 11 Image Builder Desktop Interface.
.DESCRIPTION
    Native WinForms graphical interface adhering to modern Microsoft Fluent design
    principles: restrained typography, unified canvas, neutral status presentation,
    calm action hierarchy, and seamless navigation.
    PowerShell 5.1+ compatible, zero external dependencies.
#>

[CmdletBinding(PositionalBinding = $false)]
param(
    [switch]$NoElevate,
    [string]$ScreenshotPath,
    [switch]$CloseAfterScreenshot,
    [int]$InitialTab = 0,
    [int]$Width = 960,
    [int]$Height = 840
)

$ErrorActionPreference = 'Stop'
$toolRoot = Split-Path -Parent $PSScriptRoot

# Load core WIB libraries and modules for live inspection
$coreLib = Join-Path $toolRoot 'lib\Core.ps1'
if (Test-Path -LiteralPath $coreLib -PathType Leaf) {
    . $coreLib
}
$modDir = Join-Path $toolRoot 'modules'
if (Test-Path -LiteralPath $modDir) {
    Get-ChildItem -LiteralPath $modDir -Filter '*.ps1' | Sort-Object Name | ForEach-Object { . $_.FullName }
}

# Elevation state detection
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and -not $NoElevate) {
    $elevateArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $elevateArgs
    return
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

# ---------------------------------------------------------------------------
# Design Tokens & Palette (Restrained, Unified, Microsoft Fluent 2)
# ---------------------------------------------------------------------------
$theme = @{
    BgWindow        = [System.Drawing.Color]::FromArgb(248, 249, 250)
    BgSurface       = [System.Drawing.Color]::FromArgb(255, 255, 255)
    BorderSubtle    = [System.Drawing.Color]::FromArgb(226, 230, 235)
    BorderInput     = [System.Drawing.Color]::FromArgb(209, 213, 219)
    TextPrimary     = [System.Drawing.Color]::FromArgb(31, 41, 55)
    TextSecondary   = [System.Drawing.Color]::FromArgb(100, 116, 139)
    TextMuted       = [System.Drawing.Color]::FromArgb(148, 163, 184)
    AccentBlue      = [System.Drawing.Color]::FromArgb(15, 108, 189)
    AccentBlueHover = [System.Drawing.Color]::FromArgb(17, 90, 155)
    AccentBlueBg    = [System.Drawing.Color]::FromArgb(235, 243, 252)
    SuccessGreen    = [System.Drawing.Color]::FromArgb(22, 101, 52)
    WarningAmber    = [System.Drawing.Color]::FromArgb(180, 83, 9)
    DangerRed       = [System.Drawing.Color]::FromArgb(185, 28, 28)
    BtnSecondaryBg  = [System.Drawing.Color]::FromArgb(255, 255, 255)
    BtnSecondaryFg  = [System.Drawing.Color]::FromArgb(55, 65, 81)
    BtnDisabledBg   = [System.Drawing.Color]::FromArgb(241, 245, 249)
    BtnDisabledFg   = [System.Drawing.Color]::FromArgb(156, 163, 175)
    TerminalBg      = [System.Drawing.Color]::FromArgb(24, 27, 32)
    TerminalFg      = [System.Drawing.Color]::FromArgb(226, 232, 240)
}

# Typography Hierarchy (Native Windows Segoe UI for crisp ClearType rendering)
$fontFamily = 'Segoe UI'

$fonts = @{
    AppTitle    = New-Object System.Drawing.Font($fontFamily, 14, [System.Drawing.FontStyle]::Bold)
    SectionHdr  = New-Object System.Drawing.Font($fontFamily, 10.5, [System.Drawing.FontStyle]::Bold)
    SubHdr      = New-Object System.Drawing.Font($fontFamily, 9, [System.Drawing.FontStyle]::Bold)
    Body        = New-Object System.Drawing.Font($fontFamily, 9, [System.Drawing.FontStyle]::Regular)
    Small       = New-Object System.Drawing.Font($fontFamily, 8.5, [System.Drawing.FontStyle]::Regular)
    SmallBold   = New-Object System.Drawing.Font($fontFamily, 8.5, [System.Drawing.FontStyle]::Bold)
    Console     = New-Object System.Drawing.Font('Consolas', 9.5, [System.Drawing.FontStyle]::Regular)
}

# ---------------------------------------------------------------------------
# Main Application Form
# ---------------------------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text = "WIB: Windows Image Builder Studio"
$form.Size = New-Object System.Drawing.Size($Width, $Height)
$form.MinimumSize = New-Object System.Drawing.Size(920, 700)
$form.StartPosition = 'CenterScreen'
$form.Font = $fonts.Body
$form.BackColor = $theme.BgWindow

# ---------------------------------------------------------------------------
# 1. Header Area: 2-column TableLayoutPanel (100% + AutoSize)
# ---------------------------------------------------------------------------
$pnlHeader = New-Object System.Windows.Forms.TableLayoutPanel
$pnlHeader.Dock = 'Top'
$pnlHeader.Height = 66
$pnlHeader.BackColor = $theme.BgWindow
$pnlHeader.Padding = New-Object System.Windows.Forms.Padding(24, 12, 24, 0)
$pnlHeader.RowCount = 1
$pnlHeader.ColumnCount = 2
[void]$pnlHeader.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$pnlHeader.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize)))
[void]$pnlHeader.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))

# Left cell: Title & Subtitle in FlowLayoutPanel
$pnlTitleGroup = New-Object System.Windows.Forms.FlowLayoutPanel
$pnlTitleGroup.Dock = 'Fill'
$pnlTitleGroup.FlowDirection = 'TopDown'
$pnlTitleGroup.WrapContents = $false
$pnlTitleGroup.Margin = New-Object System.Windows.Forms.Padding(0)

$lblAppTitle = New-Object System.Windows.Forms.Label
$lblAppTitle.Text = "Windows Image Builder Studio"
$lblAppTitle.Font = $fonts.AppTitle
$lblAppTitle.ForeColor = $theme.TextPrimary
$lblAppTitle.AutoSize = $true
$lblAppTitle.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 2)
$pnlTitleGroup.Controls.Add($lblAppTitle)

$lblAppSub = New-Object System.Windows.Forms.Label
$lblAppSub.Text = "Hardware-adaptive, verifiable Windows 11 offline servicing engine"
$lblAppSub.Font = $fonts.Small
$lblAppSub.ForeColor = $theme.TextSecondary
$lblAppSub.AutoSize = $true
$lblAppSub.Margin = New-Object System.Windows.Forms.Padding(1, 0, 0, 0)
$pnlTitleGroup.Controls.Add($lblAppSub)
$pnlHeader.Controls.Add($pnlTitleGroup, 0, 0)

# Right cell: Session info badge
$lblSessionInfo = New-Object System.Windows.Forms.Label
if ($isAdmin) {
    $lblSessionInfo.Text = "Elevated Session (Administrator Servicing Active)"
} else {
    $lblSessionInfo.Text = "Standard User (Preview Mode - Live builds require elevation)"
}
$lblSessionInfo.Font = $fonts.Small
$lblSessionInfo.ForeColor = $theme.TextSecondary
$lblSessionInfo.AutoSize = $true
$lblSessionInfo.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$lblSessionInfo.Margin = New-Object System.Windows.Forms.Padding(0, 6, 0, 0)
$pnlHeader.Controls.Add($lblSessionInfo, 1, 0)
$form.Controls.Add($pnlHeader)

# ---------------------------------------------------------------------------
# 2. Modern Navigation Bar (Tabs)
# ---------------------------------------------------------------------------
$pnlNav = New-Object System.Windows.Forms.FlowLayoutPanel
$pnlNav.Dock = 'Top'
$pnlNav.Height = 36
$pnlNav.BackColor = $theme.BgWindow
$pnlNav.Padding = New-Object System.Windows.Forms.Padding(24, 0, 24, 0)
$pnlNav.Margin = New-Object System.Windows.Forms.Padding(0)
$form.Controls.Add($pnlNav)

$pnlContent = New-Object System.Windows.Forms.Panel
$pnlContent.Dock = 'Fill'
$pnlContent.BackColor = $theme.BgWindow

# Root Tab Containers (TableLayoutPanel)
$tabStudio = New-Object System.Windows.Forms.TableLayoutPanel
$tabStudio.Dock = 'Fill'
$tabStudio.BackColor = $theme.BgWindow
$tabStudio.Padding = New-Object System.Windows.Forms.Padding(24, 6, 24, 16)
$tabStudio.ColumnCount = 1
$tabStudio.RowCount = 7
[void]$tabStudio.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$tabStudio.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
[void]$tabStudio.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
[void]$tabStudio.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
[void]$tabStudio.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
[void]$tabStudio.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
[void]$tabStudio.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
[void]$tabStudio.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$pnlContent.Controls.Add($tabStudio)

$tabModules = New-Object System.Windows.Forms.TableLayoutPanel
$tabModules.Dock = 'Fill'
$tabModules.BackColor = $theme.BgWindow
$tabModules.Padding = New-Object System.Windows.Forms.Padding(24, 8, 24, 16)
$tabModules.ColumnCount = 1
$tabModules.RowCount = 4
[void]$tabModules.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$tabModules.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
[void]$tabModules.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 65)))
[void]$tabModules.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
[void]$tabModules.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 35)))
$tabModules.Visible = $false
$pnlContent.Controls.Add($tabModules)

$tabReports = New-Object System.Windows.Forms.TableLayoutPanel
$tabReports.Dock = 'Fill'
$tabReports.BackColor = $theme.BgWindow
$tabReports.Padding = New-Object System.Windows.Forms.Padding(24, 8, 24, 16)
$tabReports.ColumnCount = 1
$tabReports.RowCount = 5
[void]$tabReports.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$tabReports.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
[void]$tabReports.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
[void]$tabReports.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 45)))
[void]$tabReports.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
[void]$tabReports.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 55)))
$tabReports.Visible = $false
$pnlContent.Controls.Add($tabReports)

$tabPages = @($tabStudio, $tabModules, $tabReports)

# Navigation Buttons
$tabNames = @("Studio & Build", "Module & Profile Inspector", "Build Artifacts & Reports")
$navButtons = New-Object System.Collections.ArrayList

function Select-Tab {
    param([int]$Index)
    for ($k = 0; $k -lt $tabPages.Count; $k++) {
        if ($k -eq $Index) {
            $tabPages[$k].Visible = $true
            $tabPages[$k].BringToFront()
            $navButtons[$k].BackColor = $theme.BgSurface
            $navButtons[$k].ForeColor = $theme.AccentBlue
        } else {
            $tabPages[$k].Visible = $false
            $navButtons[$k].BackColor = $theme.BgWindow
            $navButtons[$k].ForeColor = $theme.TextSecondary
        }
    }
}

for ($i = 0; $i -lt $tabNames.Count; $i++) {
    $nBtn = New-Object System.Windows.Forms.Button
    $nBtn.Text = $tabNames[$i]
    $nBtn.Tag = $i
    $nBtn.UseMnemonic = $false
    $nBtn.Font = $fonts.Body
    $nBtn.Size = New-Object System.Drawing.Size(190, 30)
    $nBtn.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)
    $nBtn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $nBtn.FlatAppearance.BorderSize = 0
    $nBtn.Cursor = [System.Windows.Forms.Cursors]::Hand
    
    $nBtn.Add_Click({
        param($s, $e)
        Select-Tab ([int]$s.Tag)
    })
    
    if ($i -eq 0) {
        $nBtn.BackColor = $theme.BgSurface
        $nBtn.ForeColor = $theme.AccentBlue
    } else {
        $nBtn.BackColor = $theme.BgWindow
        $nBtn.ForeColor = $theme.TextSecondary
    }
    
    $pnlNav.Controls.Add($nBtn)
    [void]$navButtons.Add($nBtn)
}

# Add pnlContent to form (Dock order: Fill first, then Top panels)
$form.Controls.Add($pnlContent)
$form.Controls.SetChildIndex($pnlContent, 0)
$form.Controls.SetChildIndex($pnlNav, 1)
$form.Controls.SetChildIndex($pnlHeader, 2)

# ===========================================================================
# TAB 1: STUDIO & BUILD (Automatic Layout Engine via TableLayoutPanel)
# ===========================================================================

# ---------------- Row 0: Preflight Summary ----------------
$pnlPreflight = New-Object System.Windows.Forms.Panel
$pnlPreflight.Dock = 'Fill'
$pnlPreflight.Height = 32
$pnlPreflight.BackColor = $theme.BgSurface
$pnlPreflight.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$pnlPreflight.Padding = New-Object System.Windows.Forms.Padding(12, 6, 12, 6)
$pnlPreflight.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)

$lblPreflightSummary = New-Object System.Windows.Forms.Label
$lblPreflightSummary.Text = "Privileges: Standard User    |    Source ISO: Not selected    |    Workspace: Checking...    |    Profile: balanced"
$lblPreflightSummary.Font = $fonts.Small
$lblPreflightSummary.ForeColor = $theme.TextSecondary
$lblPreflightSummary.Dock = 'Fill'
$lblPreflightSummary.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$pnlPreflight.Controls.Add($lblPreflightSummary)
$tabStudio.Controls.Add($pnlPreflight, 0, 0)

# ---------------- Row 1: Configuration Header ----------------
$pnlConfigHdr = New-Object System.Windows.Forms.FlowLayoutPanel
$pnlConfigHdr.Dock = 'Fill'
$pnlConfigHdr.FlowDirection = 'TopDown'
$pnlConfigHdr.AutoSize = $true
$pnlConfigHdr.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 6)

$lblConfigHdr = New-Object System.Windows.Forms.Label
$lblConfigHdr.Text = "Configuration"
$lblConfigHdr.Font = $fonts.SectionHdr
$lblConfigHdr.ForeColor = $theme.TextPrimary
$lblConfigHdr.AutoSize = $true
$lblConfigHdr.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 2)
$pnlConfigHdr.Controls.Add($lblConfigHdr)

$lblConfigDesc = New-Object System.Windows.Forms.Label
$lblConfigDesc.Text = "Specify the source installation image, staging workspace, and target hardware profile."
$lblConfigDesc.Font = $fonts.Small
$lblConfigDesc.ForeColor = $theme.TextSecondary
$lblConfigDesc.AutoSize = $true
$pnlConfigHdr.Controls.Add($lblConfigDesc)
$tabStudio.Controls.Add($pnlConfigHdr, 0, 1)

# ---------------- Row 2: Inputs Grid (Nested TableLayoutPanel) ----------------
$pnlInputs = New-Object System.Windows.Forms.TableLayoutPanel
$pnlInputs.Dock = 'Fill'
$pnlInputs.AutoSize = $true
$pnlInputs.ColumnCount = 1
$pnlInputs.RowCount = 5
$pnlInputs.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)
[void]$pnlInputs.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
for ($r = 0; $r -lt 5; $r++) {
    [void]$pnlInputs.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
}

# Input 1: Source ISO Label
$lblIso = New-Object System.Windows.Forms.Label
$lblIso.Text = "Source ISO Image"
$lblIso.Font = $fonts.Small
$lblIso.ForeColor = $theme.TextSecondary
$lblIso.AutoSize = $true
$lblIso.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 2)
$pnlInputs.Controls.Add($lblIso, 0, 0)

# Input 1: Source ISO Box + Browse (2-column layout: 100% + 105px)
$tblIsoRow = New-Object System.Windows.Forms.TableLayoutPanel
$tblIsoRow.Dock = 'Fill'
$tblIsoRow.Height = 28
$tblIsoRow.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)
$tblIsoRow.ColumnCount = 2
$tblIsoRow.RowCount = 1
[void]$tblIsoRow.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$tblIsoRow.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 105)))
[void]$tblIsoRow.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))

$txtIso = New-Object System.Windows.Forms.TextBox
$txtIso.Font = $fonts.Body
$txtIso.Dock = 'Fill'
$txtIso.Margin = New-Object System.Windows.Forms.Padding(0, 2, 8, 2)
$tblIsoRow.Controls.Add($txtIso, 0, 0)

$btnBrowseIso = New-Object System.Windows.Forms.Button
$btnBrowseIso.Text = "Browse..."
$btnBrowseIso.UseMnemonic = $false
$btnBrowseIso.Font = $fonts.Body
$btnBrowseIso.Dock = 'Fill'
$btnBrowseIso.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnBrowseIso.BackColor = $theme.BtnSecondaryBg
$btnBrowseIso.ForeColor = $theme.BtnSecondaryFg
$btnBrowseIso.Margin = New-Object System.Windows.Forms.Padding(0)
$tblIsoRow.Controls.Add($btnBrowseIso, 1, 0)
$pnlInputs.Controls.Add($tblIsoRow, 0, 1)

# Input 2: Staging Workspace Label
$lblWork = New-Object System.Windows.Forms.Label
$lblWork.Text = "Staging Workspace"
$lblWork.Font = $fonts.Small
$lblWork.ForeColor = $theme.TextSecondary
$lblWork.AutoSize = $true
$lblWork.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 2)
$pnlInputs.Controls.Add($lblWork, 0, 2)

# Input 2: Staging Workspace Box + Browse
$tblWorkRow = New-Object System.Windows.Forms.TableLayoutPanel
$tblWorkRow.Dock = 'Fill'
$tblWorkRow.Height = 28
$tblWorkRow.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)
$tblWorkRow.ColumnCount = 2
$tblWorkRow.RowCount = 1
[void]$tblWorkRow.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$tblWorkRow.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 105)))
[void]$tblWorkRow.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))

$txtWork = New-Object System.Windows.Forms.TextBox
$txtWork.Font = $fonts.Body
$txtWork.Text = Join-Path $toolRoot 'work'
$txtWork.Dock = 'Fill'
$txtWork.Margin = New-Object System.Windows.Forms.Padding(0, 2, 8, 2)
$tblWorkRow.Controls.Add($txtWork, 0, 0)

$btnBrowseWork = New-Object System.Windows.Forms.Button
$btnBrowseWork.Text = "Browse..."
$btnBrowseWork.UseMnemonic = $false
$btnBrowseWork.Font = $fonts.Body
$btnBrowseWork.Dock = 'Fill'
$btnBrowseWork.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnBrowseWork.BackColor = $theme.BtnSecondaryBg
$btnBrowseWork.ForeColor = $theme.BtnSecondaryFg
$btnBrowseWork.Margin = New-Object System.Windows.Forms.Padding(0)
$tblWorkRow.Controls.Add($btnBrowseWork, 1, 0)
$pnlInputs.Controls.Add($tblWorkRow, 0, 3)

# Input 3: The 3 Selectors (3 equal percentage columns: 33.3%, 33.3%, 33.4%)
$tblSelectors = New-Object System.Windows.Forms.TableLayoutPanel
$tblSelectors.Dock = 'Fill'
$tblSelectors.AutoSize = $true
$tblSelectors.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 4)
$tblSelectors.ColumnCount = 3
$tblSelectors.RowCount = 1
[void]$tblSelectors.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 33.3)))
[void]$tblSelectors.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 33.3)))
[void]$tblSelectors.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 33.4)))
[void]$tblSelectors.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))

# Column 1: Build Profile
$pnlCol1 = New-Object System.Windows.Forms.TableLayoutPanel
$pnlCol1.Dock = 'Fill'
$pnlCol1.AutoSize = $true
$pnlCol1.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 0)
$pnlCol1.ColumnCount = 1
$pnlCol1.RowCount = 3
[void]$pnlCol1.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))

$lblProfile = New-Object System.Windows.Forms.Label
$lblProfile.Text = "Build Profile"
$lblProfile.Font = $fonts.Small
$lblProfile.ForeColor = $theme.TextSecondary
$lblProfile.AutoSize = $true
$lblProfile.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 2)
$pnlCol1.Controls.Add($lblProfile, 0, 0)

$cmbProfile = New-Object System.Windows.Forms.ComboBox
$cmbProfile.DropDownStyle = 'DropDownList'
$cmbProfile.Font = $fonts.Body
$cmbProfile.Dock = 'Fill'
$pnlCol1.Controls.Add($cmbProfile, 0, 1)

$lblProfileDetails = New-Object System.Windows.Forms.Label
$lblProfileDetails.Font = $fonts.Small
$lblProfileDetails.ForeColor = $theme.TextSecondary
$lblProfileDetails.AutoSize = $true
$lblProfileDetails.Margin = New-Object System.Windows.Forms.Padding(0, 3, 0, 0)
$pnlCol1.Controls.Add($lblProfileDetails, 0, 2)
$tblSelectors.Controls.Add($pnlCol1, 0, 0)

# Column 2: Target Edition
$pnlCol2 = New-Object System.Windows.Forms.TableLayoutPanel
$pnlCol2.Dock = 'Fill'
$pnlCol2.AutoSize = $true
$pnlCol2.Margin = New-Object System.Windows.Forms.Padding(5, 0, 5, 0)
$pnlCol2.ColumnCount = 1
$pnlCol2.RowCount = 2
[void]$pnlCol2.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))

$lblEdition = New-Object System.Windows.Forms.Label
$lblEdition.Text = "Target Edition"
$lblEdition.Font = $fonts.Small
$lblEdition.ForeColor = $theme.TextSecondary
$lblEdition.AutoSize = $true
$lblEdition.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 2)
$pnlCol2.Controls.Add($lblEdition, 0, 0)

$cmbEdition = New-Object System.Windows.Forms.ComboBox
$cmbEdition.DropDownStyle = 'DropDownList'
$cmbEdition.Font = $fonts.Body
$cmbEdition.Dock = 'Fill'
[void]$cmbEdition.Items.Add("Auto-detect (Single Edition)")
for ($idx = 1; $idx -le 11; $idx++) {
    [void]$cmbEdition.Items.Add("Image Index $idx")
}
$cmbEdition.SelectedIndex = 0
$pnlCol2.Controls.Add($cmbEdition, 0, 1)
$tblSelectors.Controls.Add($pnlCol2, 1, 0)

# Column 3: Hardware Profile
$pnlCol3 = New-Object System.Windows.Forms.TableLayoutPanel
$pnlCol3.Dock = 'Fill'
$pnlCol3.AutoSize = $true
$pnlCol3.Margin = New-Object System.Windows.Forms.Padding(10, 0, 0, 0)
$pnlCol3.ColumnCount = 1
$pnlCol3.RowCount = 2
[void]$pnlCol3.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))

$lblHardware = New-Object System.Windows.Forms.Label
$lblHardware.Text = "Hardware Profile"
$lblHardware.Font = $fonts.Small
$lblHardware.ForeColor = $theme.TextSecondary
$lblHardware.AutoSize = $true
$lblHardware.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 2)
$pnlCol3.Controls.Add($lblHardware, 0, 0)

$cmbHardware = New-Object System.Windows.Forms.ComboBox
$cmbHardware.DropDownStyle = 'DropDownList'
$cmbHardware.Font = $fonts.Body
$cmbHardware.Dock = 'Fill'
[void]$cmbHardware.Items.Add("Live Host (CIM Auto-Detect)")
$specsDir = Join-Path $toolRoot 'specs'
if (Test-Path -LiteralPath $specsDir) {
    Get-ChildItem -LiteralPath $specsDir -Filter '*.json' | ForEach-Object {
        $specBase = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
        [void]$cmbHardware.Items.Add("Spec: $specBase")
    }
}
$cmbHardware.SelectedIndex = 0
$pnlCol3.Controls.Add($cmbHardware, 0, 1)
$tblSelectors.Controls.Add($pnlCol3, 2, 0)

$pnlInputs.Controls.Add($tblSelectors, 0, 4)
$tabStudio.Controls.Add($pnlInputs, 0, 2)

# ---------------- Row 3: Options Checkboxes ----------------
$pnlOptions = New-Object System.Windows.Forms.FlowLayoutPanel
$pnlOptions.Dock = 'Fill'
$pnlOptions.AutoSize = $true
$pnlOptions.WrapContents = $true
$pnlOptions.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)

$chkDryRun = New-Object System.Windows.Forms.CheckBox
$chkDryRun.Text = "Dry-run simulation only"
$chkDryRun.Font = $fonts.Body
$chkDryRun.ForeColor = $theme.TextPrimary
$chkDryRun.AutoSize = $true
$chkDryRun.Margin = New-Object System.Windows.Forms.Padding(0, 0, 20, 6)
$pnlOptions.Controls.Add($chkDryRun)

$chkResume = New-Object System.Windows.Forms.CheckBox
$chkResume.Text = "Resume from checkpoint"
$chkResume.Font = $fonts.Body
$chkResume.ForeColor = $theme.TextPrimary
$chkResume.AutoSize = $true
$chkResume.Margin = New-Object System.Windows.Forms.Padding(0, 0, 20, 6)
$pnlOptions.Controls.Add($chkResume)

$chkDownloadOscd = New-Object System.Windows.Forms.CheckBox
$chkDownloadOscd.Text = "Download signed oscdimg"
$chkDownloadOscd.Font = $fonts.Body
$chkDownloadOscd.ForeColor = $theme.TextPrimary
$chkDownloadOscd.AutoSize = $true
$chkDownloadOscd.Margin = New-Object System.Windows.Forms.Padding(0, 0, 20, 6)
$pnlOptions.Controls.Add($chkDownloadOscd)

$chkAcceptRisk = New-Object System.Windows.Forms.CheckBox
$chkAcceptRisk.Text = "Accept high-risk modules"
$chkAcceptRisk.Font = $fonts.Body
$chkAcceptRisk.ForeColor = $theme.TextSecondary
$chkAcceptRisk.AutoSize = $true
$chkAcceptRisk.Margin = New-Object System.Windows.Forms.Padding(0, 0, 20, 6)
$pnlOptions.Controls.Add($chkAcceptRisk)

$chkSkipHash = New-Object System.Windows.Forms.CheckBox
$chkSkipHash.Text = "Skip ISO hash verification"
$chkSkipHash.Font = $fonts.Body
$chkSkipHash.ForeColor = $theme.TextSecondary
$chkSkipHash.AutoSize = $true
$chkSkipHash.Margin = New-Object System.Windows.Forms.Padding(0, 0, 20, 6)
$pnlOptions.Controls.Add($chkSkipHash)
$tabStudio.Controls.Add($pnlOptions, 0, 3)

# ---------------- Row 4: Action Buttons (Left actions + Right utilities) ----------------
$tblActions = New-Object System.Windows.Forms.TableLayoutPanel
$tblActions.Dock = 'Fill'
$tblActions.Height = 36
$tblActions.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)
$tblActions.ColumnCount = 2
$tblActions.RowCount = 1
[void]$tblActions.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$tblActions.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 160)))
[void]$tblActions.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))

# Left primary action buttons
$flowActionsLeft = New-Object System.Windows.Forms.FlowLayoutPanel
$flowActionsLeft.Dock = 'Fill'
$flowActionsLeft.Margin = New-Object System.Windows.Forms.Padding(0)

$btnPlan = New-Object System.Windows.Forms.Button
$btnPlan.Text = "Preview Plan"
$btnPlan.Font = $fonts.Body
$btnPlan.Size = New-Object System.Drawing.Size(125, 32)
$btnPlan.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnPlan.BackColor = $theme.AccentBlue
$btnPlan.ForeColor = [System.Drawing.Color]::White
$btnPlan.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)
$flowActionsLeft.Controls.Add($btnPlan)

$btnBuild = New-Object System.Windows.Forms.Button
$btnBuild.Text = "Start Build"
$btnBuild.Font = $fonts.Body
$btnBuild.Size = New-Object System.Drawing.Size(125, 32)
$btnBuild.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnBuild.BackColor = $theme.BtnDisabledBg
$btnBuild.ForeColor = $theme.BtnDisabledFg
$btnBuild.Enabled = $false
$btnBuild.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)
$flowActionsLeft.Controls.Add($btnBuild)

$btnValidate = New-Object System.Windows.Forms.Button
$btnValidate.Text = "Validate Profile"
$btnValidate.Font = $fonts.Body
$btnValidate.Size = New-Object System.Drawing.Size(125, 32)
$btnValidate.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnValidate.BackColor = $theme.BtnSecondaryBg
$btnValidate.ForeColor = $theme.BtnSecondaryFg
$btnValidate.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)
$flowActionsLeft.Controls.Add($btnValidate)

$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Text = "Cancel"
$btnCancel.Font = $fonts.Body
$btnCancel.Size = New-Object System.Drawing.Size(95, 32)
$btnCancel.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnCancel.BackColor = $theme.BtnDisabledBg
$btnCancel.ForeColor = $theme.BtnDisabledFg
$btnCancel.Enabled = $false
$btnCancel.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)
$flowActionsLeft.Controls.Add($btnCancel)

$btnOpenReports = New-Object System.Windows.Forms.Button
$btnOpenReports.Text = "Open Reports"
$btnOpenReports.Font = $fonts.Body
$btnOpenReports.Size = New-Object System.Drawing.Size(115, 32)
$btnOpenReports.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnOpenReports.BackColor = $theme.BtnSecondaryBg
$btnOpenReports.ForeColor = $theme.BtnSecondaryFg
$btnOpenReports.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)
$flowActionsLeft.Controls.Add($btnOpenReports)
$tblActions.Controls.Add($flowActionsLeft, 0, 0)

# Right utilities (Clear, Copy)
$flowActionsRight = New-Object System.Windows.Forms.FlowLayoutPanel
$flowActionsRight.Dock = 'Fill'
$flowActionsRight.Margin = New-Object System.Windows.Forms.Padding(0)
$flowActionsRight.FlowDirection = 'RightToLeft'

$btnCopyLog = New-Object System.Windows.Forms.Button
$btnCopyLog.Text = "Copy"
$btnCopyLog.Font = $fonts.Small
$btnCopyLog.Size = New-Object System.Drawing.Size(75, 32)
$btnCopyLog.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnCopyLog.BackColor = $theme.BtnSecondaryBg
$btnCopyLog.ForeColor = $theme.BtnSecondaryFg
$btnCopyLog.Margin = New-Object System.Windows.Forms.Padding(0)
$flowActionsRight.Controls.Add($btnCopyLog)

$btnClearLog = New-Object System.Windows.Forms.Button
$btnClearLog.Text = "Clear"
$btnClearLog.Font = $fonts.Small
$btnClearLog.Size = New-Object System.Drawing.Size(70, 32)
$btnClearLog.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnClearLog.BackColor = $theme.BtnSecondaryBg
$btnClearLog.ForeColor = $theme.BtnSecondaryFg
$btnClearLog.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)
$flowActionsRight.Controls.Add($btnClearLog)
$tblActions.Controls.Add($flowActionsRight, 1, 0)
$tabStudio.Controls.Add($tblActions, 0, 4)

# ---------------- Row 5: Activity Header + Progress Bar ----------------
$pnlActContainer = New-Object System.Windows.Forms.TableLayoutPanel
$pnlActContainer.Dock = 'Fill'
$pnlActContainer.AutoSize = $true
$pnlActContainer.ColumnCount = 2
$pnlActContainer.RowCount = 2
$pnlActContainer.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 4)
[void]$pnlActContainer.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$pnlActContainer.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize)))
[void]$pnlActContainer.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
[void]$pnlActContainer.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 6)))

$flowActLeft = New-Object System.Windows.Forms.FlowLayoutPanel
$flowActLeft.Dock = 'Fill'
$flowActLeft.AutoSize = $true
$flowActLeft.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 2)

$lblActHdr = New-Object System.Windows.Forms.Label
$lblActHdr.Text = "Activity & Diagnostics"
$lblActHdr.UseMnemonic = $false
$lblActHdr.Font = $fonts.SectionHdr
$lblActHdr.ForeColor = $theme.TextPrimary
$lblActHdr.AutoSize = $true
$lblActHdr.Margin = New-Object System.Windows.Forms.Padding(0, 0, 16, 0)
$flowActLeft.Controls.Add($lblActHdr)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = "Status: Idle - configure inputs and choose Preview Plan or Start Build"
$lblStatus.Font = $fonts.Small
$lblStatus.ForeColor = $theme.TextSecondary
$lblStatus.AutoSize = $true
$lblStatus.Margin = New-Object System.Windows.Forms.Padding(0, 2, 0, 0)
$flowActLeft.Controls.Add($lblStatus)
$pnlActContainer.Controls.Add($flowActLeft, 0, 0)

$lblElapsed = New-Object System.Windows.Forms.Label
$lblElapsed.Text = "Elapsed: 00:00"
$lblElapsed.Font = $fonts.Small
$lblElapsed.ForeColor = $theme.TextSecondary
$lblElapsed.AutoSize = $true
$lblElapsed.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$lblElapsed.Margin = New-Object System.Windows.Forms.Padding(0, 2, 0, 0)
$pnlActContainer.Controls.Add($lblElapsed, 1, 0)

$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Dock = 'Fill'
$progressBar.Height = 4
$progressBar.Margin = New-Object System.Windows.Forms.Padding(0)
$pnlActContainer.SetColumnSpan($progressBar, 2)
$pnlActContainer.Controls.Add($progressBar, 0, 1)
$tabStudio.Controls.Add($pnlActContainer, 0, 5)

# ---------------- Row 6: Terminal Console (Fills ALL remaining space!) ----------------
$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Multiline = $true
$txtLog.ReadOnly = $true
$txtLog.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$txtLog.Font = $fonts.Console
$txtLog.BackColor = $theme.TerminalBg
$txtLog.ForeColor = $theme.TerminalFg
$txtLog.Dock = 'Fill'
$txtLog.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$txtLog.Margin = New-Object System.Windows.Forms.Padding(0)
$tabStudio.Controls.Add($txtLog, 0, 6)

# ===========================================================================
# TAB 2: MODULE & PROFILE INSPECTOR (Automatic Layout via TableLayoutPanel)
# ===========================================================================
$pnlModHdr = New-Object System.Windows.Forms.FlowLayoutPanel
$pnlModHdr.Dock = 'Fill'
$pnlModHdr.FlowDirection = 'TopDown'
$pnlModHdr.AutoSize = $true
$pnlModHdr.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)

$lblModTitle = New-Object System.Windows.Forms.Label
$lblModTitle.Text = "Module Catalog & Architecture"
$lblModTitle.UseMnemonic = $false
$lblModTitle.Font = $fonts.SectionHdr
$lblModTitle.ForeColor = $theme.TextPrimary
$lblModTitle.AutoSize = $true
$lblModTitle.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 2)
$pnlModHdr.Controls.Add($lblModTitle)

$lblModHelp = New-Object System.Windows.Forms.Label
$lblModHelp.Text = "Inspect all 19 offline servicing modules, risk levels, reversibility tiers, and execution tradeoffs."
$lblModHelp.Font = $fonts.Small
$lblModHelp.ForeColor = $theme.TextSecondary
$lblModHelp.AutoSize = $true
$pnlModHdr.Controls.Add($lblModHelp)
$tabModules.Controls.Add($pnlModHdr, 0, 0)

$listModules = New-Object System.Windows.Forms.ListView
$listModules.Dock = 'Fill'
$listModules.View = [System.Windows.Forms.View]::Details
$listModules.FullRowSelect = $true
$listModules.GridLines = $true
$listModules.Font = $fonts.Body
$listModules.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$listModules.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)
[void]$listModules.Columns.Add("Status", 75)
[void]$listModules.Columns.Add("Module ID", 190)
[void]$listModules.Columns.Add("Risk", 80)
[void]$listModules.Columns.Add("Reversibility", 110)
[void]$listModules.Columns.Add("Scope", 85)
[void]$listModules.Columns.Add("Description & Trade-offs", 340)

# Responsive column stretching for Description
$listModules.Add_Resize({
    param($s, $e)
    $fixedWidth = 75 + 190 + 80 + 110 + 85 + 25
    $remainder = $listModules.ClientSize.Width - $fixedWidth
    if ($remainder -gt 320) {
        $listModules.Columns[5].Width = $remainder
    }
})
$tabModules.Controls.Add($listModules, 0, 1)

$lblModDetailTitle = New-Object System.Windows.Forms.Label
$lblModDetailTitle.Text = "Selected Module Details & Trade-offs:"
$lblModDetailTitle.UseMnemonic = $false
$lblModDetailTitle.Font = $fonts.SubHdr
$lblModDetailTitle.ForeColor = $theme.TextPrimary
$lblModDetailTitle.AutoSize = $true
$lblModDetailTitle.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 4)
$tabModules.Controls.Add($lblModDetailTitle, 0, 2)

$txtModDetail = New-Object System.Windows.Forms.TextBox
$txtModDetail.Font = $fonts.Body
$txtModDetail.Multiline = $true
$txtModDetail.ReadOnly = $true
$txtModDetail.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$txtModDetail.Dock = 'Fill'
$txtModDetail.BackColor = $theme.BgSurface
$txtModDetail.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$txtModDetail.Margin = New-Object System.Windows.Forms.Padding(0)
$tabModules.Controls.Add($txtModDetail, 0, 3)

# ===========================================================================
# TAB 3: BUILD ARTIFACTS & REPORTS (Automatic Layout via TableLayoutPanel)
# ===========================================================================
$pnlRepHdr = New-Object System.Windows.Forms.FlowLayoutPanel
$pnlRepHdr.Dock = 'Fill'
$pnlRepHdr.FlowDirection = 'TopDown'
$pnlRepHdr.AutoSize = $true
$pnlRepHdr.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 6)

$lblRepTitle = New-Object System.Windows.Forms.Label
$lblRepTitle.Text = "Build Artifacts & Generated Reports"
$lblRepTitle.UseMnemonic = $false
$lblRepTitle.Font = $fonts.SectionHdr
$lblRepTitle.ForeColor = $theme.TextPrimary
$lblRepTitle.AutoSize = $true
$lblRepTitle.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 2)
$pnlRepHdr.Controls.Add($lblRepTitle)

$lblRepHelp = New-Object System.Windows.Forms.Label
$lblRepHelp.Text = "Review manifests, verification reports, and logs generated in the staging directory."
$lblRepHelp.Font = $fonts.Small
$lblRepHelp.ForeColor = $theme.TextSecondary
$lblRepHelp.AutoSize = $true
$pnlRepHdr.Controls.Add($lblRepHelp)
$tabReports.Controls.Add($pnlRepHdr, 0, 0)

$flowRepButtons = New-Object System.Windows.Forms.FlowLayoutPanel
$flowRepButtons.Dock = 'Fill'
$flowRepButtons.AutoSize = $true
$flowRepButtons.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)

$btnRefreshReports = New-Object System.Windows.Forms.Button
$btnRefreshReports.Text = "Refresh Artifacts"
$btnRefreshReports.Font = $fonts.Body
$btnRefreshReports.Size = New-Object System.Drawing.Size(130, 30)
$btnRefreshReports.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnRefreshReports.BackColor = $theme.BtnSecondaryBg
$btnRefreshReports.ForeColor = $theme.BtnSecondaryFg
$btnRefreshReports.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)
$flowRepButtons.Controls.Add($btnRefreshReports)

$btnOpenReportsDir = New-Object System.Windows.Forms.Button
$btnOpenReportsDir.Text = "Open in Explorer"
$btnOpenReportsDir.Font = $fonts.Body
$btnOpenReportsDir.Size = New-Object System.Drawing.Size(130, 30)
$btnOpenReportsDir.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnOpenReportsDir.BackColor = $theme.BtnSecondaryBg
$btnOpenReportsDir.ForeColor = $theme.BtnSecondaryFg
$btnOpenReportsDir.Margin = New-Object System.Windows.Forms.Padding(0)
$flowRepButtons.Controls.Add($btnOpenReportsDir)
$tabReports.Controls.Add($flowRepButtons, 0, 1)

$listReports = New-Object System.Windows.Forms.ListView
$listReports.Dock = 'Fill'
$listReports.View = [System.Windows.Forms.View]::Details
$listReports.FullRowSelect = $true
$listReports.GridLines = $true
$listReports.Font = $fonts.Body
$listReports.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$listReports.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)
[void]$listReports.Columns.Add("Artifact Name", 280)
[void]$listReports.Columns.Add("Size", 100)
[void]$listReports.Columns.Add("Last Modified", 180)
[void]$listReports.Columns.Add("Type", 120)

# Responsive column stretching for Artifact Name
$listReports.Add_Resize({
    param($s, $e)
    $fixedWidth = 100 + 180 + 120 + 25
    $remainder = $listReports.ClientSize.Width - $fixedWidth
    if ($remainder -gt 250) {
        $listReports.Columns[0].Width = $remainder
    }
})
$tabReports.Controls.Add($listReports, 0, 2)

$lblPreviewTitle = New-Object System.Windows.Forms.Label
$lblPreviewTitle.Text = "Artifact Content Preview:"
$lblPreviewTitle.Font = $fonts.SubHdr
$lblPreviewTitle.ForeColor = $theme.TextPrimary
$lblPreviewTitle.AutoSize = $true
$lblPreviewTitle.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 4)
$tabReports.Controls.Add($lblPreviewTitle, 0, 3)

$txtReportViewer = New-Object System.Windows.Forms.TextBox
$txtReportViewer.Font = $fonts.Console
$txtReportViewer.Multiline = $true
$txtReportViewer.ReadOnly = $true
$txtReportViewer.ScrollBars = [System.Windows.Forms.ScrollBars]::Both
$txtReportViewer.Dock = 'Fill'
$txtReportViewer.BackColor = $theme.BgSurface
$txtReportViewer.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$txtReportViewer.Margin = New-Object System.Windows.Forms.Padding(0)
$tabReports.Controls.Add($txtReportViewer, 0, 4)

# ---------------------------------------------------------------------------
# Helper: Logging & Diagnostics Output
# ---------------------------------------------------------------------------
function Add-LogLine {
    param([string]$Text)
    if ($txtLog.InvokeRequired) {
        $txtLog.Invoke([Action[string]]{ param($t) Add-LogLine $t }, $Text)
        return
    }
    $txtLog.AppendText($Text + "`r`n")
    $txtLog.SelectionStart = $txtLog.TextLength
    $txtLog.ScrollToCaret()
}

function Get-DriveFreeSpaceGb {
    param([string]$Path)
    try {
        $root = [System.IO.Path]::GetPathRoot([System.IO.Path]::GetFullPath($Path))
        $di = New-Object System.IO.DriveInfo($root)
        return [Math]::Round($di.AvailableFreeSpace / 1GB, 1)
    } catch {
        return $null
    }
}

function Update-FormState {
    # 1. Privileges
    $privStr = if ($isAdmin) { "Administrator" } else { "Standard User" }

    # 2. ISO check
    $isoPath = $txtIso.Text.Trim()
    $isoValid = $false
    $isoStr = "Not selected"
    if ($isoPath) {
        if (Test-Path -LiteralPath $isoPath -PathType Leaf) {
            $isoValid = $true
            try {
                $fLen = [Math]::Round((Get-Item -LiteralPath $isoPath).Length / 1GB, 2)
                $isoBase = [System.IO.Path]::GetFileName($isoPath)
                $isoStr = "$isoBase ($fLen GB)"
            } catch {
                $isoStr = "Selected"
            }
        } else {
            $isoStr = "File not found"
        }
    }

    # 3. Disk Space
    $workPath = $txtWork.Text.Trim()
    $spaceStr = "Unchecked"
    $freeGb = if ($workPath) { Get-DriveFreeSpaceGb -Path $workPath } else { $null }
    if ($null -ne $freeGb) {
        $spaceStr = "${freeGb} GB free"
        if ($freeGb -lt 25) {
            $spaceStr += " (Low disk space)"
        }
    }

    # 4. Profile
    $selProf = [string]$cmbProfile.SelectedItem
    $profStr = if ($selProf) { $selProf } else { "None" }

    # Unified neutral Preflight summary
    $lblPreflightSummary.Text = "Privileges: $privStr    |    Source ISO: $isoStr    |    Workspace: $spaceStr    |    Profile: $profStr"

    # 5. Buttons enablement & Action hierarchy
    $canPlan = $isoValid -or $chkDryRun.Checked
    $btnPlan.Enabled = $canPlan

    if ($isoValid) {
        if ($isAdmin -or $chkDryRun.Checked) {
            $btnBuild.Enabled = $true
            $btnBuild.Text = if ($chkDryRun.Checked) { "Run Dry-Run Build" } else { "Start Build" }
            $btnBuild.BackColor = $theme.AccentBlue
            $btnBuild.ForeColor = [System.Drawing.Color]::White
            # Secondary plan button
            $btnPlan.BackColor = $theme.BtnSecondaryBg
            $btnPlan.ForeColor = $theme.BtnSecondaryFg
        } else {
            $btnBuild.Enabled = $false
            $btnBuild.Text = "Build (Admin Needed)"
            $btnBuild.BackColor = $theme.BtnDisabledBg
            $btnBuild.ForeColor = $theme.BtnDisabledFg
            # Plan remains primary
            $btnPlan.BackColor = $theme.AccentBlue
            $btnPlan.ForeColor = [System.Drawing.Color]::White
        }
    } else {
        $btnBuild.Enabled = $false
        $btnBuild.Text = "Start Build"
        $btnBuild.BackColor = $theme.BtnDisabledBg
        $btnBuild.ForeColor = $theme.BtnDisabledFg
        # Plan primary if DryRun
        if ($chkDryRun.Checked) {
            $btnPlan.BackColor = $theme.AccentBlue
            $btnPlan.ForeColor = [System.Drawing.Color]::White
        } else {
            $btnPlan.BackColor = $theme.BtnDisabledBg
            $btnPlan.ForeColor = $theme.BtnDisabledFg
        }
    }
}

function Populate-ModuleList {
    $listModules.Items.Clear()
    $selProf = [string]$cmbProfile.SelectedItem
    $profObj = $null
    if ($selProf) {
        $pPath = Join-Path (Join-Path $toolRoot 'profiles') "$selProf.json"
        if (Test-Path -LiteralPath $pPath) {
            try { $profObj = Import-WibProfile -Path $pPath } catch {}
        }
    }

    if ($script:WibModules) {
        foreach ($mKey in ($script:WibModules.Keys | Sort-Object)) {
            $m = $script:WibModules[$mKey]
            $isEnabled = $false
            if ($profObj -and $profObj.ContainsKey('modules') -and $profObj['modules'].ContainsKey($mKey)) {
                $isEnabled = Test-WibModuleEnabled $profObj['modules'][$mKey]
            }

            $statusText = if ($isEnabled) { "Active" } else { "Off" }
            $item = New-Object System.Windows.Forms.ListViewItem($statusText)
            $item.UseItemStyleForSubItems = $false
            if ($isEnabled) {
                $item.ForeColor = $theme.TextPrimary
            } else {
                $item.ForeColor = $theme.TextMuted
            }

            $subId = $item.SubItems.Add($mKey)
            $subId.ForeColor = $theme.TextPrimary

            $subRisk = $item.SubItems.Add([string]$m.Risk)
            $subRisk.ForeColor = $theme.TextSecondary

            $subRev = $item.SubItems.Add([string]$m.Reversibility)
            $subRev.ForeColor = $theme.TextSecondary

            $scopeStr = if ($m.Scope) { $m.Scope -join ', ' } else { 'all' }
            $subScope = $item.SubItems.Add($scopeStr)
            $subScope.ForeColor = $theme.TextMuted

            $descStr = if ($m.Description) { $m.Description } else { 'No description provided.' }
            $subDesc = $item.SubItems.Add($descStr)
            $subDesc.ForeColor = $theme.TextSecondary

            $item.Tag = $m
            [void]$listModules.Items.Add($item)
        }
    }
}

function Populate-ReportsList {
    $listReports.Items.Clear()
    $repDir = Join-Path $toolRoot 'reports'
    if (Test-Path -LiteralPath $repDir) {
        Get-ChildItem -LiteralPath $repDir -File | Sort-Object LastWriteTime -Descending | ForEach-Object {
            $item = New-Object System.Windows.Forms.ListViewItem($_.Name)
            $fKb = [Math]::Round($_.Length / 1KB, 1)
            [void]$item.SubItems.Add("${fKb} KB")
            [void]$item.SubItems.Add($_.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss"))
            [void]$item.SubItems.Add($_.Extension.ToUpper())
            $item.Tag = $_.FullName
            [void]$listReports.Items.Add($item)
        }
    }
}

function Update-ProfileInfo {
    $sel = [string]$cmbProfile.SelectedItem
    if (-not $sel) { return }
    $pPath = Join-Path (Join-Path $toolRoot 'profiles') "$sel.json"
    if (Test-Path -LiteralPath $pPath -PathType Leaf) {
        try {
            $prof = Import-WibProfile -Path $pPath
            $mods = if ($prof.ContainsKey('modules') -and $prof['modules']) { $prof['modules'].Count } else { 0 }
            
            $maxRisk = 'low'
            $enabledCount = 0
            if ($prof.ContainsKey('modules')) {
                foreach ($mKey in $prof['modules'].Keys) {
                    $mCfg = $prof['modules'][$mKey]
                    if (Test-WibModuleEnabled $mCfg) {
                        $enabledCount++
                        if ($script:WibModules -and $script:WibModules.Contains($mKey)) {
                            $mRisk = $script:WibModules[$mKey].Risk
                            if ($mRisk -eq 'high') { $maxRisk = 'high' }
                            elseif ($mRisk -eq 'medium' -and $maxRisk -ne 'high') { $maxRisk = 'medium' }
                        }
                    }
                }
            }
            $lblProfileDetails.Text = "Risk: $maxRisk | $enabledCount of $mods active"
            $lblProfileDetails.ForeColor = $theme.TextSecondary
        } catch {
            $lblProfileDetails.Text = "Profile ($sel)"
            $lblProfileDetails.ForeColor = $theme.TextSecondary
        }
    }
    Populate-ModuleList
    Update-FormState
}

# ---------------------------------------------------------------------------
# Background Process Execution & Log Streaming
# ---------------------------------------------------------------------------
$script:Proc = $null
$script:LogFile = $null
$script:LogPos = 0
$script:StartTime = [DateTime]::MinValue

$timerElapsed = New-Object System.Windows.Forms.Timer
$timerElapsed.Interval = 1000
$timerElapsed.Add_Tick({
    if ($script:StartTime -gt [DateTime]::MinValue) {
        $span = [DateTime]::UtcNow - $script:StartTime
        $lblElapsed.Text = ("Elapsed: {0:D2}:{1:D2}" -f [int]$span.TotalMinutes, $span.Seconds)
    }
})

function Start-WibProcess {
    param(
        [string]$ScriptFile,
        [string[]]$Arguments,
        [string]$StatusMessage,
        [scriptblock]$OnComplete
    )

    $lblStatus.Text = "Status: $StatusMessage"
    $lblStatus.ForeColor = $theme.AccentBlue
    $progressBar.Style = 'Marquee'
    $progressBar.MarqueeAnimationSpeed = 30
    $btnBuild.Enabled = $false
    $btnPlan.Enabled = $false
    $btnValidate.Enabled = $false
    $btnCancel.Enabled = $true
    $btnCancel.BackColor = $theme.DangerRed
    $btnCancel.ForeColor = [System.Drawing.Color]::White

    $script:StartTime = [DateTime]::UtcNow
    $timerElapsed.Start()

    Add-LogLine ("=" * 80)
    Add-LogLine ("[WIB STUDIO] Executing: powershell.exe -File `"$ScriptFile`" $($Arguments -join ' ')")
    Add-LogLine ("=" * 80)

    $script:LogFile = Join-Path $env:TEMP ("wib-studio-{0}.log" -f [guid]::NewGuid().ToString('N'))
    $script:LogPos  = 0

    $escapedArgs = @()
    foreach ($arg in $Arguments) {
        if ($arg -match '\s' -and -not ($arg.StartsWith('\"') -or ($arg.StartsWith('"') -and $arg.EndsWith('"')))) {
            $escapedArgs += ('"{0}"' -f ($arg -replace '"', '\"'))
        } else {
            $escapedArgs += $arg
        }
    }
    $argString = $escapedArgs -join ' '

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName   = 'cmd.exe'
    $psi.Arguments  = "/s /c `"powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$ScriptFile`" $argString > `"$script:LogFile`" 2>&1 < nul`""
    $psi.WorkingDirectory = $toolRoot
    $psi.RedirectStandardOutput = $false
    $psi.RedirectStandardError  = $false
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true

    $script:Proc = [System.Diagnostics.Process]::Start($psi)

    $timerStream = New-Object System.Windows.Forms.Timer
    $timerStream.Interval = 400
    $timerStream.Add_Tick({
        param($sender, $e)
        if (Test-Path -LiteralPath $script:LogFile) {
            try {
                $fs = [System.IO.File]::Open($script:LogFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                try {
                    [void]$fs.Seek($script:LogPos, [System.IO.SeekOrigin]::Begin)
                    $sr = New-Object System.IO.StreamReader($fs)
                    $text = $sr.ReadToEnd()
                    $script:LogPos = $fs.Position
                } finally {
                    $fs.Dispose()
                }
                foreach ($line in ($text -split "`r?`n")) {
                    if ($line) { Add-LogLine $line }
                }
            } catch {}
        }
        if ($script:Proc.HasExited) {
            $sender.Stop()
            $sender.Dispose()
            $timerElapsed.Stop()

            # Drain final lines
            if (Test-Path -LiteralPath $script:LogFile) {
                try {
                    $fs = [System.IO.File]::Open($script:LogFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                    try {
                        [void]$fs.Seek($script:LogPos, [System.IO.SeekOrigin]::Begin)
                        $sr = New-Object System.IO.StreamReader($fs)
                        $tail = $sr.ReadToEnd()
                    } finally {
                        $fs.Dispose()
                    }
                    foreach ($line in ($tail -split "`r?`n")) {
                        if ($line) { Add-LogLine $line }
                    }
                } catch {}
                Remove-Item -LiteralPath $script:LogFile -Force -ErrorAction SilentlyContinue
            }

            $progressBar.Style = 'Blocks'
            $progressBar.Value = 100
            $btnCancel.Enabled = $false
            $btnCancel.BackColor = $theme.BtnDisabledBg
            $btnCancel.ForeColor = $theme.BtnDisabledFg
            $code = $script:Proc.ExitCode

            if ($code -eq 0) {
                $lblStatus.Text = "Status: Completed successfully (Exit Code 0)"
                $lblStatus.ForeColor = $theme.SuccessGreen
                Add-LogLine "`r`n[WIB STUDIO] Operation completed successfully (Exit Code 0)."
            } else {
                $lblStatus.Text = "Status: Operation failed (Exit Code $code)"
                $lblStatus.ForeColor = $theme.DangerRed
                Add-LogLine "`r`n[WIB STUDIO] Operation failed with exit code $code. Review diagnostic trace above."
            }

            Update-FormState
            Populate-ReportsList

            if ($OnComplete) {
                & $OnComplete $code
            }
        }
    })
    $timerStream.Start()
}

# ---------------------------------------------------------------------------
# Control Event Bindings
# ---------------------------------------------------------------------------
# ISO Browsing
$btnBrowseIso.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = "Windows Installation Media (*.iso;*.wim)|*.iso;*.wim|ISO Images (*.iso)|*.iso|WIM Files (*.wim)|*.wim|All Files (*.*)|*.*"
    $dlg.Title = "Select Official Windows 11 Installation ISO or WIM"
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtIso.Text = $dlg.FileName
        Update-FormState
    }
})

$txtIso.Add_TextChanged({ Update-FormState })
$txtWork.Add_TextChanged({ Update-FormState })
$chkDryRun.Add_CheckedChanged({ Update-FormState })
$chkAcceptRisk.Add_CheckedChanged({ Update-FormState })
$chkSkipHash.Add_CheckedChanged({ Update-FormState })

# Workspace Browsing
$btnBrowseWork.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = "Select Staging Directory for Offline Image Servicing (~25 GB free recommended)"
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtWork.Text = $dlg.SelectedPath
        Update-FormState
    }
})

# Profile Dropdown population
$profilesDir = Join-Path $toolRoot 'profiles'
if (Test-Path -LiteralPath $profilesDir) {
    Get-ChildItem -LiteralPath $profilesDir -Filter '*.json' | ForEach-Object {
        $pName = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
        [void]$cmbProfile.Items.Add($pName)
    }
    if ($cmbProfile.Items.Contains('balanced')) {
        $cmbProfile.SelectedItem = 'balanced'
    } elseif ($cmbProfile.Items.Count -gt 0) {
        $cmbProfile.SelectedIndex = 0
    }
}
$cmbProfile.Add_SelectedIndexChanged({ Update-ProfileInfo })

# Module List item selection updates detail view
$listModules.Add_SelectedIndexChanged({
    if ($listModules.SelectedItems.Count -gt 0) {
        $selItem = $listModules.SelectedItems[0]
        $mod = $selItem.Tag
        if ($mod) {
            $tradeoffText = if ($mod.Tradeoff) { $mod.Tradeoff } else { "None noted." }
            $verifyText = if ($mod.Verify) { "Automated post-apply verification enabled." } else { "No automated verification hook registered." }
            $txtModDetail.Text = "Module: $($mod.Id)`r`nScope: $(($mod.Scope -join ', '))`r`nRisk Tier: $($mod.Risk) | Reversibility: $($mod.Reversibility)`r`n`r`nDescription:`r`n$($mod.Description)`r`n`r`nTrade-offs & Technical Context:`r`n$tradeoffText`r`n`r`nVerification:`r`n$verifyText"
        }
    }
})

# Report List item selection updates report viewer
$listReports.Add_SelectedIndexChanged({
    if ($listReports.SelectedItems.Count -gt 0) {
        $selItem = $listReports.SelectedItems[0]
        $filePath = $selItem.Tag
        if ($filePath -and (Test-Path -LiteralPath $filePath)) {
            try {
                $txtReportViewer.Text = Get-Content -LiteralPath $filePath -Raw
            } catch {
                $txtReportViewer.Text = "Unable to preview artifact: $($_.Exception.Message)"
            }
        }
    }
})

$btnRefreshReports.Add_Click({ Populate-ReportsList })

$btnOpenReportsDir.Add_Click({
    $repDir = Join-Path $toolRoot 'reports'
    if (-not (Test-Path -LiteralPath $repDir)) { New-Item -ItemType Directory -Force -Path $repDir | Out-Null }
    [System.Diagnostics.Process]::Start('explorer.exe', "`"$repDir`"") | Out-Null
})

$btnOpenReports.Add_Click({
    $repDir = Join-Path $toolRoot 'reports'
    if (-not (Test-Path -LiteralPath $repDir)) { New-Item -ItemType Directory -Force -Path $repDir | Out-Null }
    [System.Diagnostics.Process]::Start('explorer.exe', "`"$repDir`"") | Out-Null
})

$btnClearLog.Add_Click({ $txtLog.Clear() })
$btnCopyLog.Add_Click({
    if ($txtLog.Text) {
        [System.Windows.Forms.Clipboard]::SetText($txtLog.Text)
        [System.Windows.Forms.MessageBox]::Show("Console diagnostic log copied to clipboard.", "WIB Studio", "OK", "Information")
    }
})

# Button Actions
$btnValidate.Add_Click({
    $p = [string]$cmbProfile.SelectedItem
    $cliArgs = @('-Command', 'validate', '-ProfileName', $p)
    if ($chkAcceptRisk.Checked) { $cliArgs += '-AcceptRisk' }
    Start-WibProcess -ScriptFile (Join-Path $toolRoot 'build.ps1') -Arguments $cliArgs -StatusMessage "Validating profile '$p' against schema..."
})

$btnPlan.Add_Click({
    $iso = $txtIso.Text.Trim()
    $p = [string]$cmbProfile.SelectedItem
    $cliArgs = @('-Command', 'plan', '-ProfileName', $p, '-WorkDir', "`"$($txtWork.Text)`"")
    if ($iso) { $cliArgs += @('-IsoPath', "`"$iso`"") }
    if ($cmbEdition.SelectedIndex -gt 0) {
        $cliArgs += @('-Index', [string]$cmbEdition.SelectedIndex)
    }
    if ($cmbHardware.SelectedIndex -gt 0) {
        $selHw = [string]$cmbHardware.SelectedItem
        if ($selHw -match '^Spec:\s+(.+)$') {
            $specPath = Join-Path $toolRoot ("specs\{0}.json" -f $matches[1])
            $cliArgs += @('-HardwareSpec', "`"$specPath`"")
        }
    }
    if ($chkAcceptRisk.Checked) { $cliArgs += '-AcceptRisk' }
    if ($chkSkipHash.Checked) { $cliArgs += '-SkipIsoHash' }
    if ($chkDownloadOscd.Checked) { $cliArgs += '-DownloadOscdimg' }
    Start-WibProcess -ScriptFile (Join-Path $toolRoot 'build.ps1') -Arguments $cliArgs -StatusMessage "Generating declarative plan for profile '$p'..."
})

$btnBuild.Add_Click({
    $iso = $txtIso.Text.Trim()
    if (-not $iso -or -not (Test-Path -LiteralPath $iso)) {
        [System.Windows.Forms.MessageBox]::Show("Please select a valid Windows 11 installation ISO or WIM file to build.", "Source Media Required", "OK", "Warning")
        return
    }
    $p = [string]$cmbProfile.SelectedItem
    $cliArgs = @('-Command', 'build', '-IsoPath', "`"$iso`"", '-ProfileName', $p, '-WorkDir', "`"$($txtWork.Text)`"")
    if ($cmbEdition.SelectedIndex -gt 0) {
        $cliArgs += @('-Index', [string]$cmbEdition.SelectedIndex)
    }
    if ($cmbHardware.SelectedIndex -gt 0) {
        $selHw = [string]$cmbHardware.SelectedItem
        if ($selHw -match '^Spec:\s+(.+)$') {
            $specPath = Join-Path $toolRoot ("specs\{0}.json" -f $matches[1])
            $cliArgs += @('-HardwareSpec', "`"$specPath`"")
        }
    }
    if ($chkDryRun.Checked) { $cliArgs += '-DryRun' }
    if ($chkResume.Checked) { $cliArgs += '-Resume' }
    if ($chkAcceptRisk.Checked) { $cliArgs += '-AcceptRisk' }
    if ($chkSkipHash.Checked) { $cliArgs += '-SkipIsoHash' }
    if ($chkDownloadOscd.Checked) { $cliArgs += '-DownloadOscdimg' }

    $confirmMsg = "Start full offline image build with profile '$p'?"
    if ($chkDryRun.Checked) { $confirmMsg = "Start dry-run build simulation with profile '$p'?" }
    if ([System.Windows.Forms.MessageBox]::Show($confirmMsg, "Confirm Execution", "YesNo", "Question") -ne 'Yes') { return }

    Start-WibProcess -ScriptFile (Join-Path $toolRoot 'build.ps1') -Arguments $cliArgs -StatusMessage "Executing build with profile '$p'..."
})

$btnCancel.Add_Click({
    if ($script:Proc -and -not $script:Proc.HasExited) {
        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "Terminating an active build stops the servicing process tree.`r`n`r`nIf DISM was mounting an image, you may need to run 'dism /Cleanup-Wim' to release driver locks.`r`n`r`nAre you sure you want to cancel?",
            "Confirm Cancellation",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        if ($confirm -eq [System.Windows.Forms.DialogResult]::Yes) {
            try {
                & taskkill.exe /T /F /PID $script:Proc.Id | Out-Null
            } catch {}
            $lblStatus.Text = "Status: Cancellation requested by user."
            $lblStatus.ForeColor = $theme.DangerRed
            Add-LogLine "`r`n[WIB STUDIO] Cancellation requested. Process tree terminated."
            $btnCancel.Enabled = $false
            $btnCancel.BackColor = $theme.BtnDisabledBg
            $btnCancel.ForeColor = $theme.BtnDisabledFg
        }
    }
})

$form.Add_FormClosing({
    param($sender, $e)
    if ($script:Proc -and -not $script:Proc.HasExited) {
        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "A build or validation process is actively running.`r`n`r`nAre you sure you want to exit and terminate?",
            "Process Active",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) {
            $e.Cancel = $true
            return
        }
        try { & taskkill.exe /T /F /PID $script:Proc.Id | Out-Null } catch {}
    }
})

# ---------------------------------------------------------------------------
# Initial Form Startup
# ---------------------------------------------------------------------------
Update-ProfileInfo
Populate-ReportsList
Update-FormState

if ($InitialTab -ge 0 -and $InitialTab -lt $tabPages.Count) {
    Select-Tab $InitialTab
}

# Welcome banner in console
$txtLog.AppendText("WIB Studio ready.`r`n")
$txtLog.AppendText("Select a Windows 11 installation ISO and click 'Preview Plan' to inspect the execution stages.`r`n")

# Screenshot support for automated audit/verification
if ($ScreenshotPath) {
    $shotTimer = New-Object System.Windows.Forms.Timer
    $shotTimer.Interval = 700
    $shotTimer.Add_Tick({
        $shotTimer.Stop()
        $shotTimer.Dispose()
        try {
            $form.Refresh()
            [System.Windows.Forms.Application]::DoEvents()
            
            $bmp = New-Object System.Drawing.Bitmap($form.Width, $form.Height)
            $form.DrawToBitmap($bmp, (New-Object System.Drawing.Rectangle(0, 0, $form.Width, $form.Height)))
            
            $dir = Split-Path -Parent $ScreenshotPath
            if ($dir -and -not (Test-Path -LiteralPath $dir)) {
                New-Item -ItemType Directory -Force -Path $dir | Out-Null
            }
            $bmp.Save($ScreenshotPath, [System.Drawing.Imaging.ImageFormat]::Png)
            $bmp.Dispose()
        } catch {
            Write-Verbose $_.Exception.Message
        }
        if ($CloseAfterScreenshot) {
            $form.Close()
        }
    })
    $form.Add_Shown({ $shotTimer.Start() })
}

[void]$form.ShowDialog()
