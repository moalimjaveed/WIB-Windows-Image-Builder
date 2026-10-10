#Requires -Version 5.1
<#
.SYNOPSIS
    WIB Compact - Standalone NTFS/WOF Compression Engine & CompactGUI-style Tool.
    Wraps Windows compact.exe for first-party-only, safe filesystem and OS compression.
    PowerShell 5.1+ compatible (CLI & WinForms GUI, zero external dependencies).

.DESCRIPTION
    Provides automated folder analysis, hardware-aware algorithm selection (XPRESS4K,
    XPRESS8K, XPRESS16K, LZX), skip list filtering for incompressible formats, DirectStorage
    safety heuristics, recompression support, whole OS (CompactOS) management, and
    scheduled folder watcher management.

.PARAMETER Command
    The action to execute: 'analyze', 'compress', 'decompress', 'query', 'compactos', 'watcher', or 'gui'.
.PARAMETER Path
    Target directory path for analysis, compression, decompression, or query.
.PARAMETER Algorithm
    Compression algorithm: 'auto' (hardware-adaptive), 'XPRESS4K', 'XPRESS8K', 'XPRESS16K', or 'LZX'.
.PARAMETER HardwareSpec
    Optional path to a hardware specification JSON file for hardware-aware recommendations.
.PARAMETER Force
    Passes /F to compact.exe to force recompression of already compressed files.
.PARAMETER Recompress
    Forces recompression of already compressed files with the selected algorithm.
.PARAMETER OverrideSafetyChecks
    Explicitly overrides DirectStorage and system directory safety exclusions (drive roots and reparse points remain non-overridable).
.PARAMETER ContinueOnNativeError
    Allows non-zero compact.exe exit codes to return a structured failure result instead of terminating.
.PARAMETER CompactOsAction
    CompactOS action: 'query', 'always', or 'never'.
.PARAMETER OfflineWinDir
    Offline Windows directory path for CompactOS operations.
.PARAMETER WatcherAction
    Watcher action: 'list', 'add', 'remove', 'run', 'enable', or 'disable'.
.PARAMETER Gui
    Forces launching the interactive WinForms graphical user interface.
#>

[CmdletBinding()]
param(
    [ValidateSet('analyze', 'compress', 'decompress', 'query', 'compactos', 'watcher', 'gui')]
    [string]$Command = '',

    [string]$Path = '',

    [ValidateSet('auto', 'XPRESS4K', 'XPRESS8K', 'XPRESS16K', 'LZX')]
    [string]$Algorithm = 'auto',

    [string]$HardwareSpec = '',

    [switch]$Force,

    [switch]$Recompress,

    [switch]$OverrideSafetyChecks,

    [switch]$ContinueOnNativeError,

    [ValidateSet('query', 'always', 'never')]
    [string]$CompactOsAction = 'query',

    [string]$OfflineWinDir = '',

    [ValidateSet('list', 'add', 'remove', 'run', 'enable', 'disable')]
    [string]$WatcherAction = 'list',

    [string]$ConfigDir = '',

    [switch]$Gui
)

$ErrorActionPreference = 'Stop'

# Locate and import libraries
$root = Split-Path -Parent $PSScriptRoot
$libDir = Join-Path $root 'lib'
if (-not (Test-Path -LiteralPath $libDir)) {
    $libDir = Join-Path $PSScriptRoot 'lib'
}

$coreLib = Join-Path $libDir 'Core.ps1'
if (Test-Path -LiteralPath $coreLib) {
    . $coreLib
} else {
    throw "Required library not found: $coreLib"
}

$hardwareLib = Join-Path $libDir 'Hardware.ps1'
if (Test-Path -LiteralPath $hardwareLib) {
    . $hardwareLib
}

$compactLib = Join-Path $libDir 'Compact.ps1'
if (Test-Path -LiteralPath $compactLib) {
    . $compactLib
} else {
    throw "Required library not found: $compactLib"
}

