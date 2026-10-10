# Scanner + planner. Requires Core.ps1.

function Get-WibScan {
    # Enumerate what is actually in the mounted image (no hardcoded name list).
    param([Parameter(Mandatory)][string]$MountDir)
    $errors = @()
    $appx = @()
    if (Get-Command Get-AppxProvisionedPackage -ErrorAction SilentlyContinue) {
        try {
            foreach ($p in @(Get-AppxProvisionedPackage -Path $MountDir -ErrorAction Stop)) {
                $appx += , @{ DisplayName = $p.DisplayName; PackageName = $p.PackageName }
            }
        } catch {
            $errors += "appx: Appx scan failed: $($_.Exception.Message)"
        }
    }

    $optFeatures = @()
    if (Get-Command Get-WindowsOptionalFeature -ErrorAction SilentlyContinue) {
        try {
            foreach ($f in @(Get-WindowsOptionalFeature -Path $MountDir -ErrorAction Stop)) {
                $optFeatures += , @{ FeatureName = $f.FeatureName; State = [string]$f.State }
            }
        } catch {
            $errors += "features: OptionalFeatures scan failed: $($_.Exception.Message)"
        }
    }

    $capabilities = @()
    if (Get-Command Get-WindowsCapability -ErrorAction SilentlyContinue) {
        try {
            foreach ($c in @(Get-WindowsCapability -Path $MountDir -ErrorAction Stop)) {
                $capabilities += , @{ Name = $c.Name; State = [string]$c.State }
            }
        } catch {
            $errors += "caps: Capabilities scan failed: $($_.Exception.Message)"
        }
    }

    @{
        Appx             = $appx
        OptionalFeatures = $optFeatures
        Capabilities     = $capabilities
        Errors           = $errors
    }
}

function Get-WibAppxMatches {
    # Match scanned packages against profile 'remove'/'addRemove' prefixes, minus 'keep' prefixes.
    param($Scan, [hashtable]$Settings)
    $remove = @(); $keep = @()
    if ($Settings.ContainsKey('remove'))    { $remove += $Settings['remove'] }
    if ($Settings.ContainsKey('addRemove')) { $remove += $Settings['addRemove'] }
    if ($Settings.ContainsKey('keep'))      { $keep   += $Settings['keep'] }

    $neverRemoveAppx = @(
        'Microsoft.WindowsStore', 'Microsoft.StorePurchaseApp', 'Microsoft.DesktopAppInstaller',
        'Microsoft.Windows.ShellExperienceHost', 'Microsoft.UI.Xaml', 'Microsoft.VCLibs'
    )

    $result = @{ Remove = @(); Kept = @() }
    if ($Scan -and $Scan.ContainsKey('Appx') -and $Scan.Appx) {
        foreach ($pkg in $Scan.Appx) {
            $critHit = $neverRemoveAppx | Where-Object { $pkg.DisplayName -like "$_*" -or $pkg.PackageName -like "$_*" } | Select-Object -First 1
            if ($critHit) {
                $result.Kept += , @{ DisplayName = $pkg.DisplayName; Reason = "critical system component protected by never-remove rule '$critHit'" }
                continue
            }
            $hit = $remove | Where-Object { $pkg.DisplayName -like "$_*" } | Select-Object -First 1
            if (-not $hit) { continue }
            $keepHit = $keep | Where-Object { $pkg.DisplayName -like "$_*" } | Select-Object -First 1
            if ($keepHit) {
                $result.Kept += , @{ DisplayName = $pkg.DisplayName; Reason = "protected by keep rule '$keepHit'" }
            } else {
                $result.Remove += , @{ DisplayName = $pkg.DisplayName; PackageName = $pkg.PackageName; Pattern = $hit }
            }
        }
    }
    $result
}

