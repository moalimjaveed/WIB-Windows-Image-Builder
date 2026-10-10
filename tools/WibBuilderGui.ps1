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

[CmdletBinding()]
param(
    [switch]$NoElevate,
    [string]$ScreenshotPath,
    [switch]$CloseAfterScreenshot,
    [int]$InitialTab = 0
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
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
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

# Typography Hierarchy
$fontFamily = 'Segoe UI'
try {
    $testFont = New-Object System.Drawing.Font('Segoe UI Variable Text', 9)
    $fontFamily = 'Segoe UI Variable Text'
    $testFont.Dispose()
} catch {}

$fonts = @{
    AppTitle    = New-Object System.Drawing.Font($fontFamily, 14, [System.Drawing.FontStyle]::Bold)
    SectionHdr  = New-Object System.Drawing.Font($fontFamily, 10.5, [System.Drawing.FontStyle]::Bold)
    SubHdr      = New-Object System.Drawing.Font($fontFamily, 9, [System.Drawing.FontStyle]::Bold)
    Body        = New-Object System.Drawing.Font($fontFamily, 9, [System.Drawing.FontStyle]::Regular)
    Small       = New-Object System.Drawing.Font($fontFamily, 8.25, [System.Drawing.FontStyle]::Regular)
    SmallBold   = New-Object System.Drawing.Font($fontFamily, 8.25, [System.Drawing.FontStyle]::Bold)
    Console     = New-Object System.Drawing.Font('Consolas', 9, [System.Drawing.FontStyle]::Regular)
}

# ---------------------------------------------------------------------------
# Main Application Form
# ---------------------------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text = "WIB: Windows Image Builder Studio"
$form.Size = New-Object System.Drawing.Size(960, 810)
$form.MinimumSize = New-Object System.Drawing.Size(900, 720)
$form.StartPosition = 'CenterScreen'
$form.Font = $fonts.Body
$form.BackColor = $theme.BgWindow

# ---------------------------------------------------------------------------
# 1. Header Area: Integrated directly on canvas (NO boxed container, NO bottom line)
# ---------------------------------------------------------------------------
$pnlHeader = New-Object System.Windows.Forms.Panel
$pnlHeader.Dock = 'Top'
$pnlHeader.Height = 56
$pnlHeader.BackColor = $theme.BgWindow
$form.Controls.Add($pnlHeader)

$lblAppTitle = New-Object System.Windows.Forms.Label
$lblAppTitle.Text = "Windows Image Builder Studio"
$lblAppTitle.Font = $fonts.AppTitle
$lblAppTitle.ForeColor = $theme.TextPrimary
$lblAppTitle.Location = New-Object System.Drawing.Point(24, 12)
$lblAppTitle.AutoSize = $true
$pnlHeader.Controls.Add($lblAppTitle)

$lblAppSub = New-Object System.Windows.Forms.Label
$lblAppSub.Text = "Hardware-adaptive, verifiable Windows 11 offline servicing engine"
$lblAppSub.Font = $fonts.Small
$lblAppSub.ForeColor = $theme.TextSecondary
$lblAppSub.Location = New-Object System.Drawing.Point(25, 36)
$lblAppSub.AutoSize = $true
$pnlHeader.Controls.Add($lblAppSub)

$lblSessionInfo = New-Object System.Windows.Forms.Label
if ($isAdmin) {
    $lblSessionInfo.Text = "Elevated Session (Administrator Servicing Active)"
} else {
    $lblSessionInfo.Text = "Standard User (Preview Mode - Live builds require elevation)"
}
$lblSessionInfo.Font = $fonts.Small
$lblSessionInfo.ForeColor = $theme.TextSecondary
$lblSessionInfo.Location = New-Object System.Drawing.Point(540, 18)
$lblSessionInfo.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$lblSessionInfo.AutoSize = $true
$pnlHeader.Controls.Add($lblSessionInfo)

# ---------------------------------------------------------------------------
# 2. Modern Navigation Bar (Tabs)
# ---------------------------------------------------------------------------
$pnlNav = New-Object System.Windows.Forms.Panel
$pnlNav.Dock = 'Top'
$pnlNav.Height = 36
$pnlNav.BackColor = $theme.BgWindow
$form.Controls.Add($pnlNav)

$pnlContent = New-Object System.Windows.Forms.Panel
$pnlContent.Dock = 'Fill'
$pnlContent.BackColor = $theme.BgWindow

$tabStudio = New-Object System.Windows.Forms.Panel
$tabStudio.Dock = 'Fill'
$tabStudio.BackColor = $theme.BgWindow
$pnlContent.Controls.Add($tabStudio)

$tabModules = New-Object System.Windows.Forms.Panel
$tabModules.Dock = 'Fill'
$tabModules.BackColor = $theme.BgWindow
$tabModules.Visible = $false
$pnlContent.Controls.Add($tabModules)

$tabReports = New-Object System.Windows.Forms.Panel
$tabReports.Dock = 'Fill'
$tabReports.BackColor = $theme.BgWindow
$tabReports.Visible = $false
$pnlContent.Controls.Add($tabReports)

$tabPages = @($tabStudio, $tabModules, $tabReports)

# Navigation Buttons
$tabNames = @("Studio & Build", "Module & Profile Inspector", "Build Artifacts & Reports")
$navButtons = New-Object System.Collections.ArrayList
$navX = 24

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
    $nBtn.Location = New-Object System.Drawing.Point($navX, 2)
    $nBtn.Size = New-Object System.Drawing.Size(190, 30)
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
    $navX += 196
}