# Resolve hardware profile if provided or available
$hwProfile = $null
if ($HardwareSpec) {
    $hwProfile = Get-WibHardwareProfile -SpecPath $HardwareSpec
} elseif (Get-Command Get-WibHardwareProfile -ErrorAction SilentlyContinue) {
    try {
        $hwProfile = Get-WibHardwareProfile
    } catch {
        Write-Verbose $_.Exception.Message
    }
}

# Determine if GUI should be launched
$shouldLaunchGui = $Gui.IsPresent -or ($Command -eq 'gui')
if (-not $shouldLaunchGui -and -not $Command -and -not $Path) {
    if ([Environment]::UserInteractive) {
        $shouldLaunchGui = $true
    } else {
        $Command = 'analyze'
    }
}

# ==============================================================================
# CLI EXECUTION PATHS
# ==============================================================================

if (-not $shouldLaunchGui) {
    switch ($Command) {
        'analyze' {
            if (-not $Path) { throw "Parameter -Path is required for 'analyze' command." }
            Write-Host "Analyzing folder: $Path" -ForegroundColor Cyan
            $analysis = Measure-WibFolderSavings -Path $Path -Algorithm $Algorithm -HardwareProfile $hwProfile

            Write-Host ("`n=== WIB Compact Analysis: {0} ===" -f $analysis.Path) -ForegroundColor Green
            Write-Host ("Algorithm Choice   : {0}" -f $analysis.Algorithm)
            if ($analysis.AlgorithmReason) {
                Write-Host ("Algorithm Reason   : {0}" -f $analysis.AlgorithmReason) -ForegroundColor Gray
            }
            Write-Host ("Total Files        : {0:N0}" -f $analysis.TotalFiles)
            Write-Host ("Compressible Files : {0:N0}" -f $analysis.CompressibleFiles)
            Write-Host ("Skipped Files      : {0:N0} (incompressible extensions/archives)" -f $analysis.SkippedFiles)
            Write-Host ("Total Size         : {0}" -f (Format-WibBytes $analysis.TotalBytes))
            Write-Host ("Estimated Savings  : ~{0} (Ratio: ~{1}:1)" -f (Format-WibBytes $analysis.EstimatedSavingsBytes), $analysis.EstimatedRatio) -ForegroundColor Green
            Write-Host ("Estimated Size     : ~{0}" -f (Format-WibBytes $analysis.EstimatedFinalBytes))

            if ($analysis.IsDirectStorage) {
                Write-Host "`nWARNING: DirectStorage runtime files detected!" -ForegroundColor Yellow
                Write-Host $analysis.DirectStorageWarning -ForegroundColor Yellow
            }
            if ($analysis.IsSystemExcluded) {
                Write-Host ("`nSAFETY EXCLUSION: {0}" -f $analysis.SystemExclusionReason) -ForegroundColor Red
            }

            return $analysis
        }

        'compress' {
            if (-not $Path) { throw "Parameter -Path is required for 'compress' command." }
            $res = Invoke-WibFolderCompression -Path $Path -Algorithm $Algorithm -Force:$Force -Recompress:$Recompress -OverrideSafetyChecks:$OverrideSafetyChecks -ContinueOnNativeError:$ContinueOnNativeError -HardwareProfile $hwProfile
            if ((-not $res.Success) -and (-not $ContinueOnNativeError)) {
                $code = if ($res.ExitCode -ne 0) { $res.ExitCode } else { 1 }
                exit $code
            }
            return $res
        }

        'decompress' {
            if (-not $Path) { throw "Parameter -Path is required for 'decompress' command." }
            $res = Invoke-WibFolderDecompression -Path $Path -Force:$Force -ContinueOnNativeError:$ContinueOnNativeError
            if ((-not $res.Success) -and (-not $ContinueOnNativeError)) {
                $code = if ($res.ExitCode -ne 0) { $res.ExitCode } else { 1 }
                exit $code
            }
            return $res
        }

        'query' {
            if (-not $Path) { throw "Parameter -Path is required for 'query' command." }
            $status = Get-WibCompactStatus -Path $Path
            if (-not $status.Success) {
                Write-Warning "compact.exe query failed with exit code $($status.ExitCode): $($status.Error)"
            }
            Write-Host ("`n=== WIB Compact Status: {0} ===" -f $status.Path) -ForegroundColor $(if ($status.Success) { 'Green' } else { 'Yellow' })
            Write-Host ("Status State       : {0} (Success: {1}, ExitCode: {2})" -f $status.State, $status.Success, $status.ExitCode)
            Write-Host ("Total Files        : {0}" -f $status.TotalFiles)
            Write-Host ("Compressed Files   : {0}" -f $status.CompressedFiles)
            Write-Host ("Uncompressed Files : {0}" -f $status.UncompressedFiles)
            Write-Host ("Original Bytes     : {0}" -f (Format-WibBytes $status.OriginalBytes))
            Write-Host ("Compressed Bytes   : {0}" -f (Format-WibBytes $status.CompressedBytes))
            Write-Host ("Saved Bytes        : {0}" -f (Format-WibBytes $status.SavedBytes)) -ForegroundColor Green
            Write-Host ("Compression Ratio  : {0}:1" -f $status.Ratio)
            return $status
        }

        'compactos' {
            $osRes = Invoke-WibCompactOS -Action $CompactOsAction -OfflineWinDir $OfflineWinDir -Force:$Force -ContinueOnNativeError:$ContinueOnNativeError
            if (-not $osRes.Success) {
                Write-Host ("CompactOS failed with exit code {0} (State: {1})" -f $osRes.ExitCode, $osRes.State) -ForegroundColor Red
                if (-not $ContinueOnNativeError) { exit 1 }
            }
            Write-Host ("CompactOS Action: {0} -> State: {1}" -f $osRes.Action, $osRes.State) -ForegroundColor Green
            return $osRes
        }

        'watcher' {
            $watchAlgo = 'XPRESS8K'
            if ($Algorithm -ne 'auto') {
                $watchAlgo = $Algorithm
            }
            $wRes = Set-WibCompactWatcher -Action $WatcherAction -Path $Path -Algorithm $watchAlgo -ConfigDir $ConfigDir
            return $wRes
        }
    }
    return
}