function Get-WibFeatureMatches {
    # Match scanned optional features and capabilities against profile prefixes, protecting critical servicing items.
    param($Scan, [hashtable]$Settings)
    $remFeatures = @(); $keepFeatures = @()
    if ($Settings.ContainsKey('removeFeatures'))    { $remFeatures += $Settings['removeFeatures'] }
    if ($Settings.ContainsKey('addRemoveFeatures')) { $remFeatures += $Settings['addRemoveFeatures'] }
    if ($Settings.ContainsKey('keepFeatures'))      { $keepFeatures += $Settings['keepFeatures'] }

    $remCaps = @(); $keepCaps = @()
    if ($Settings.ContainsKey('removeCapabilities'))    { $remCaps += $Settings['removeCapabilities'] }
    if ($Settings.ContainsKey('addRemoveCapabilities')) { $remCaps += $Settings['addRemoveCapabilities'] }
    if ($Settings.ContainsKey('keepCapabilities'))      { $keepCaps += $Settings['keepCapabilities'] }

    # Critical servicing protection list (never touch these items)
    $criticalPrefixes = @('NetFx4', 'NetFx3', 'Foundation', 'ServicingStack', 'Windows-Defender', 'DirectX', 'OpenSSH')

    $featureResult = @{ Remove = @(); Kept = @() }
    if ($Scan -and $Scan.ContainsKey('OptionalFeatures') -and $Scan.OptionalFeatures) {
        foreach ($feat in $Scan.OptionalFeatures) {
            if ($feat.State -ne 'Enabled' -and $feat.State -ne 'Disabled') { continue }
            $fName = $feat.FeatureName
            $critHit = $criticalPrefixes | Where-Object { $fName -like "$_*" } | Select-Object -First 1
            if ($critHit) { continue }
            $hit = $remFeatures | Where-Object { $fName -like "$_*" } | Select-Object -First 1
            if (-not $hit) { continue }
            $keepHit = $keepFeatures | Where-Object { $fName -like "$_*" } | Select-Object -First 1
            if ($keepHit) {
                $featureResult.Kept += , @{ Name = $fName; Type = 'Feature'; Reason = "protected by keep rule '$keepHit'" }
            } else {
                $featureResult.Remove += , @{ Name = $fName; Type = 'Feature'; Pattern = $hit; State = $feat.State }
            }
        }
    }

    $capResult = @{ Remove = @(); Kept = @() }
    if ($Scan -and $Scan.ContainsKey('Capabilities') -and $Scan.Capabilities) {
        foreach ($cap in $Scan.Capabilities) {
            if ($cap.State -ne 'Installed') { continue }
            $cName = $cap.Name
            $critHit = $criticalPrefixes | Where-Object { $cName -like "$_*" } | Select-Object -First 1
            if ($critHit) { continue }
            $hit = $remCaps | Where-Object { $cName -like "$_*" } | Select-Object -First 1
            if (-not $hit) { continue }
            $keepHit = $keepCaps | Where-Object { $cName -like "$_*" } | Select-Object -First 1
            if ($keepHit) {
                $capResult.Kept += , @{ Name = $cName; Type = 'Capability'; Reason = "protected by keep rule '$keepHit'" }
            } else {
                $capResult.Remove += , @{ Name = $cName; Type = 'Capability'; Pattern = $hit; State = $cap.State }
            }
        }
    }

    @{
        Features     = $featureResult
        Capabilities = $capResult
    }
}

function Test-WibModuleApplies {
    param($Module, $Context)
    if (-not $Module.AppliesWhen -or $Module.AppliesWhen.Count -eq 0) {
        return @{ Applies = $true; Reason = '' }
    }
    $aw = $Module.AppliesWhen

    # 1. Architecture check
    if ($aw.ContainsKey('Arch') -and $Context -and $Context.ContainsKey('Arch') -and $Context.Arch) {
        $allowedArchs = @($aw['Arch'])
        if ($allowedArchs -notcontains $Context.Arch) {
            return @{ Applies = $false; Reason = "Arch '$($Context.Arch)' not in ($($allowedArchs -join ', '))" }
        }
    }

    # 2. Build number check (e.g. '>=22621', '<26000')
    if ($aw.ContainsKey('Builds') -and $Context -and $Context.ContainsKey('Build') -and $Context.Build) {
        $rule = [string]$aw['Builds']
        $actualBuildStr = [string]$Context.Build
        $actualBuildNum = 0
        if ($actualBuildStr -match '(\d{5,})') {
            $actualBuildNum = [int]$matches[1]
        } elseif ([int]::TryParse($actualBuildStr, [ref]$actualBuildNum)) {
            # parsed directly
        }
        if ($actualBuildNum -gt 0) {
            if ($rule -match '^([><=]+)\s*(\d+)') {
                $op = $matches[1]
                $targetBuild = [int]$matches[2]
                $pass = $false
                switch ($op) {
                    '>=' { $pass = ($actualBuildNum -ge $targetBuild) }
                    '<=' { $pass = ($actualBuildNum -le $targetBuild) }
                    '>'  { $pass = ($actualBuildNum -gt $targetBuild) }
                    '<'  { $pass = ($actualBuildNum -lt $targetBuild) }
                    '='  { $pass = ($actualBuildNum -eq $targetBuild) }
                    '==' { $pass = ($actualBuildNum -eq $targetBuild) }
                }
                if (-not $pass) {
                    return @{ Applies = $false; Reason = "Build $actualBuildNum does not satisfy '$rule'" }
                }
            }
        }
    }

    # 3. Edition check (e.g. @('Pro', 'Enterprise'))
    if ($aw.ContainsKey('Editions') -and $Context -and $Context.ContainsKey('Edition') -and $Context.Edition) {
        $allowedEditions = @($aw['Editions'])
        $actualEdition = [string]$Context.Edition
        $matched = $false
        foreach ($ed in $allowedEditions) {
            if ($actualEdition -like "*$ed*") { $matched = $true; break }
        }
        if (-not $matched) {
            return @{ Applies = $false; Reason = "Edition '$actualEdition' not in ($($allowedEditions -join ', '))" }
        }
    }

    return @{ Applies = $true; Reason = '' }
}