# Add pnlContent to form (Dock order: Fill first, then Top panels)
$form.Controls.Add($pnlContent)
$form.Controls.SetChildIndex($pnlContent, 0)
$form.Controls.SetChildIndex($pnlNav, 1)
$form.Controls.SetChildIndex($pnlHeader, 2)

# ===========================================================================
# TAB 1: STUDIO & BUILD WORKSPACE
# ===========================================================================

# Preflight Summary Bar (Flat, calm neutral)
$pnlPreflight = New-Object System.Windows.Forms.Panel
$pnlPreflight.Location = New-Object System.Drawing.Point(24, 8)
$pnlPreflight.Size = New-Object System.Drawing.Size(896, 32)
$pnlPreflight.BackColor = $theme.BgSurface
$pnlPreflight.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$tabStudio.Controls.Add($pnlPreflight)

$lblPreflightSummary = New-Object System.Windows.Forms.Label
$lblPreflightSummary.Text = "Privileges: Standard User    |    Source ISO: Not selected    |    Workspace: Checking...    |    Profile: balanced"
$lblPreflightSummary.Font = $fonts.Small
$lblPreflightSummary.ForeColor = $theme.TextSecondary
$lblPreflightSummary.Location = New-Object System.Drawing.Point(14, 7)
$lblPreflightSummary.AutoSize = $true
$pnlPreflight.Controls.Add($lblPreflightSummary)

# Configuration Section Header (No box outline)
$lblConfigHdr = New-Object System.Windows.Forms.Label
$lblConfigHdr.Text = "Configuration"
$lblConfigHdr.Font = $fonts.SectionHdr
$lblConfigHdr.ForeColor = $theme.TextPrimary
$lblConfigHdr.Location = New-Object System.Drawing.Point(24, 52)
$lblConfigHdr.AutoSize = $true
$tabStudio.Controls.Add($lblConfigHdr)

$lblConfigDesc = New-Object System.Windows.Forms.Label
$lblConfigDesc.Text = "Specify the source installation image, target hardware, and servicing profile."
$lblConfigDesc.Font = $fonts.Small
$lblConfigDesc.ForeColor = $theme.TextSecondary
$lblConfigDesc.Location = New-Object System.Drawing.Point(25, 73)
$lblConfigDesc.AutoSize = $true
$tabStudio.Controls.Add($lblConfigDesc)

# Fields container (Clean, borderless)
$pnlFields = New-Object System.Windows.Forms.Panel
$pnlFields.Location = New-Object System.Drawing.Point(24, 94)
$pnlFields.Size = New-Object System.Drawing.Size(896, 175)
$pnlFields.BackColor = $theme.BgWindow
$tabStudio.Controls.Add($pnlFields)

# Row 1: Source ISO
$lblIso = New-Object System.Windows.Forms.Label
$lblIso.Text = "Source ISO Image"
$lblIso.Font = $fonts.Small
$lblIso.ForeColor = $theme.TextSecondary
$lblIso.Location = New-Object System.Drawing.Point(0, 0)
$lblIso.AutoSize = $true
$pnlFields.Controls.Add($lblIso)