# ==============================================================================
# WINFORMS GRAPHICAL USER INTERFACE (CompactGUI-Style)
# ==============================================================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$form = New-Object System.Windows.Forms.Form
$form.Text = "WIB Compact - NTFS / WOF Compression Engine"
$form.Size = New-Object System.Drawing.Size(860, 680)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
$form.MaximizeBox = $false

# Top Header
$headerPanel = New-Object System.Windows.Forms.Panel
$headerPanel.Dock = 'Top'
$headerPanel.Height = 75
$headerPanel.BackColor = [System.Drawing.Color]::FromArgb(24, 32, 44)
$form.Controls.Add($headerPanel)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = "WIB Compact Engine"
$lblTitle.Font = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
$lblTitle.ForeColor = [System.Drawing.Color]::White
$lblTitle.AutoSize = $true
$lblTitle.Location = New-Object System.Drawing.Point(16, 12)
$headerPanel.Controls.Add($lblTitle)

$lblSub = New-Object System.Windows.Forms.Label
$lblSub.Text = "First-party Windows compact.exe GUI - Transparent file & game compression"
$lblSub.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$lblSub.ForeColor = [System.Drawing.Color]::LightGray
$lblSub.AutoSize = $true
$lblSub.Location = New-Object System.Drawing.Point(18, 42)
$headerPanel.Controls.Add($lblSub)

# Main Container
$mainPanel = New-Object System.Windows.Forms.Panel
$mainPanel.Dock = 'Fill'
$mainPanel.Padding = New-Object System.Windows.Forms.Padding(16)
$form.Controls.Add($mainPanel)

