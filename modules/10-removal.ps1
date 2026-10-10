# Removal modules: provisioned apps (scanned), optional features/capabilities (scanned), Edge, OneDrive, telemetry scheduled tasks.

# ------------------------------------------------------------------ appx-removal
Register-WibModule -Id 'appx-removal' -Order 10 -Risk 'medium' -Reversibility 'reinstallable' `
    -Description 'Remove provisioned Store apps. Matches what is actually in the image against profile prefixes (remove/addRemove), minus keep rules.' `
    -Tradeoff 'Removes provisioned inbox applications. Frees disk space and reduces background activity; apps can be reinstalled from Microsoft Store.' `
    -Schema @{ remove = 'array'; addRemove = 'array'; keep = 'array' } `
    -Validate {
        param($S)
        if ($S -and $S.ContainsKey('remove')) {
            foreach ($p in @($S['remove'])) {
                if ([string]::IsNullOrWhiteSpace($p)) { throw "appx-removal: remove patterns cannot be empty or whitespace." }
                if ($p.Trim() -eq '*' -or $p.Trim().Length -lt 3) { throw "appx-removal: remove pattern '$p' is too broad or too short (< 3 chars)." }
            }
        }
        if ($S -and $S.ContainsKey('addRemove')) {
            foreach ($p in @($S['addRemove'])) {
                if ([string]::IsNullOrWhiteSpace($p)) { throw "appx-removal: addRemove patterns cannot be empty or whitespace." }
                if ($p.Trim() -eq '*' -or $p.Trim().Length -lt 3) { throw "appx-removal: addRemove pattern '$p' is too broad or too short (< 3 chars)." }
            }
        }
    } `
    -Plan {
        param($Ctx, $S)
        $m = Get-WibAppxMatches -Scan $Ctx.Scan -Settings $S
        foreach ($p in $m.Remove) {
            $bytes = 0
            if ($Ctx -and $Ctx.MountDir) {
                $pkgDir = Join-Path $Ctx.MountDir "Program Files\WindowsApps\$($p.PackageName)"
                if (Test-Path -LiteralPath $pkgDir) {
                    $measured = Get-ChildItem -LiteralPath $pkgDir -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum
                    if ($measured -and $null -ne $measured.Sum) { $bytes = [long]$measured.Sum }
                }
            }
            New-WibPlanItem 'appx-removal' 'Remove provisioned app' $p.DisplayName "matched '$($p.Pattern)'" -Reversibility 'reinstallable' -EstimatedBytes $bytes
        }
        foreach ($k in $m.Kept)   { New-WibPlanItem 'appx-removal' 'KEEP (protected)' $k.DisplayName $k.Reason -Reversibility 'reinstallable' }
    } `
    -Apply {
        param($Ctx, $S)
        $res = @()
        $m = Get-WibAppxMatches -Scan $Ctx.Scan -Settings $S
        foreach ($p in $m.Remove) {
            try {
                $null = Remove-AppxProvisionedPackage -Path $Ctx.MountDir -PackageName $p.PackageName
                $res += (New-WibResult 'appx-removal' $p.DisplayName 'applied')
            } catch {
                $res += (New-WibResult 'appx-removal' $p.DisplayName 'failed' $_.Exception.Message)
            }
        }
        $res
    } `
    -Verify {
        param($Ctx, $S)
        $m = Get-WibAppxMatches -Scan $Ctx.Scan -Settings $S
        try {
            $left = @(Get-AppxProvisionedPackage -Path $Ctx.MountDir -ErrorAction Stop | ForEach-Object { $_.PackageName })
        } catch {
            return ,(New-WibResult 'verify' 'appx: re-scan' 'fail' "could not re-scan image: $($_.Exception.Message)")
        }
        foreach ($p in $m.Remove) {
            if ($left -contains $p.PackageName) { New-WibResult 'verify' "appx: $($p.DisplayName)" 'fail' 'still provisioned' }
            else { New-WibResult 'verify' "appx: $($p.DisplayName)" 'pass' }
        }
    }

# ------------------------------------------------------------------ features-cleanup
Register-WibModule -Id 'features-cleanup' -Order 15 -Risk 'medium' -Reversibility 'reinstallable' `
    -Description 'Remove unused Windows optional features and capabilities by pattern with keep rules.' `
    -Tradeoff 'Disables legacy or unused optional features and capabilities (e.g. Internet Explorer, legacy Media Player, Steps Recorder, Quick Assist). These can be re-enabled later via DISM or Windows Features.' `
    -Schema @{
        removeFeatures        = 'array'
        addRemoveFeatures     = 'array'
        keepFeatures          = 'array'
        removeCapabilities    = 'array'
        addRemoveCapabilities = 'array'
        keepCapabilities      = 'array'
    } `
    -Plan {
        param($Ctx, $S)
        $m = Get-WibFeatureMatches -Scan $Ctx.Scan -Settings $S
        foreach ($f in $m.Features.Remove)     { New-WibPlanItem 'features-cleanup' 'Disable optional feature' $f.Name "matched '$($f.Pattern)'" -Reversibility 'reinstallable' }
        foreach ($f in $m.Features.Kept)       { New-WibPlanItem 'features-cleanup' 'KEEP optional feature (protected)' $f.Name $f.Reason -Reversibility 'reinstallable' }
        foreach ($c in $m.Capabilities.Remove) { New-WibPlanItem 'features-cleanup' 'Remove capability' $c.Name "matched '$($c.Pattern)'" -Reversibility 'reinstallable' }
        foreach ($c in $m.Capabilities.Kept)   { New-WibPlanItem 'features-cleanup' 'KEEP capability (protected)' $c.Name $c.Reason -Reversibility 'reinstallable' }
    } `
    -Apply {
        param($Ctx, $S)
        $res = @()
        $m = Get-WibFeatureMatches -Scan $Ctx.Scan -Settings $S
        foreach ($f in $m.Features.Remove) {
            try {
                if (Get-Command Disable-WindowsOptionalFeature -ErrorAction SilentlyContinue) {
                    $null = Disable-WindowsOptionalFeature -Path $Ctx.MountDir -FeatureName $f.Name -Remove -NoRestart -ErrorAction Stop
                } else {
                    [void](Invoke-WibNativeTool -ToolKey 'dismExe' -FilePath 'dism.exe' -Arguments @("/Image:$($Ctx.MountDir)", '/Disable-Feature', "/FeatureName:$($f.Name)", '/Remove', '/NoRestart'))
                    if ($LASTEXITCODE -ne 0) { throw "dism /Disable-Feature exit $LASTEXITCODE" }
                }
                $res += (New-WibResult 'features-cleanup' "feature: $($f.Name)" 'applied')
            } catch {
                $res += (New-WibResult 'features-cleanup' "feature: $($f.Name)" 'failed' $_.Exception.Message)
            }
        }
        foreach ($c in $m.Capabilities.Remove) {
            try {
                if (Get-Command Remove-WindowsCapability -ErrorAction SilentlyContinue) {
                    $null = Remove-WindowsCapability -Path $Ctx.MountDir -Name $c.Name -ErrorAction Stop
                } else {
                    [void](Invoke-WibNativeTool -ToolKey 'dismExe' -FilePath 'dism.exe' -Arguments @("/Image:$($Ctx.MountDir)", '/Remove-Capability', "/CapabilityName:$($c.Name)"))
                    if ($LASTEXITCODE -ne 0) { throw "dism /Remove-Capability exit $LASTEXITCODE" }
                }
                $res += (New-WibResult 'features-cleanup' "capability: $($c.Name)" 'applied')
            } catch {
                $res += (New-WibResult 'features-cleanup' "capability: $($c.Name)" 'failed' $_.Exception.Message)
            }
        }
        $res
    } `
    -Verify {
        param($Ctx, $S)
        $m = Get-WibFeatureMatches -Scan $Ctx.Scan -Settings $S
        $res = @()
        try {
            $featMap = @{}
            if (Get-Command Get-WindowsOptionalFeature -ErrorAction SilentlyContinue) {
                foreach ($f in @(Get-WindowsOptionalFeature -Path $Ctx.MountDir -ErrorAction Stop)) {
                    $featMap[$f.FeatureName] = [string]$f.State
                }
            }
            foreach ($f in $m.Features.Remove) {
                if ($featMap.ContainsKey($f.Name)) {
                    $st = $featMap[$f.Name]
                    if ($st -eq 'Enabled') {
                        $res += (New-WibResult 'verify' "feature: $($f.Name)" 'fail' 'feature still enabled')
                    } elseif ($st -like '*PayloadRemoved*' -or $st -eq 'Disabled') {
                        $res += (New-WibResult 'verify' "feature: $($f.Name)" 'pass' "state: $st")
                    } else {
                        $res += (New-WibResult 'verify' "feature: $($f.Name)" 'pass')
                    }
                } else {
                    $res += (New-WibResult 'verify' "feature: $($f.Name)" 'pass')
                }
            }
        } catch {
            $res += (New-WibResult 'verify' 'features: re-scan' 'fail' "could not re-scan optional features: $($_.Exception.Message)")
        }

        try {
            $remainingCaps = @()
            if (Get-Command Get-WindowsCapability -ErrorAction SilentlyContinue) {
                $remainingCaps = @(Get-WindowsCapability -Path $Ctx.MountDir -ErrorAction Stop | Where-Object { $_.State -eq 'Installed' } | ForEach-Object { $_.Name })
            }
            foreach ($c in $m.Capabilities.Remove) {
                if ($remainingCaps -contains $c.Name) {
                    $res += (New-WibResult 'verify' "capability: $($c.Name)" 'fail' 'capability still installed')
                } else {
                    $res += (New-WibResult 'verify' "capability: $($c.Name)" 'pass')
                }
            }
        } catch {
            $res += (New-WibResult 'verify' 'caps: re-scan' 'fail' "could not re-scan capabilities: $($_.Exception.Message)")
        }
        $res
    }

# ------------------------------------------------------------------ edge-removal
function Get-WibEdgePaths {
    param([hashtable]$S)
    $paths = @(
        'Program Files (x86)\Microsoft\Edge',
        'Program Files (x86)\Microsoft\EdgeUpdate',
        'Program Files (x86)\Microsoft\EdgeCore',
        'Program Files\Microsoft\Edge',
        'Program Files\Microsoft\EdgeCore'
    )
    # WebView2 is used by other apps/features; removal is opt-in.
    if ($S.ContainsKey('removeWebView') -and $S['removeWebView']) {
        $paths += 'Windows\System32\Microsoft-Edge-Webview'
        $paths += 'Program Files (x86)\Microsoft\EdgeWebView'
        $paths += 'Program Files\Microsoft\EdgeWebView'
    }
    $paths
}

$script:WibEdgeTasks = @(
    'Windows\System32\Tasks\MicrosoftEdgeUpdateTaskMachineCore',
    'Windows\System32\Tasks\MicrosoftEdgeUpdateTaskMachineUA'
)

Register-WibModule -Id 'edge-removal' -Order 20 -Risk 'medium' -Reversibility 'permanent' `
    -Description 'Delete Edge, EdgeUpdate, and EdgeCore from the image. Set removeWebView=true to also remove WebView2 runtime (breaks apps that depend on it).' `
    -Tradeoff 'Permanently deletes Edge, EdgeUpdate, and EdgeCore files from the image. Disables Edge update services. If removeWebView=true, also deletes WebView2 runtime (breaks apps like Teams or Widgets).' `
    -Schema @{ removeWebView = 'bool' } `
    -TweakProvider {
        param($S)
        $tweaks = @(
            (New-WibTweak SOFTWARE 'Policies\Microsoft\Edge' 'HubsSidebarEnabled' DWord 0),
            (New-WibTweak SYSTEM 'ControlSet001\Services\edgeupdate' 'Start' DWord 4),
            (New-WibTweak SYSTEM 'ControlSet001\Services\edgeupdatem' 'Start' DWord 4),
            (New-WibTweak SOFTWARE 'WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge' -Action DeleteKey),
            (New-WibTweak SOFTWARE 'WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge Update' -Action DeleteKey),
            (New-WibTweak SOFTWARE 'Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\Microsoft\EdgeUpdate' -Action DeleteKey)
        )
        $taskGuids = Get-WibOfflineTaskCacheGuids -SubkeyFilter 'EdgeUpdate'
        foreach ($tg in $taskGuids) {
            $tweaks += (New-WibTweak SOFTWARE "Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tasks\$($tg.Guid)" -Action DeleteKey)
        }
        $tweaks
    } `
    -Plan   {
        param($Ctx, $S)
        $items = @(Get-WibPathPlanItems $Ctx 'edge-removal' (Get-WibEdgePaths $S) 'Edge component' -Reversibility 'permanent')
        $items += @(Get-WibPathPlanItems $Ctx 'edge-removal' $script:WibEdgeTasks 'Edge update task' -Reversibility 'permanent')
        $items
    } `
    -Apply  {
        param($Ctx, $S)
        $res = @(Remove-WibImagePaths $Ctx 'edge-removal' (Get-WibEdgePaths $S))
        $res += @(Remove-WibImagePaths $Ctx 'edge-removal' $script:WibEdgeTasks)
        $res
    } `
    -Verify {
        param($Ctx, $S)
        $res = @(Test-WibPathsGone $Ctx 'edge-removal' (Get-WibEdgePaths $S))
        $res += @(Test-WibPathsGone $Ctx 'edge-removal' $script:WibEdgeTasks)
        $res
    }

