# Report writer: manifest.json (machine-readable) + report.html (human-readable).

function ConvertTo-WibHtml { param([string]$Text) [System.Net.WebUtility]::HtmlEncode([string]$Text) }

function Add-WibHtmlTable {
    param($Sb, [string]$Title, [string[]]$Headers, $Rows, [string[]]$Keys, [switch]$Collapsible)
    $rowCount = if ($Rows) { @($Rows).Count } else { 0 }
    if ($Collapsible -and $rowCount -gt 25) {
        [void]$Sb.AppendLine("<details open><summary><h2 style=`"display:inline-block;cursor:pointer;margin:0.5em 0;`>$(ConvertTo-WibHtml $Title) ($rowCount items)</h2></summary>")
    } else {
        [void]$Sb.AppendLine("<h2>$(ConvertTo-WibHtml $Title)</h2>")
    }
    if (-not $Rows -or $rowCount -eq 0) {
        [void]$Sb.AppendLine('<p>None.</p>')
        if ($Collapsible -and $rowCount -gt 25) { [void]$Sb.AppendLine('</details>') }
        return
    }
    [void]$Sb.AppendLine('<table><tr>' + (($Headers | ForEach-Object { "<th>$(ConvertTo-WibHtml $_)</th>" }) -join '') + '</tr>')
    foreach ($r in $Rows) {
        $cells = foreach ($k in $Keys) {
            $v = if ($r -is [System.Collections.IDictionary]) { [string]$r[$k] } elseif ($r.PSObject.Properties[$k]) { [string]$r.PSObject.Properties[$k].Value } else { '' }
            $cls = ''
            if ($k -eq 'Status') { $cls = " class=`"$(ConvertTo-WibHtml $v)`"" }
            "<td$cls>$(ConvertTo-WibHtml $v)</td>"
        }
        [void]$Sb.AppendLine('<tr>' + ($cells -join '') + '</tr>')
    }
    [void]$Sb.AppendLine('</table>')
    if ($Collapsible -and $rowCount -gt 25) {
        [void]$Sb.AppendLine('</details>')
    }
}