function New-WibPlan {
    param([Parameter(Mandatory)][hashtable]$BuildProfile, [Parameter(Mandatory)]$Ctx)
    $items = New-Object System.Collections.ArrayList
    foreach ($id in @(Get-WibEnabledModuleIds $BuildProfile $Ctx.Image)) {
        $mod = $script:WibModules[$id]
        $s = Get-WibModuleSettings $BuildProfile $id

        # Evaluate AppliesWhen
        $appliesRes = Test-WibModuleApplies -Module $mod -Context $Ctx
        if (-not $appliesRes.Applies) {
            [void]$items.Add((New-WibPlanItem $id 'Skip module' $id "Condition not met: $($appliesRes.Reason)" -Reversibility 'journal'))
            continue
        }

        if ($mod.Plan -and $Ctx.Image -eq 'install') {
            foreach ($i in @(& $mod.Plan $Ctx $s)) { if ($i) { [void]$items.Add($i) } }
        }
        foreach ($t in @(Get-WibModuleTweaks $mod $s)) {
            if ($t.Action -eq 'DeleteKey') {
                [void]$items.Add((New-WibPlanItem $id 'Delete registry key' (Get-WibTweakLabel $t) '' -Reversibility 'journal' -NewKind 'DeleteKey'))
            } else {
                $valStr = [string]$t.Value
                $kindStr = [string]$t.Type
                [void]$items.Add((New-WibPlanItem $id 'Set registry value' (Get-WibTweakLabel $t) "= $($t.Value)" -Reversibility 'journal' -NewValue $valStr -NewKind $kindStr))
            }
        }
        if ($mod.Post -and $Ctx.Image -eq 'install') {
            [void]$items.Add((New-WibPlanItem $id 'Post-step' $mod.Description '' -Reversibility $mod.Reversibility))
        }
    }

    # Adaptive hardware tweaks
    if ($Ctx -and $Ctx.ContainsKey('AdaptiveDecisions') -and $Ctx.AdaptiveDecisions -and $Ctx.Image -eq 'install') {
        foreach ($ad in $Ctx.AdaptiveDecisions) {
            if ($ad.Contains('Settings') -and $ad.Settings) { continue }   # module already applies and plans these
            if ($ad.Contains('Tweaks') -and $ad.Tweaks) {
                foreach ($t in $ad.Tweaks) {
                    $reason = if ($ad.Reason) { "Adaptive: $($ad.Reason)" } else { 'Hardware-adaptive optimization' }
                    $valStr = [string]$t.Value
                    $kindStr = [string]$t.Type
                    [void]$items.Add((New-WibPlanItem 'adaptive-hardware' 'Set adaptive tweak' (Get-WibTweakLabel $t) "= $($t.Value) ($reason)" -Reversibility 'journal' -NewValue $valStr -NewKind $kindStr))
                }
            }
        }
    }

    $items.ToArray()   # emitted unrolled; callers wrap with @()
}