# ------------------------------------------------------------------ onedrive-removal
$script:WibOneDrivePaths = @('Windows\System32\OneDriveSetup.exe', 'Windows\SysWOW64\OneDriveSetup.exe')

Register-WibModule -Id 'onedrive-removal' -Order 21 -Risk 'low' -Reversibility 'permanent' `
    -Description 'Remove the OneDrive installer and disable OneDrive file sync by policy.' `
    -Tradeoff 'Permanently removes the offline OneDrive setup executable and disables OneDrive file synchronization.' `
    -Schema @{} `
    -Tweaks @(
        (New-WibTweak SOFTWARE 'Policies\Microsoft\Windows\OneDrive' 'DisableFileSyncNGSC' DWord 1),
        (New-WibTweak DEFAULT 'Software\Microsoft\Windows\CurrentVersion\Run' 'OneDriveSetup' -Action DeleteValue),
        (New-WibTweak NTUSER 'Software\Microsoft\Windows\CurrentVersion\Run' 'OneDriveSetup' -Action DeleteValue)
    ) `
    -Plan   { param($Ctx, $S) Get-WibPathPlanItems $Ctx 'onedrive-removal' $script:WibOneDrivePaths 'OneDrive installer' -Reversibility 'permanent' } `
    -Apply  { param($Ctx, $S) Remove-WibImagePaths $Ctx 'onedrive-removal' $script:WibOneDrivePaths } `
    -Verify { param($Ctx, $S) Test-WibPathsGone $Ctx 'onedrive-removal' $script:WibOneDrivePaths }

# ------------------------------------------------------------------ tasks-cleanup
$script:WibTaskPaths = @(
    'Windows\System32\Tasks\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser',
    'Windows\System32\Tasks\Microsoft\Windows\Application Experience\ProgramDataUpdater',
    'Windows\System32\Tasks\Microsoft\Windows\Customer Experience Improvement Program',
    'Windows\System32\Tasks\Microsoft\Windows\Chkdsk\Proxy',
    'Windows\System32\Tasks\Microsoft\Windows\Windows Error Reporting\QueueReporting'
)

$script:WibTaskKeys = @($script:WibTaskPaths | ForEach-Object { $_ -replace '^Windows\\System32\\Tasks\\', '' })

Register-WibModule -Id 'tasks-cleanup' -Order 22 -Risk 'low' -Reversibility 'permanent' `
    -Description 'Delete telemetry-related scheduled task definitions (compat appraiser, CEIP, error reporting queue).' `
    -Tradeoff 'Permanently deletes telemetry, appraiser, and CEIP scheduled task definitions and their TaskCache registrations.' `
    -Schema @{} `
    -TweakProvider {
        param($S)
        $tweaks = @()
        foreach ($k in $script:WibTaskKeys) {
            $tweaks += (New-WibTweak SOFTWARE ('Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\' + $k) -Action DeleteKey)
        }
        $taskGuids = Get-WibOfflineTaskCacheGuids
        if ($taskGuids.Count -gt 0) {
            foreach ($tg in $taskGuids) {
                if ($tg.Path) {
                    $normP = ($tg.Path.TrimStart('\')).Replace('/', '\')
                    foreach ($k in $script:WibTaskKeys) {
                        if ($normP -ieq $k) {
                            $tweaks += (New-WibTweak SOFTWARE "Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tasks\$($tg.Guid)" -Action DeleteKey)
                            break
                        }
                    }
                }
            }
        }
        $tweaks
    } `
    -Plan   { param($Ctx, $S) Get-WibPathPlanItems $Ctx 'tasks-cleanup' $script:WibTaskPaths 'telemetry task' -Reversibility 'permanent' } `
    -Apply  { param($Ctx, $S) Remove-WibImagePaths $Ctx 'tasks-cleanup' $script:WibTaskPaths } `
    -Verify { param($Ctx, $S) Test-WibPathsGone $Ctx 'tasks-cleanup' $script:WibTaskPaths }