# Folder Selection Group
$grpFolder = New-Object System.Windows.Forms.GroupBox
$grpFolder.Text = " Target Directory "
$grpFolder.Location = New-Object System.Drawing.Point(16, 85)
$grpFolder.Size = New-Object System.Drawing.Size(812, 70)
$mainPanel.Controls.Add($grpFolder)

$txtPath = New-Object System.Windows.Forms.TextBox
$txtPath.Location = New-Object System.Drawing.Point(16, 26)
$txtPath.Size = New-Object System.Drawing.Size(680, 25)
if ($Path) { $txtPath.Text = $Path }
$grpFolder.Controls.Add($txtPath)

$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text = "Browse..."
$btnBrowse.Location = New-Object System.Drawing.Point(704, 25)
$btnBrowse.Size = New-Object System.Drawing.Size(95, 27)
$btnBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = "Select a folder to analyze or compress"
    if ($txtPath.Text -and (Test-Path -LiteralPath $txtPath.Text)) {
        $dlg.SelectedPath = $txtPath.Text
    }
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtPath.Text = $dlg.SelectedPath
    }
})
$grpFolder.Controls.Add($btnBrowse)

# Options & Algorithm Group
$grpOptions = New-Object System.Windows.Forms.GroupBox
$grpOptions.Text = " Compression Settings & Hardware Recommendation "
$grpOptions.Location = New-Object System.Drawing.Point(16, 165)
$grpOptions.Size = New-Object System.Drawing.Size(812, 100)
$mainPanel.Controls.Add($grpOptions)

$lblAlgo = New-Object System.Windows.Forms.Label
$lblAlgo.Text = "Algorithm:"
$lblAlgo.Location = New-Object System.Drawing.Point(16, 26)
$lblAlgo.AutoSize = $true
$grpOptions.Controls.Add($lblAlgo)

$cmbAlgo = New-Object System.Windows.Forms.ComboBox
$cmbAlgo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$cmbAlgo.Location = New-Object System.Drawing.Point(85, 23)
$cmbAlgo.Size = New-Object System.Drawing.Size(300, 25)
[void]$cmbAlgo.Items.Add('auto (Hardware Adaptive Recommendation)')
[void]$cmbAlgo.Items.Add('XPRESS4K (Fastest / Low CPU / HDD)')
[void]$cmbAlgo.Items.Add('XPRESS8K (Balanced / Standard SSD)')
[void]$cmbAlgo.Items.Add('XPRESS16K (Higher Compression / Multi-core)')
[void]$cmbAlgo.Items.Add('LZX (Maximum Compression / High CPU)')
$cmbAlgo.SelectedIndex = 0
$grpOptions.Controls.Add($cmbAlgo)

$lblHwInfo = New-Object System.Windows.Forms.Label
$rec = Get-WibCompactAlgorithmRecommendation -HardwareProfile $hwProfile
$lblHwInfo.Text = "Auto recommendation: $($rec.Algorithm) - $($rec.Reason)"
$lblHwInfo.ForeColor = [System.Drawing.Color]::Navy
$lblHwInfo.Location = New-Object System.Drawing.Point(16, 62)
$lblHwInfo.Size = New-Object System.Drawing.Size(780, 25)
$grpOptions.Controls.Add($lblHwInfo)

$chkForce = New-Object System.Windows.Forms.CheckBox
$chkForce.Text = "Force / Recompress (/F)"
$chkForce.Location = New-Object System.Drawing.Point(410, 24)
$chkForce.AutoSize = $true
$grpOptions.Controls.Add($chkForce)

$chkIgnoreDs = New-Object System.Windows.Forms.CheckBox
$chkIgnoreDs.Text = "Override DirectStorage Check"
$chkIgnoreDs.Location = New-Object System.Drawing.Point(590, 24)
$chkIgnoreDs.AutoSize = $true
$grpOptions.Controls.Add($chkIgnoreDs)