$txtIso = New-Object System.Windows.Forms.TextBox
$txtIso.Font = $fonts.Body
$txtIso.Location = New-Object System.Drawing.Point(0, 20)
$txtIso.Size = New-Object System.Drawing.Size(785, 24)
$pnlFields.Controls.Add($txtIso)

$btnBrowseIso = New-Object System.Windows.Forms.Button
$btnBrowseIso.Text = "Browse..."
$btnBrowseIso.UseMnemonic = $false
$btnBrowseIso.Font = $fonts.Body
$btnBrowseIso.Location = New-Object System.Drawing.Point(795, 18)
$btnBrowseIso.Size = New-Object System.Drawing.Size(100, 27)
$btnBrowseIso.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnBrowseIso.BackColor = $theme.BtnSecondaryBg
$btnBrowseIso.ForeColor = $theme.BtnSecondaryFg
$pnlFields.Controls.Add($btnBrowseIso)

# Row 2: Profile Selection & Edition
$lblProfile = New-Object System.Windows.Forms.Label
$lblProfile.Text = "Build Profile"
$lblProfile.Font = $fonts.Small
$lblProfile.ForeColor = $theme.TextSecondary
$lblProfile.Location = New-Object System.Drawing.Point(0, 56)
$lblProfile.AutoSize = $true
$pnlFields.Controls.Add($lblProfile)

$cmbProfile = New-Object System.Windows.Forms.ComboBox
$cmbProfile.DropDownStyle = 'DropDownList'
$cmbProfile.Font = $fonts.Body
$cmbProfile.Location = New-Object System.Drawing.Point(0, 76)
$cmbProfile.Size = New-Object System.Drawing.Size(260, 24)
$pnlFields.Controls.Add($cmbProfile)

$lblProfileDetails = New-Object System.Windows.Forms.Label
$lblProfileDetails.Font = $fonts.Small
$lblProfileDetails.ForeColor = $theme.TextSecondary
$lblProfileDetails.Location = New-Object System.Drawing.Point(268, 79)
$lblProfileDetails.AutoSize = $true
$pnlFields.Controls.Add($lblProfileDetails)

$lblEdition = New-Object System.Windows.Forms.Label
$lblEdition.Text = "Target Edition"
$lblEdition.Font = $fonts.Small
$lblEdition.ForeColor = $theme.TextSecondary
$lblEdition.Location = New-Object System.Drawing.Point(440, 56)
$lblEdition.AutoSize = $true
$pnlFields.Controls.Add($lblEdition)

$cmbEdition = New-Object System.Windows.Forms.ComboBox
$cmbEdition.DropDownStyle = 'DropDownList'
$cmbEdition.Font = $fonts.Body
$cmbEdition.Location = New-Object System.Drawing.Point(440, 76)
$cmbEdition.Size = New-Object System.Drawing.Size(260, 24)
[void]$cmbEdition.Items.Add("Auto-detect (Single Edition)")
for ($idx = 1; $idx -le 11; $idx++) {
    [void]$cmbEdition.Items.Add("Image Index $idx")
}
$cmbEdition.SelectedIndex = 0
$pnlFields.Controls.Add($cmbEdition)

# Row 3: Target Hardware & Staging Workspace
$lblHardware = New-Object System.Windows.Forms.Label
$lblHardware.Text = "Hardware Profile"
$lblHardware.Font = $fonts.Small
$lblHardware.ForeColor = $theme.TextSecondary
$lblHardware.Location = New-Object System.Drawing.Point(0, 112)
$lblHardware.AutoSize = $true
$pnlFields.Controls.Add($lblHardware)

$cmbHardware = New-Object System.Windows.Forms.ComboBox
$cmbHardware.DropDownStyle = 'DropDownList'
$cmbHardware.Font = $fonts.Body
$cmbHardware.Location = New-Object System.Drawing.Point(0, 132)
$cmbHardware.Size = New-Object System.Drawing.Size(260, 24)
[void]$cmbHardware.Items.Add("Live Host (CIM Auto-Detect)")
$specsDir = Join-Path $toolRoot 'specs'
if (Test-Path -LiteralPath $specsDir) {
    Get-ChildItem -LiteralPath $specsDir -Filter '*.json' | ForEach-Object {
        $specBase = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
        [void]$cmbHardware.Items.Add("Spec: $specBase")
    }
}
$cmbHardware.SelectedIndex = 0
$pnlFields.Controls.Add($cmbHardware)