function Show-WibPlan {
    param($Plan, $AdaptiveDecisions = @())

    if ($AdaptiveDecisions -and @($AdaptiveDecisions).Count -gt 0) {
        Write-Host ''
        Write-Host '================ ADAPTIVE HARDWARE DECISIONS ================' -ForegroundColor Cyan
        foreach ($ad in $AdaptiveDecisions) {
            Write-Host ("[{0}] {1} -> {2}" -f $ad.Signal, $ad.Value, $ad.Decision) -ForegroundColor Yellow
            Write-Host ("      Reason: {0}" -f $ad.Reason) -ForegroundColor Gray
        }
    }

    Write-Host ''
    Write-Host '================ BUILD PLAN ================' -ForegroundColor Cyan
    $groups = $Plan | Group-Object { $_.Module }
    foreach ($g in $groups) {
        $mod = $script:WibModules[$g.Name]
        $tierCounts = @{ journal = 0; reinstallable = 0; permanent = 0 }
        foreach ($item in $g.Group) {
            $tier = $item.Reversibility
            if (-not $tier) {
                if ($item.Reversible) { $tier = 'journal' } else { $tier = 'permanent' }
            }
            if ($tierCounts.ContainsKey($tier)) { $tierCounts[$tier]++ }
        }
        $tierDesc = @()
        if ($tierCounts.permanent -gt 0) { $tierDesc += "$($tierCounts.permanent) permanent" }
        if ($tierCounts.reinstallable -gt 0) { $tierDesc += "$($tierCounts.reinstallable) reinstallable" }
        if ($tierCounts.journal -gt 0) { $tierDesc += "$($tierCounts.journal) journal" }
        $tierStr = if ($tierDesc.Count -gt 0) { ", " + ($tierDesc -join ', ') } else { '' }

        $riskStr = 'low'
        if ($mod -and $mod.ContainsKey('Risk')) { $riskStr = $mod.Risk }

        Write-Host ("{0}  [{1} change(s), risk: {2}{3}]" -f $g.Name, $g.Count, $riskStr, $tierStr) -ForegroundColor White
        foreach ($i in ($g.Group | Select-Object -First 6)) {
            Write-Host ("    - {0}: {1} {2} [{3}]" -f $i.Action, $i.Target, $i.Reason, $i.Reversibility)
        }
        if ($g.Count -gt 6) { Write-Host ("    ... and {0} more (see report)" -f ($g.Count - 6)) -ForegroundColor DarkGray }
    }
    $total = @($Plan).Count
    $journalCount = @($Plan | Where-Object { $_.Reversibility -eq 'journal' }).Count
    $reinstallableCount = @($Plan | Where-Object { $_.Reversibility -eq 'reinstallable' }).Count
    $permanentCount = @($Plan | Where-Object { $_.Reversibility -eq 'permanent' }).Count
    $totalSavings = 0
    foreach ($item in $Plan) {
        if ($item.PSObject.Properties['EstimatedBytes'] -and $item.EstimatedBytes) {
            $totalSavings += [long]$item.EstimatedBytes
        }
    }

    Write-Host ''
    Write-Host ("Total: {0} change(s); {1} journal, {2} reinstallable, {3} permanent." -f $total, $journalCount, $reinstallableCount, $permanentCount) -ForegroundColor Cyan
    if ($totalSavings -gt 0) {
        Write-Host ("Estimated disk savings: ~{0} (estimate based on scanned packages & files)" -f (Format-WibBytes $totalSavings)) -ForegroundColor Green
    }

    $newDeltaCount = @($Plan | Where-Object { $_.PSObject.Properties['DeltaStatus'] -and $_.DeltaStatus -ne 'Unchanged' }).Count
    $unchangedDeltaCount = @($Plan | Where-Object { $_.PSObject.Properties['DeltaStatus'] -and $_.DeltaStatus -eq 'Unchanged' }).Count
    if ($newDeltaCount -gt 0 -or $unchangedDeltaCount -gt 0) {
        Write-Host ("Delta Rebuild Status: {0} new/modified item(s), {1} unchanged item(s)." -f $newDeltaCount, $unchangedDeltaCount) -ForegroundColor Yellow
    }

    Write-Host '============================================' -ForegroundColor Cyan
}

function Get-WibPropertyValue {
    param($Obj, [string]$PropName)
    if ($null -eq $Obj) { return @{ Present = $false; Value = $null } }
    if ($Obj -is [System.Collections.IDictionary]) {
        if ($Obj.Contains($PropName)) {
            return @{ Present = $true; Value = $Obj[$PropName] }
        }
        return @{ Present = $false; Value = $null }
    }
    if ($null -ne $Obj.PSObject.Properties[$PropName]) {
        return @{ Present = $true; Value = $Obj.PSObject.Properties[$PropName].Value }
    }
    return @{ Present = $false; Value = $null }
}