# Analysis Display Group
$grpAnalysis = New-Object System.Windows.Forms.GroupBox
$grpAnalysis.Text = " Analysis & Metrics "
$grpAnalysis.Location = New-Object System.Drawing.Point(16, 275)
$grpAnalysis.Size = New-Object System.Drawing.Size(812, 140)
$mainPanel.Controls.Add($grpAnalysis)

$lblMetricsLeft = New-Object System.Windows.Forms.Label
$lblMetricsLeft.Text = "Files: 0 total (0 compressible, 0 skipped)`nOriginal Size: 0 MB`nEstimated Size: 0 MB"
$lblMetricsLeft.Location = New-Object System.Drawing.Point(16, 26)
$lblMetricsLeft.Size = New-Object System.Drawing.Size(380, 65)
$grpAnalysis.Controls.Add($lblMetricsLeft)

$lblMetricsRight = New-Object System.Windows.Forms.Label
$lblMetricsRight.Text = "Estimated Savings: 0 MB`nCompression Ratio: ~1.0:1`nCurrent Status: Not analyzed"
$lblMetricsRight.Location = New-Object System.Drawing.Point(410, 26)
$lblMetricsRight.Size = New-Object System.Drawing.Size(380, 65)
$lblMetricsRight.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$grpAnalysis.Controls.Add($lblMetricsRight)

$lblWarning = New-Object System.Windows.Forms.Label
$lblWarning.Text = ""
$lblWarning.ForeColor = [System.Drawing.Color]::Firebrick
$lblWarning.Location = New-Object System.Drawing.Point(16, 100)
$lblWarning.Size = New-Object System.Drawing.Size(780, 28)
$grpAnalysis.Controls.Add($lblWarning)

# Action Buttons Panel
$pnlActions = New-Object System.Windows.Forms.Panel
$pnlActions.Location = New-Object System.Drawing.Point(16, 425)
$pnlActions.Size = New-Object System.Drawing.Size(812, 45)
$mainPanel.Controls.Add($pnlActions)

$btnAnalyze = New-Object System.Windows.Forms.Button
$btnAnalyze.Text = "Analyze Folder"
$btnAnalyze.Location = New-Object System.Drawing.Point(0, 5)
$btnAnalyze.Size = New-Object System.Drawing.Size(130, 34)
$pnlActions.Controls.Add($btnAnalyze)

$btnCompress = New-Object System.Windows.Forms.Button
$btnCompress.Text = "Compress Folder"
$btnCompress.Location = New-Object System.Drawing.Point(140, 5)
$btnCompress.Size = New-Object System.Drawing.Size(140, 34)
$btnCompress.BackColor = [System.Drawing.Color]::FromArgb(40, 167, 69)
$btnCompress.ForeColor = [System.Drawing.Color]::White
$btnCompress.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$pnlActions.Controls.Add($btnCompress)

$btnDecompress = New-Object System.Windows.Forms.Button
$btnDecompress.Text = "Decompress"
$btnDecompress.Location = New-Object System.Drawing.Point(290, 5)
$btnDecompress.Size = New-Object System.Drawing.Size(120, 34)
$pnlActions.Controls.Add($btnDecompress)

$btnCompactOS = New-Object System.Windows.Forms.Button
$btnCompactOS.Text = "CompactOS Status"
$btnCompactOS.Location = New-Object System.Drawing.Point(420, 5)
$btnCompactOS.Size = New-Object System.Drawing.Size(140, 34)
$pnlActions.Controls.Add($btnCompactOS)

$btnWatch = New-Object System.Windows.Forms.Button
$btnWatch.Text = "Add to Watcher"
$btnWatch.Location = New-Object System.Drawing.Point(570, 5)
$btnWatch.Size = New-Object System.Drawing.Size(130, 34)
$pnlActions.Controls.Add($btnWatch)