$lblWork = New-Object System.Windows.Forms.Label
$lblWork.Text = "Staging Workspace"
$lblWork.Font = $fonts.Small
$lblWork.ForeColor = $theme.TextSecondary
$lblWork.Location = New-Object System.Drawing.Point(290, 112)
$lblWork.AutoSize = $true
$pnlFields.Controls.Add($lblWork)

$txtWork = New-Object System.Windows.Forms.TextBox
$txtWork.Font = $fonts.Body
$txtWork.Text = Join-Path $toolRoot 'work'
$txtWork.Location = New-Object System.Drawing.Point(290, 132)
$txtWork.Size = New-Object System.Drawing.Size(495, 24)
$pnlFields.Controls.Add($txtWork)

$btnBrowseWork = New-Object System.Windows.Forms.Button
$btnBrowseWork.Text = "Browse..."
$btnBrowseWork.UseMnemonic = $false
$btnBrowseWork.Font = $fonts.Body
$btnBrowseWork.Location = New-Object System.Drawing.Point(795, 130)
$btnBrowseWork.Size = New-Object System.Drawing.Size(100, 27)
$btnBrowseWork.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnBrowseWork.BackColor = $theme.BtnSecondaryBg
$btnBrowseWork.ForeColor = $theme.BtnSecondaryFg
$pnlFields.Controls.Add($btnBrowseWork)

# Options & Safety Controls (Clean, inline, no enclosing box)
$pnlOptions = New-Object System.Windows.Forms.Panel
$pnlOptions.Location = New-Object System.Drawing.Point(24, 274)
$pnlOptions.Size = New-Object System.Drawing.Size(896, 52)
$pnlOptions.BackColor = $theme.BgWindow
$tabStudio.Controls.Add($pnlOptions)

$chkDryRun = New-Object System.Windows.Forms.CheckBox
$chkDryRun.Text = "Dry-run simulation only"
$chkDryRun.Font = $fonts.Body
$chkDryRun.ForeColor = $theme.TextPrimary
$chkDryRun.Location = New-Object System.Drawing.Point(0, 4)
$chkDryRun.AutoSize = $true
$pnlOptions.Controls.Add($chkDryRun)

$chkResume = New-Object System.Windows.Forms.CheckBox
$chkResume.Text = "Resume from checkpoint"
$chkResume.Font = $fonts.Body
$chkResume.ForeColor = $theme.TextPrimary
$chkResume.Location = New-Object System.Drawing.Point(220, 4)
$chkResume.AutoSize = $true
$pnlOptions.Controls.Add($chkResume)

$chkDownloadOscd = New-Object System.Windows.Forms.CheckBox
$chkDownloadOscd.Text = "Download signed oscdimg"
$chkDownloadOscd.Font = $fonts.Body
$chkDownloadOscd.ForeColor = $theme.TextPrimary
$chkDownloadOscd.Location = New-Object System.Drawing.Point(440, 4)
$chkDownloadOscd.AutoSize = $true
$pnlOptions.Controls.Add($chkDownloadOscd)

$chkAcceptRisk = New-Object System.Windows.Forms.CheckBox
$chkAcceptRisk.Text = "Accept high-risk modules"
$chkAcceptRisk.Font = $fonts.Body
$chkAcceptRisk.ForeColor = $theme.TextSecondary
$chkAcceptRisk.Location = New-Object System.Drawing.Point(0, 28)
$chkAcceptRisk.AutoSize = $true
$pnlOptions.Controls.Add($chkAcceptRisk)

$chkSkipHash = New-Object System.Windows.Forms.CheckBox
$chkSkipHash.Text = "Skip ISO hash verification"
$chkSkipHash.Font = $fonts.Body
$chkSkipHash.ForeColor = $theme.TextSecondary
$chkSkipHash.Location = New-Object System.Drawing.Point(220, 28)
$chkSkipHash.AutoSize = $true
$pnlOptions.Controls.Add($chkSkipHash)