function Test-WibSemanticPropertyMatch {
    param($ItemA, $ItemB, [string]$PropName)
    $pA = Get-WibPropertyValue -Obj $ItemA -PropName $PropName
    $pB = Get-WibPropertyValue -Obj $ItemB -PropName $PropName

    # 1. Both absent -> match
    if (-not $pA.Present -and -not $pB.Present) { return $true }
    # 2. One absent, one present -> do not match (no wildcard)
    if ($pA.Present -ne $pB.Present) { return $false }

    $vA = $pA.Value
    $vB = $pB.Value

    # 3. Null handling: null matches only null
    if ($null -eq $vA -and $null -eq $vB) { return $true }
    if ($null -eq $vA -or $null -eq $vB) { return $false }

    # 4. Strictly distinguish boolean from non-boolean
    if (($vA -is [bool]) -ne ($vB -is [bool])) { return $false }
    if ($vA -is [bool] -and $vB -is [bool]) { return ($vA -eq $vB) }

    # 5. Empty string: empty string matches ONLY empty string (not 0, not null, not false)
    $isStrA = ($vA -is [string])
    $isStrB = ($vB -is [string])
    if ($isStrA -and $vA.Length -eq 0 -and $isStrB -and $vB.Length -eq 0) { return $true }
    if ($isStrA -and $vA.Length -eq 0) { return $false }
    if ($isStrB -and $vB.Length -eq 0) { return $false }

    # 6. Integer/number comparison (including numeric string vs int)
    $numA = 0L
    $isNumA = ($vA -is [int] -or $vA -is [long] -or $vA -is [byte] -or $vA -is [int16])
    if ($isNumA) { $numA = [int64]$vA }
    elseif ($isStrA -and [int64]::TryParse($vA, [ref]$numA)) { $isNumA = $true }

    $numB = 0L
    $isNumB = ($vB -is [int] -or $vB -is [long] -or $vB -is [byte] -or $vB -is [int16])
    if ($isNumB) { $numB = [int64]$vB }
    elseif ($isStrB -and [int64]::TryParse($vB, [ref]$numB)) { $isNumB = $true }

    if ($isNumA -and $isNumB) {
        return ($numA -eq $numB)
    }

    # 7. Exact string representation equality
    return ([string]$vA -eq [string]$vB)
}

function Compare-WibDeltaPlan {
    param(
        [Parameter(Mandatory)]$CurrentPlan,
        [Parameter(Mandatory)][string]$PreviousManifestPath
    )

    if (-not (Test-Path -LiteralPath $PreviousManifestPath)) {
        throw "Previous manifest file not found: $PreviousManifestPath"
    }

    $raw = Get-Content -LiteralPath $PreviousManifestPath -Raw | ConvertFrom-Json
    $prevPlan = @()
    if ($raw.PSObject.Properties['plan']) {
        $prevPlan = @($raw.plan)
    }

    $prevMap = @{}
    foreach ($p in $prevPlan) {
        $sig = "$($p.module)|$($p.action)|$($p.target)"
        $prevMap[$sig] = $p
    }

    $deltaItems = New-Object System.Collections.ArrayList
    $newCount = 0
    $unchangedCount = 0

    foreach ($item in $CurrentPlan) {
        $sig = "$($item.Module)|$($item.Action)|$($item.Target)"
        if ($prevMap.ContainsKey($sig)) {
            $prevItem = $prevMap[$sig]
            $reasonMatch = Test-WibSemanticPropertyMatch -ItemA $item -ItemB $prevItem -PropName 'Reason'
            $revMatch    = Test-WibSemanticPropertyMatch -ItemA $item -ItemB $prevItem -PropName 'Reversibility'
            $valMatch    = Test-WibSemanticPropertyMatch -ItemA $item -ItemB $prevItem -PropName 'NewValue'
            $kindMatch   = Test-WibSemanticPropertyMatch -ItemA $item -ItemB $prevItem -PropName 'NewKind'

            if ($reasonMatch -and $revMatch -and $valMatch -and $kindMatch) {
                $item['DeltaStatus'] = 'Unchanged'
                $unchangedCount++
            } else {
                $item['DeltaStatus'] = 'Modified'
                $newCount++
            }
        } else {
            $item['DeltaStatus'] = 'New'
            $newCount++
        }
        [void]$deltaItems.Add($item)
    }

    $prevSha = ''
    if ($raw.PSObject.Properties['profile'] -and $raw.profile.PSObject.Properties['sha256']) { $prevSha = [string]$raw.profile.sha256 }
    elseif ($raw.PSObject.Properties['output'] -and $raw.output.PSObject.Properties['sha256']) { $prevSha = [string]$raw.output.sha256 }
    elseif ($raw.PSObject.Properties['sha256']) { $prevSha = [string]$raw.sha256 }
    $currentSigs = @{}; foreach ($i in $CurrentPlan) { $currentSigs["$($i.Module)|$($i.Action)|$($i.Target)"] = $true }
    $removed = @($prevMap.Keys | Where-Object { -not $currentSigs.ContainsKey($_) }).Count

    [PSCustomObject]@{
        TotalItems     = @($CurrentPlan).Count
        NewOrModified  = $newCount
        Unchanged      = $unchangedCount
        Removed        = $removed
        PreviousSha256 = $prevSha
        Plan           = @($deltaItems)
    }
}