# Output Log Box
$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Multiline = $true
$txtLog.ScrollBars = 'Vertical'
$txtLog.ReadOnly = $true
$txtLog.Location = New-Object System.Drawing.Point(16, 480)
$txtLog.Size = New-Object System.Drawing.Size(812, 140)
$txtLog.BackColor = [System.Drawing.Color]::FromArgb(245, 247, 250)
$mainPanel.Controls.Add($txtLog)

function Add-CompactLog {
    param([string]$Message)
    $ts = (Get-Date).ToString('HH:mm:ss')
    $txtLog.AppendText("[$ts] $Message`r`n")
}

# Helper to get selected algorithm string
function Get-SelectedAlgorithm {
    switch ($cmbAlgo.SelectedIndex) {
        1 { return 'XPRESS4K' }
        2 { return 'XPRESS8K' }
        3 { return 'XPRESS16K' }
        4 { return 'LZX' }
        default { return 'auto' }
    }
}

# Event Handlers
$btnAnalyze.Add_Click({
    $target = $txtPath.Text.Trim()
    if (-not $target -or -not (Test-Path -LiteralPath $target)) {
        [System.Windows.Forms.MessageBox]::Show("Please select a valid existing directory.", "Invalid Path", 'OK', 'Warning') | Out-Null
        return
    }

    Add-CompactLog "Analyzing directory: $target..."
    [System.Windows.Forms.Cursor]::Current = [System.Windows.Forms.Cursors]::WaitCursor

    try {
        $algoChoice = Get-SelectedAlgorithm
        $res = Measure-WibFolderSavings -Path $target -Algorithm $algoChoice -HardwareProfile $hwProfile

        $lblMetricsLeft.Text = ("Files: {0:N0} total ({1:N0} compressible, {2:N0} skipped)`nOriginal Size: {3}`nEstimated Size: {4}" -f `
            $res.TotalFiles, $res.CompressibleFiles, $res.SkippedFiles, (Format-WibBytes $res.TotalBytes), (Format-WibBytes $res.EstimatedFinalBytes))

        $lblMetricsRight.Text = ("Estimated Savings: {0}`nCompression Ratio: ~{1}:1`nCurrent Status: {2} compressed / {3} uncompressed" -f `
            (Format-WibBytes $res.EstimatedSavingsBytes), $res.EstimatedRatio, $res.CurrentStatus.CompressedFiles, $res.CurrentStatus.UncompressedFiles)

        if ($res.IsDirectStorage) {
            $lblWarning.Text = "WARNING: DirectStorage files detected! Filesystem compression may impact game streaming performance."
        } elseif ($res.IsSystemExcluded) {
            $lblWarning.Text = "EXCLUSION: System path detected. Use CompactOS for Windows operating system binaries."
        } else {
            $lblWarning.Text = "Folder analyzed successfully. Ready for compression."
            $lblWarning.ForeColor = [System.Drawing.Color]::Green
        }

        Add-CompactLog ("Analysis done. Total: {0}, Estimated Savings: {1} (~{2}:1 ratio)" -f (Format-WibBytes $res.TotalBytes), (Format-WibBytes $res.EstimatedSavingsBytes), $res.EstimatedRatio)
    } catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Analysis Error", 'OK', 'Error') | Out-Null
        Add-CompactLog "Error: $_"
    } finally {
        [System.Windows.Forms.Cursor]::Current = [System.Windows.Forms.Cursors]::Default
    }
})