# Action Buttons Bar (Clean, integrated, NO box border)
$pnlActions = New-Object System.Windows.Forms.Panel
$pnlActions.Location = New-Object System.Drawing.Point(24, 332)
$pnlActions.Size = New-Object System.Drawing.Size(896, 36)
$pnlActions.BackColor = $theme.BgWindow
$tabStudio.Controls.Add($pnlActions)

$btnPlan = New-Object System.Windows.Forms.Button
$btnPlan.Text = "Preview Plan"
$btnPlan.Font = $fonts.Body
$btnPlan.Location = New-Object System.Drawing.Point(0, 2)
$btnPlan.Size = New-Object System.Drawing.Size(125, 32)
$btnPlan.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnPlan.BackColor = $theme.AccentBlue
$btnPlan.ForeColor = [System.Drawing.Color]::White
$pnlActions.Controls.Add($btnPlan)

$btnBuild = New-Object System.Windows.Forms.Button
$btnBuild.Text = "Start Build"
$btnBuild.Font = $fonts.Body
$btnBuild.Location = New-Object System.Drawing.Point(135, 2)
$btnBuild.Size = New-Object System.Drawing.Size(125, 32)
$btnBuild.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnBuild.BackColor = $theme.BtnDisabledBg
$btnBuild.ForeColor = $theme.BtnDisabledFg
$btnBuild.Enabled = $false
$pnlActions.Controls.Add($btnBuild)

$btnValidate = New-Object System.Windows.Forms.Button
$btnValidate.Text = "Validate Profile"
$btnValidate.Font = $fonts.Body
$btnValidate.Location = New-Object System.Drawing.Point(270, 2)
$btnValidate.Size = New-Object System.Drawing.Size(125, 32)
$btnValidate.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnValidate.BackColor = $theme.BtnSecondaryBg
$btnValidate.ForeColor = $theme.BtnSecondaryFg
$pnlActions.Controls.Add($btnValidate)

$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Text = "Cancel"
$btnCancel.Font = $fonts.Body
$btnCancel.Location = New-Object System.Drawing.Point(405, 2)
$btnCancel.Size = New-Object System.Drawing.Size(95, 32)
$btnCancel.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnCancel.BackColor = $theme.BtnDisabledBg
$btnCancel.ForeColor = $theme.BtnDisabledFg
$btnCancel.Enabled = $false
$pnlActions.Controls.Add($btnCancel)

$btnOpenReports = New-Object System.Windows.Forms.Button
$btnOpenReports.Text = "Open Reports"
$btnOpenReports.Font = $fonts.Body
$btnOpenReports.Location = New-Object System.Drawing.Point(510, 2)
$btnOpenReports.Size = New-Object System.Drawing.Size(115, 32)
$btnOpenReports.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnOpenReports.BackColor = $theme.BtnSecondaryBg
$btnOpenReports.ForeColor = $theme.BtnSecondaryFg
$pnlActions.Controls.Add($btnOpenReports)

$btnClearLog = New-Object System.Windows.Forms.Button
$btnClearLog.Text = "Clear"
$btnClearLog.Font = $fonts.Small
$btnClearLog.Location = New-Object System.Drawing.Point(740, 2)
$btnClearLog.Size = New-Object System.Drawing.Size(70, 32)
$btnClearLog.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnClearLog.BackColor = $theme.BtnSecondaryBg
$btnClearLog.ForeColor = $theme.BtnSecondaryFg
$pnlActions.Controls.Add($btnClearLog)

$btnCopyLog = New-Object System.Windows.Forms.Button
$btnCopyLog.Text = "Copy"
$btnCopyLog.Font = $fonts.Small
$btnCopyLog.Location = New-Object System.Drawing.Point(820, 2)
$btnCopyLog.Size = New-Object System.Drawing.Size(75, 32)
$btnCopyLog.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnCopyLog.BackColor = $theme.BtnSecondaryBg
$btnCopyLog.ForeColor = $theme.BtnSecondaryFg
$pnlActions.Controls.Add($btnCopyLog)