function Write-WibReport {
    param([Parameter(Mandatory)]$Manifest, [Parameter(Mandatory)][string]$Dir, [string]$SigningCertThumbprint = '')
    New-Item -ItemType Directory -Force -Path $Dir | Out-Null

    $planList = @($Manifest.plan)
    $journalCount = @($planList | Where-Object { $_.Reversibility -eq 'journal' }).Count
    $reinstallableCount = @($planList | Where-Object { $_.Reversibility -eq 'reinstallable' }).Count
    $permanentCount = @($planList | Where-Object { $_.Reversibility -eq 'permanent' }).Count

    # Calculate estimated disk space savings
    $totalSavingsBytes = 0
    foreach ($item in $planList) {
        if ($item -and $item.ContainsKey('EstimatedBytes') -and $item.EstimatedBytes) {
            $totalSavingsBytes += [long]$item.EstimatedBytes
        }
    }
    $savingsFormatted = Format-WibBytes $totalSavingsBytes
    $Manifest['estimatedSavings'] = [ordered]@{
        bytes     = $totalSavingsBytes
        formatted = "$savingsFormatted (estimated)"
    }

    # Write manifest.json and generate detached checksum (.sha256 = detached checksum)
    $manifestPath = Join-Path $Dir 'manifest.json'
    Set-WibDurableJsonFile -Path $manifestPath -Data $Manifest -Depth 10
    Protect-WibManifest -ManifestPath $manifestPath -Thumbprint $SigningCertThumbprint | Out-Null

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('<!doctype html><meta charset="utf-8"><title>WIB build report</title>')
    [void]$sb.AppendLine('<style>body{font:14px system-ui,sans-serif;max-width:1100px;margin:2em auto;padding:0 1em}table{border-collapse:collapse;width:100%;margin:.5em 0 1.5em;content-visibility:auto;contain-intrinsic-size:500px}td,th{border:1px solid #ccc;padding:4px 8px;text-align:left;vertical-align:top;word-break:break-word}th{background:#f3f3f3}.fail,.failed{color:#b00020;font-weight:600}.warn,.skipped{color:#8a6d00;font-weight:600}.pass,.applied{color:#0a7a2f}details{margin:1em 0}summary{cursor:pointer;user-select:none}</style>')
    [void]$sb.AppendLine("<h1>WIB build report</h1><p>Status: <b>$(ConvertTo-WibHtml $Manifest.status)</b> &middot; tool $(ConvertTo-WibHtml $Manifest.tool.version) &middot; $(ConvertTo-WibHtml $Manifest.createdUtc)</p>")

    $parentChainStr = 'none'
    if ($Manifest.profile.parentChain -and @($Manifest.profile.parentChain).Count -gt 0) {
        $parentChainStr = @($Manifest.profile.parentChain) -join ' -> '
    }

    $summary = @(
        @{ K = 'Overall Status'; V = [string]$Manifest.status },
        @{ K = 'Artifact Status'; V = if ($Manifest.Contains('artifactStatus') -and $Manifest.artifactStatus) { [string]$Manifest.artifactStatus } else { [string]$Manifest.status } },
        @{ K = 'Finalization Status'; V = if ($Manifest.Contains('finalizationStatus') -and $Manifest.finalizationStatus) { [string]$Manifest.finalizationStatus } else { 'n/a' } },
        @{ K = 'Profile'; V = "$($Manifest.profile.name) (canonical sha256 $($Manifest.profile.sha256))" },
        @{ K = 'Parent Chain'; V = $parentChainStr },
        @{ K = 'Reversibility Tiers'; V = "$journalCount journal, $reinstallableCount reinstallable, $permanentCount permanent" },
        @{ K = 'Estimated Disk Savings'; V = "$savingsFormatted (estimated)" },
        @{ K = 'Source ISO sha256'; V = [string]$Manifest.source.isoSha256 },
        @{ K = 'Architecture'; V = [string]$Manifest.source.arch },
        @{ K = 'Edition / index'; V = "$($Manifest.source.edition) / $($Manifest.source.index)" },
        @{ K = 'Output ISO'; V = [string]$Manifest.output.iso },
        @{ K = 'Output sha256'; V = [string]$Manifest.output.sha256 },
        @{ K = 'oscdimg'; V = "$($Manifest.oscdimg.path) (sha256 $($Manifest.oscdimg.sha256))" },
        @{ K = 'Dry run'; V = [string]$Manifest.dryRun }
    )
    if ($Manifest.Contains('hardware') -and $Manifest.hardware) {
        $hw = $Manifest.hardware
        $hwDesc = "$($hw.ramGB) GB RAM, $($hw.storageType), $($hw.cpuCores) CPU cores, $($hw.gpuType) GPU ($($hw.formFactor))"
        $summary += @{ K = 'Target Hardware'; V = $hwDesc }
    }
    Add-WibHtmlTable $sb 'Summary' @('Field', 'Value') $summary @('K', 'V')

    # Workspace Cleanup Results (if present)
    if ($Manifest.Contains('cleanup') -and $Manifest.cleanup -and @($Manifest.cleanup.Keys).Count -gt 0) {
        $cleanupRows = foreach ($k in $Manifest.cleanup.Keys) {
            $cat = if ($k -eq 'recoveryLedger') { 'Critical Ledger' } else { 'Workspace Hygiene' }
            @{ Target = [string]$k; Category = $cat; Status = [string]$Manifest.cleanup[$k] }
        }
        Add-WibHtmlTable $sb 'Workspace Cleanup' @('Target', 'Category', 'Status') $cleanupRows @('Target', 'Category', 'Status')
    }

    # Adaptive Hardware Decisions (if present)
    if ($Manifest.Contains('adaptiveDecisions') -and $Manifest.adaptiveDecisions -and @($Manifest.adaptiveDecisions).Count -gt 0) {
        Add-WibHtmlTable $sb 'Adaptive Hardware Decisions' @('Signal', 'Detected Value', 'Decision', 'Reason') $Manifest.adaptiveDecisions @('Signal', 'Value', 'Decision', 'Reason')
    }

    # Prominent Security Warning Banners
    if ($Manifest.Contains('unattendSecurityNotice') -and $Manifest['unattendSecurityNotice']) {
        [void]$sb.AppendLine("<div style=`"background:#fff3cd;border:1px solid #ffeeba;color:#856404;padding:12px;margin:1em 0;border-radius:4px;font-weight:600;`>SECURITY WARNING: $(ConvertTo-WibHtml $Manifest.unattendSecurityNotice)</div>")
    }
    $highRiskApplied = @($Manifest.results | Where-Object { $_.Module -in @('defender-off', 'mitigations-off', 'uac-off') -and $_.Status -eq 'applied' })
    if ($highRiskApplied.Count -gt 0) {
        $hrMods = ($highRiskApplied | ForEach-Object { $_.Module } | Select-Object -Unique) -join ', '
        [void]$sb.AppendLine("<div style=`"background:#f8d7da;border:1px solid #f5c6cb;color:#721c24;padding:12px;margin:1em 0;border-radius:4px;font-weight:600;`>HIGH-RISK SECURITY WARNING: High-risk security opt-in modules were applied ($hrMods). System defenses have been reduced. Deploy this image ONLY in isolated test environments.</div>")
    }

    # Warnings and failures are displayed FIRST right below Summary
    $buildFailures = @($Manifest.results | Where-Object { $_.Status -eq 'failed' })
    if ($buildFailures.Count -gt 0) {
        Add-WibHtmlTable $sb 'Build Failures (Critical)' @('Module', 'Item', 'Status', 'Detail') $buildFailures @('Module', 'Item', 'Status', 'Detail')
    }
    $verifyWarnings = @($Manifest.verification | Where-Object { $_.Status -eq 'fail' -or $_.Status -eq 'warn' })
    if ($verifyWarnings.Count -gt 0) {
        Add-WibHtmlTable $sb 'Verification Findings (Warnings / Failures)' @('Check', 'Status', 'Detail') $verifyWarnings @('Item', 'Status', 'Detail')
    }

    # Plan vs. Actual Table
    $planVsActual = New-Object System.Collections.ArrayList
    foreach ($pItem in $planList) {
        $targetStr = [string]$pItem.Target
        $resMatch = $Manifest.results | Where-Object {
            if ($_.Module -ne $pItem.Module) { return $false }
            if ($_.Item -eq $targetStr) { return $true }
            if ($targetStr -and $_.Item -and ($_.Item.IndexOf($targetStr, [System.StringComparison]::OrdinalIgnoreCase) -ge 0)) { return $true }
            return $false
        } | Select-Object -First 1

        $actualStatus = if ($resMatch) {
            $resMatch.Status
        } elseif ($Manifest.dryRun) {
            'dry-run (preview)'
        } elseif ($pItem.Action -like 'KEEP*' -or $pItem.Reason -like '*keep*' -or $pItem.Reason -like '*protected*') {
            'kept'
        } elseif ($pItem.Action -eq 'SKIP' -or $pItem.Reason -like '*appliesWhen not met*') {
            'skipped'
        } else {
            'pending'
        }
        $actualDetail = if ($resMatch) { $resMatch.Detail } else { $pItem.Reason }
        $itemSavings = if ($pItem.ContainsKey('EstimatedBytes') -and $pItem.EstimatedBytes) { Format-WibBytes $pItem.EstimatedBytes } else { '-' }

        [void]$planVsActual.Add([ordered]@{
            Module        = $pItem.Module
            Action        = $pItem.Action
            Target        = $pItem.Target
            Tier          = $pItem.Reversibility
            EstimatedSize = $itemSavings
            Status        = $actualStatus
            Detail        = $actualDetail
        })
    }
    Add-WibHtmlTable $sb 'Plan vs. Actual Execution' @('Module', 'Action', 'Target', 'Tier', 'Est. Size', 'Status', 'Detail') $planVsActual @('Module', 'Action', 'Target', 'Tier', 'EstimatedSize', 'Status', 'Detail') -Collapsible
    Add-WibHtmlTable $sb 'Detailed Results' @('Module', 'Item', 'Status', 'Detail') $Manifest.results @('Module', 'Item', 'Status', 'Detail') -Collapsible
    $sb.ToString() | Set-Content -LiteralPath (Join-Path $Dir 'report.html') -Encoding UTF8
}