$btnCompress.Add_Click({
    $target = $txtPath.Text.Trim()
    if (-not $target -or -not (Test-Path -LiteralPath $target)) {
        [System.Windows.Forms.MessageBox]::Show("Please select a valid directory to compress.", "Invalid Path", 'OK', 'Warning') | Out-Null
        return
    }

    $algoChoice = Get-SelectedAlgorithm
    $forceFlag = $chkForce.Checked
    $recompFlag = $chkForce.Checked
    $overrideSafetyFlag = $chkIgnoreDs.Checked

    $confirm = [System.Windows.Forms.MessageBox]::Show("Compress folder '$target' using $algoChoice?", "Confirm Compression", 'YesNo', 'Question')
    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    Add-CompactLog "Starting compression on $target ($algoChoice)..."
    [System.Windows.Forms.Cursor]::Current = [System.Windows.Forms.Cursors]::WaitCursor

    try {
        $res = Invoke-WibFolderCompression -Path $target -Algorithm $algoChoice -Force:$forceFlag -Recompress:$recompFlag -OverrideSafetyChecks:$overrideSafetyFlag -HardwareProfile $hwProfile
        Add-CompactLog ("Compression completed! ExitCode: {0}, Ratio: {1}:1, Saved: {2}" -f $res.ExitCode, $res.Status.Ratio, (Format-WibBytes $res.Status.SavedBytes))
        [System.Windows.Forms.MessageBox]::Show("Compression complete!`nRatio: $($res.Status.Ratio):1`nSaved: $(Format-WibBytes $res.Status.SavedBytes)", "Success", 'OK', 'Information') | Out-Null
    } catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Compression Error", 'OK', 'Error') | Out-Null
        Add-CompactLog "Compression failed: $_"
    } finally {
        [System.Windows.Forms.Cursor]::Current = [System.Windows.Forms.Cursors]::Default
    }
})

$btnDecompress.Add_Click({
    $target = $txtPath.Text.Trim()
    if (-not $target -or -not (Test-Path -LiteralPath $target)) {
        [System.Windows.Forms.MessageBox]::Show("Please select a valid directory to decompress.", "Invalid Path", 'OK', 'Warning') | Out-Null
        return
    }

    $confirm = [System.Windows.Forms.MessageBox]::Show("Decompress folder '$target' back to standard uncompressed files?", "Confirm Decompression", 'YesNo', 'Question')
    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    Add-CompactLog "Decompressing folder $target..."
    [System.Windows.Forms.Cursor]::Current = [System.Windows.Forms.Cursors]::WaitCursor

    try {
        $res = Invoke-WibFolderDecompression -Path $target
        Add-CompactLog "Decompression completed successfully."
        [System.Windows.Forms.MessageBox]::Show("Decompression complete.", "Success", 'OK', 'Information') | Out-Null
    } catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Decompression Error", 'OK', 'Error') | Out-Null
        Add-CompactLog "Decompression failed: $_"
    } finally {
        [System.Windows.Forms.Cursor]::Current = [System.Windows.Forms.Cursors]::Default
    }
})

$btnCompactOS.Add_Click({
    Add-CompactLog "Querying CompactOS state..."
    try {
        $os = Invoke-WibCompactOS -Action query
        Add-CompactLog "CompactOS Query State: $($os.State)"
        $msg = "CompactOS State: $($os.State)`n`nOutput:`n$($os.Output)"
        [System.Windows.Forms.MessageBox]::Show($msg, "CompactOS Query", 'OK', 'Information') | Out-Null
    } catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "CompactOS Error", 'OK', 'Error') | Out-Null
    }
})

$btnWatch.Add_Click({
    $target = $txtPath.Text.Trim()
    if (-not $target -or -not (Test-Path -LiteralPath $target)) {
        [System.Windows.Forms.MessageBox]::Show("Please select a valid directory to add to watched folders.", "Invalid Path", 'OK', 'Warning') | Out-Null
        return
    }
    $algo = Get-SelectedAlgorithm
    if ($algo -eq 'auto') { $algo = 'XPRESS8K' }
    try {
        Set-WibCompactWatcher -Action add -Path $target -Algorithm $algo | Out-Null
        Add-CompactLog "Added '$target' to watched folders list ($algo)."
        [System.Windows.Forms.MessageBox]::Show("Added '$target' to watched folders list ($algo).", "Watcher", 'OK', 'Information') | Out-Null
    } catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Watcher Error", 'OK', 'Error') | Out-Null
    }
})

# Display GUI
[void]$form.ShowDialog()