# Activity & Diagnostics Header
$lblActHdr = New-Object System.Windows.Forms.Label
$lblActHdr.Text = "Activity & Diagnostics"
$lblActHdr.UseMnemonic = $false
$lblActHdr.Font = $fonts.SectionHdr
$lblActHdr.ForeColor = $theme.TextPrimary
$lblActHdr.Location = New-Object System.Drawing.Point(24, 378)
$lblActHdr.AutoSize = $true
$tabStudio.Controls.Add($lblActHdr)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = "Status: Idle - configure inputs and choose Preview Plan or Start Build"
$lblStatus.Font = $fonts.Small
$lblStatus.ForeColor = $theme.TextSecondary
$lblStatus.Location = New-Object System.Drawing.Point(200, 381)
$lblStatus.AutoSize = $true
$tabStudio.Controls.Add($lblStatus)

$lblElapsed = New-Object System.Windows.Forms.Label
$lblElapsed.Text = "Elapsed: 00:00"
$lblElapsed.Font = $fonts.Small
$lblElapsed.ForeColor = $theme.TextSecondary
$lblElapsed.Location = New-Object System.Drawing.Point(820, 381)
$lblElapsed.AutoSize = $true
$tabStudio.Controls.Add($lblElapsed)

# Progress Bar (Slim, 4px)
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(24, 404)
$progressBar.Size = New-Object System.Drawing.Size(896, 4)
$tabStudio.Controls.Add($progressBar)

# Console TextBox (Clean, quiet dark terminal with subtle 1px border)
$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Multiline = $true
$txtLog.ReadOnly = $true
$txtLog.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$txtLog.Font = $fonts.Console
$txtLog.BackColor = $theme.TerminalBg
$txtLog.ForeColor = $theme.TerminalFg
$txtLog.Location = New-Object System.Drawing.Point(24, 414)
$txtLog.Size = New-Object System.Drawing.Size(896, 280)
$txtLog.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$tabStudio.Controls.Add($txtLog)

# ===========================================================================
# TAB 2: MODULE & PROFILE INSPECTOR
# ===========================================================================
$lblModTitle = New-Object System.Windows.Forms.Label
$lblModTitle.Text = "Module Catalog & Architecture"
$lblModTitle.UseMnemonic = $false
$lblModTitle.Font = $fonts.SectionHdr
$lblModTitle.ForeColor = $theme.TextPrimary
$lblModTitle.Location = New-Object System.Drawing.Point(24, 16)
$lblModTitle.AutoSize = $true
$tabModules.Controls.Add($lblModTitle)

$lblModHelp = New-Object System.Windows.Forms.Label
$lblModHelp.Text = "Inspect all 19 offline servicing modules, risk levels, reversibility tiers, and execution tradeoffs."
$lblModHelp.Font = $fonts.Small
$lblModHelp.ForeColor = $theme.TextSecondary
$lblModHelp.Location = New-Object System.Drawing.Point(25, 40)
$lblModHelp.AutoSize = $true
$tabModules.Controls.Add($lblModHelp)

$listModules = New-Object System.Windows.Forms.ListView
$listModules.Location = New-Object System.Drawing.Point(24, 66)
$listModules.Size = New-Object System.Drawing.Size(896, 440)
$listModules.View = [System.Windows.Forms.View]::Details
$listModules.FullRowSelect = $true
$listModules.GridLines = $true
$listModules.Font = $fonts.Body
[void]$listModules.Columns.Add("Status", 75)
[void]$listModules.Columns.Add("Module ID", 190)
[void]$listModules.Columns.Add("Risk", 80)
[void]$listModules.Columns.Add("Reversibility", 110)
[void]$listModules.Columns.Add("Scope", 85)
[void]$listModules.Columns.Add("Description & Trade-offs", 340)
$tabModules.Controls.Add($listModules)

$lblModDetailTitle = New-Object System.Windows.Forms.Label
$lblModDetailTitle.Text = "Selected Module Details & Trade-offs:"
$lblModDetailTitle.UseMnemonic = $false
$lblModDetailTitle.Font = $fonts.SubHdr
$lblModDetailTitle.ForeColor = $theme.TextPrimary
$lblModDetailTitle.Location = New-Object System.Drawing.Point(24, 516)
$lblModDetailTitle.AutoSize = $true
$tabModules.Controls.Add($lblModDetailTitle)

$txtModDetail = New-Object System.Windows.Forms.TextBox
$txtModDetail.Font = $fonts.Body
$txtModDetail.Multiline = $true
$txtModDetail.ReadOnly = $true
$txtModDetail.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$txtModDetail.Location = New-Object System.Drawing.Point(24, 540)
$txtModDetail.Size = New-Object System.Drawing.Size(896, 150)
$txtModDetail.BackColor = $theme.BgSurface
$txtModDetail.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$tabModules.Controls.Add($txtModDetail)

# ===========================================================================
# TAB 3: BUILD ARTIFACTS & REPORTS
# ===========================================================================
$lblRepTitle = New-Object System.Windows.Forms.Label
$lblRepTitle.Text = "Build Artifacts & Generated Reports"
$lblRepTitle.UseMnemonic = $false
$lblRepTitle.Font = $fonts.SectionHdr
$lblRepTitle.ForeColor = $theme.TextPrimary
$lblRepTitle.Location = New-Object System.Drawing.Point(24, 16)
$lblRepTitle.AutoSize = $true
$tabReports.Controls.Add($lblRepTitle)

$lblRepHelp = New-Object System.Windows.Forms.Label
$lblRepHelp.Text = "Review manifests, verification reports, and logs generated in the staging directory."
$lblRepHelp.Font = $fonts.Small
$lblRepHelp.ForeColor = $theme.TextSecondary
$lblRepHelp.Location = New-Object System.Drawing.Point(25, 40)
$lblRepHelp.AutoSize = $true
$tabReports.Controls.Add($lblRepHelp)

$btnRefreshReports = New-Object System.Windows.Forms.Button
$btnRefreshReports.Text = "Refresh Artifacts"
$btnRefreshReports.Font = $fonts.Body
$btnRefreshReports.Location = New-Object System.Drawing.Point(24, 66)
$btnRefreshReports.Size = New-Object System.Drawing.Size(130, 30)
$btnRefreshReports.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnRefreshReports.BackColor = $theme.BtnSecondaryBg
$btnRefreshReports.ForeColor = $theme.BtnSecondaryFg
$tabReports.Controls.Add($btnRefreshReports)

$btnOpenReportsDir = New-Object System.Windows.Forms.Button
$btnOpenReportsDir.Text = "Open in Explorer"
$btnOpenReportsDir.Font = $fonts.Body
$btnOpenReportsDir.Location = New-Object System.Drawing.Point(162, 66)
$btnOpenReportsDir.Size = New-Object System.Drawing.Size(130, 30)
$btnOpenReportsDir.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnOpenReportsDir.BackColor = $theme.BtnSecondaryBg
$btnOpenReportsDir.ForeColor = $theme.BtnSecondaryFg
$tabReports.Controls.Add($btnOpenReportsDir)

$listReports = New-Object System.Windows.Forms.ListView
$listReports.Location = New-Object System.Drawing.Point(24, 106)
$listReports.Size = New-Object System.Drawing.Size(896, 230)
$listReports.View = [System.Windows.Forms.View]::Details
$listReports.FullRowSelect = $true
$listReports.GridLines = $true
$listReports.Font = $fonts.Body
[void]$listReports.Columns.Add("Artifact Name", 280)
[void]$listReports.Columns.Add("Size", 100)
[void]$listReports.Columns.Add("Last Modified", 180)
[void]$listReports.Columns.Add("Type", 120)
$tabReports.Controls.Add($listReports)

$lblPreviewTitle = New-Object System.Windows.Forms.Label
$lblPreviewTitle.Text = "Artifact Content Preview:"
$lblPreviewTitle.Font = $fonts.SubHdr
$lblPreviewTitle.ForeColor = $theme.TextPrimary
$lblPreviewTitle.Location = New-Object System.Drawing.Point(24, 348)
$lblPreviewTitle.AutoSize = $true
$tabReports.Controls.Add($lblPreviewTitle)

$txtReportViewer = New-Object System.Windows.Forms.TextBox
$txtReportViewer.Font = $fonts.Console
$txtReportViewer.Multiline = $true
$txtReportViewer.ReadOnly = $true
$txtReportViewer.ScrollBars = [System.Windows.Forms.ScrollBars]::Both
$txtReportViewer.Location = New-Object System.Drawing.Point(24, 372)
$txtReportViewer.Size = New-Object System.Drawing.Size(896, 318)
$txtReportViewer.BackColor = $theme.BgSurface
$txtReportViewer.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$tabReports.Controls.Add($txtReportViewer)

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
