# WIB core helpers. PowerShell 5.1+ compatible (no ternary, no ?? , no -AsHashtable).
# Dot-source this file; it uses $script: state.

if ($PSVersionTable.PSVersion.Major -ge 6) {
    # .NET Core / .NET 6+ moved GetAccessControl/SetAccessControl from FileSystemInfo to FileSystemAclExtensions.
    # Expose them as instance ScriptMethods on FileInfo, DirectoryInfo, and FileStream for cross-version parity with PS 5.1.
    $null = Update-TypeData -TypeName System.IO.FileInfo -MemberType ScriptMethod -MemberName GetAccessControl -Value {
        param($sections = ([System.Security.AccessControl.AccessControlSections]::Access -bor [System.Security.AccessControl.AccessControlSections]::Owner))
        try {
            $raw = if ($null -ne $this.PSObject) { $this.PSObject.BaseObject } else { $this }
            $m = ([type]'System.IO.FileSystemAclExtensions').GetMethod('GetAccessControl', [type[]]@([System.IO.FileInfo], [System.Security.AccessControl.AccessControlSections]))
            return $m.Invoke($null, @($raw, [System.Security.AccessControl.AccessControlSections]$sections))
        } catch {
            return (Get-Acl -LiteralPath $this.FullName)
        }
    } -Force -ErrorAction SilentlyContinue

    $null = Update-TypeData -TypeName System.IO.FileInfo -MemberType ScriptMethod -MemberName SetAccessControl -Value {
        param($acl)
        try {
            $raw = if ($null -ne $this.PSObject) { $this.PSObject.BaseObject } else { $this }
            $rawAcl = if ($null -ne $acl -and $null -ne $acl.PSObject) { $acl.PSObject.BaseObject } else { $acl }
            $m = ([type]'System.IO.FileSystemAclExtensions').GetMethod('SetAccessControl', [type[]]@([System.IO.FileInfo], [System.Security.AccessControl.FileSecurity]))
            [void]$m.Invoke($null, @($raw, $rawAcl))
        } catch {
            Set-Acl -LiteralPath $this.FullName -AclObject $acl
        }
    } -Force -ErrorAction SilentlyContinue

    $null = Update-TypeData -TypeName System.IO.DirectoryInfo -MemberType ScriptMethod -MemberName GetAccessControl -Value {
        param($sections = ([System.Security.AccessControl.AccessControlSections]::Access -bor [System.Security.AccessControl.AccessControlSections]::Owner))
        try {
            $raw = if ($null -ne $this.PSObject) { $this.PSObject.BaseObject } else { $this }
            $m = ([type]'System.IO.FileSystemAclExtensions').GetMethod('GetAccessControl', [type[]]@([System.IO.DirectoryInfo], [System.Security.AccessControl.AccessControlSections]))
            return $m.Invoke($null, @($raw, [System.Security.AccessControl.AccessControlSections]$sections))
        } catch {
            return (Get-Acl -LiteralPath $this.FullName)
        }
    } -Force -ErrorAction SilentlyContinue

    $null = Update-TypeData -TypeName System.IO.DirectoryInfo -MemberType ScriptMethod -MemberName SetAccessControl -Value {
        param($acl)
        try {
            $raw = if ($null -ne $this.PSObject) { $this.PSObject.BaseObject } else { $this }
            $rawAcl = if ($null -ne $acl -and $null -ne $acl.PSObject) { $acl.PSObject.BaseObject } else { $acl }
            $m = ([type]'System.IO.FileSystemAclExtensions').GetMethod('SetAccessControl', [type[]]@([System.IO.DirectoryInfo], [System.Security.AccessControl.DirectorySecurity]))
            [void]$m.Invoke($null, @($raw, $rawAcl))
        } catch {
            Set-Acl -LiteralPath $this.FullName -AclObject $acl
        }
    } -Force -ErrorAction SilentlyContinue

    $null = Update-TypeData -TypeName System.IO.FileStream -MemberType ScriptMethod -MemberName GetAccessControl -Value {
        $raw = if ($null -ne $this.PSObject) { $this.PSObject.BaseObject } else { $this }
        $m = ([type]'System.IO.FileSystemAclExtensions').GetMethod('GetAccessControl', [type[]]@([System.IO.FileStream]))
        return $m.Invoke($null, @($raw))
    } -Force -ErrorAction SilentlyContinue

    $null = Update-TypeData -TypeName System.IO.FileStream -MemberType ScriptMethod -MemberName SetAccessControl -Value {
        param($acl)
        $raw = if ($null -ne $this.PSObject) { $this.PSObject.BaseObject } else { $this }
        $rawAcl = if ($null -ne $acl -and $null -ne $acl.PSObject) { $acl.PSObject.BaseObject } else { $acl }
        $m = ([type]'System.IO.FileSystemAclExtensions').GetMethod('SetAccessControl', [type[]]@([System.IO.FileStream], [System.Security.AccessControl.FileSecurity]))
        [void]$m.Invoke($null, @($raw, $rawAcl))
    } -Force -ErrorAction SilentlyContinue
}

$script:WibVersion      = '0.2.29'
$script:WibModules      = [ordered]@{}
$script:WibLogPath      = $null
$script:WibLoadedHives  = @()
$script:WibHivePrefix   = 'wib_'
$script:WibDisableKernelIdentityHelper = $false
$script:WibDisableChildWorkingSetSampling = $false
if ($null -eq $script:WibAllowNativeToolMocks) { $script:WibAllowNativeToolMocks = $false }
if ($null -eq $script:WibFaultInjectionEnabled) { $script:WibFaultInjectionEnabled = $false }
$script:WibSensitiveCommitTestHook = $null
$script:WibBeforeBackupDeleteHook = $null
$script:WibBeforeBackupAclHook = $null
$script:WibLastFileTransactionStatus = $null
$script:WibNativeToolPathOverrides = @{}
$script:WibNativeToolNames = @('dismExe', 'oscdimgExe', 'regExe', 'compactExe', 'takeownExe', 'icaclsExe', 'attribExe')

$script:WibFirstPartyWindowsTools = @{
    'dismExe'    = 'dism.exe'
    'regExe'     = 'reg.exe'
    'compactExe' = 'compact.exe'
    'takeownExe' = 'takeown.exe'
    'icaclsExe'  = 'icacls.exe'
    'attribExe'  = 'attrib.exe'
}

function New-WibNativeToolEntry {
    return [ordered]@{
        invocations                 = [int]0
        totalElapsedMs              = [long]0
        maxProcessWorkingSetBytes   = $null
        lastExitCode                = $null
        launchFailures              = [int]0
        lastInvocationUtc           = $null
        workingSetMeasurementStatus = 'not-collected'
    }
}

function Reset-WibNativeToolTelemetry {
    $script:WibNativeToolTelemetry = [ordered]@{}
    $script:WibNativeToolCounts = [ordered]@{}
    foreach ($k in $script:WibNativeToolNames) {
        $script:WibNativeToolTelemetry[$k] = New-WibNativeToolEntry
        $script:WibNativeToolCounts[$k] = 0
    }
}
Reset-WibNativeToolTelemetry

function Add-WibNativeToolInvocation {
    param(
        [Parameter(Mandatory)][string]$Tool,
        [long]$ElapsedMs = 0,
        $WorkingSetBytes = $null,
        [ValidateSet('measured', 'unavailable', 'not-collected')][string]$WorkingSetStatus = 'not-collected',
        $ExitCode = $null,
        [switch]$LaunchFailed
    )
    if (-not $script:WibNativeToolTelemetry) { Reset-WibNativeToolTelemetry }
    if (-not $script:WibNativeToolTelemetry.Contains($Tool)) {
        $script:WibNativeToolTelemetry[$Tool] = New-WibNativeToolEntry
    }
    $entry = $script:WibNativeToolTelemetry[$Tool]
    $entry['lastInvocationUtc'] = (Get-Date).ToUniversalTime().ToString('o')
    if ($LaunchFailed) {
        $entry['launchFailures'] = [int]$entry['launchFailures'] + 1
        $entry['lastExitCode'] = $null
        if ($entry['workingSetMeasurementStatus'] -ne 'measured') {
            $entry['workingSetMeasurementStatus'] = 'unavailable'
        }
    } else {
        $entry['invocations'] = [int]$entry['invocations'] + 1
        if ($ElapsedMs -gt 0) {
            $entry['totalElapsedMs'] = [long]$entry['totalElapsedMs'] + [long]$ElapsedMs
        }
        if ($null -ne $ExitCode) {
            $entry['lastExitCode'] = [int]$ExitCode
        }
        if ($WorkingSetStatus -eq 'measured' -and $null -ne $WorkingSetBytes -and [long]$WorkingSetBytes -gt 0) {
            $ws = [long]$WorkingSetBytes
            if ($null -eq $entry['maxProcessWorkingSetBytes'] -or $ws -gt [long]$entry['maxProcessWorkingSetBytes']) {
                $entry['maxProcessWorkingSetBytes'] = $ws
            }
            $entry['workingSetMeasurementStatus'] = 'measured'
        } elseif ($WorkingSetStatus -eq 'unavailable' -and $entry['workingSetMeasurementStatus'] -ne 'measured') {
            $entry['workingSetMeasurementStatus'] = 'unavailable'
        }
    }
    if ($script:WibNativeToolCounts) {
        $script:WibNativeToolCounts[$Tool] = [int]$entry['invocations']
    }
}

function Get-WibNativeToolTelemetry {
    if (-not $script:WibNativeToolTelemetry) { Reset-WibNativeToolTelemetry }
    $total = 0
    $out = [ordered]@{
        totalCount = [int]0
    }
    foreach ($k in $script:WibNativeToolTelemetry.Keys) {
        $entry = $script:WibNativeToolTelemetry[$k]
        $inv = [int]$entry['invocations']
        $total += $inv
        $out[$k] = [ordered]@{
            invocations                 = $inv
            totalElapsedMs              = [long]$entry['totalElapsedMs']
            maxProcessWorkingSetBytes   = if ($null -ne $entry['maxProcessWorkingSetBytes']) { [long]$entry['maxProcessWorkingSetBytes'] } else { $null }
            lastExitCode                = if ($null -ne $entry['lastExitCode']) { [int]$entry['lastExitCode'] } else { $null }
            launchFailures              = [int]$entry['launchFailures']
            lastInvocationUtc           = $entry['lastInvocationUtc']
            workingSetMeasurementStatus = [string]$entry['workingSetMeasurementStatus']
        }
    }
    $out['totalCount'] = [int]$total
    return $out
}

function Format-WibProcessArgument {
    param([AllowEmptyString()][string]$Argument)
    if ($null -eq $Argument -or $Argument.Length -eq 0) {
        return '""'
    }
    if ($Argument -notmatch '[\s"]') {
        return $Argument
    }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"')
    $bsCount = 0
    for ($i = 0; $i -lt $Argument.Length; $i++) {
        $ch = $Argument[$i]
        if ($ch -eq '\') {
            $bsCount++
        } elseif ($ch -eq '"') {
            [void]$sb.Append(('\' * ($bsCount * 2 + 1)))
            [void]$sb.Append('"')
            $bsCount = 0
        } else {
            if ($bsCount -gt 0) {
                [void]$sb.Append(('\' * $bsCount))
                $bsCount = 0
            }
            [void]$sb.Append($ch)
        }
    }
    if ($bsCount -gt 0) {
        [void]$sb.Append(('\' * ($bsCount * 2)))
    }
    [void]$sb.Append('"')
    return $sb.ToString()
}

function Get-WibCanonicalWindowsRoot {
    [CmdletBinding()]
    param()

    $apiRoot = [System.Environment]::GetFolderPath(
        [System.Environment+SpecialFolder]::Windows
    )

    if ([string]::IsNullOrWhiteSpace($apiRoot)) {
        throw 'SECURITY ERROR: Windows directory could not be resolved through the OS API.'
    }

    $apiRoot = [System.IO.Path]::GetFullPath($apiRoot).TrimEnd('\')

    if (-not (Test-Path -LiteralPath $apiRoot -PathType Container)) {
        throw "SECURITY ERROR: OS-resolved Windows directory does not exist: '$apiRoot'."
    }

    foreach ($hint in @($env:SystemRoot, $env:windir)) {
        if ([string]::IsNullOrWhiteSpace($hint)) {
            continue
        }

        $hintFull = [System.IO.Path]::GetFullPath($hint).TrimEnd('\')

        if ($hintFull -ine $apiRoot) {
            throw "SECURITY ERROR: Windows root environment hint '$hintFull' disagrees with OS root '$apiRoot'."
        }
    }

    $item = Get-Item -LiteralPath $apiRoot -Force -ErrorAction Stop

    if (($item.Attributes -band
        [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "SECURITY ERROR: OS-resolved Windows root is a reparse point: '$apiRoot'."
    }

    return $apiRoot
}

function Assert-WibMicrosoftSignedOscdimg {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$ExpectedSha256
    )

    if (-not [System.IO.Path]::IsPathRooted($Path)) {
        throw "SECURITY ERROR: oscdimg path is not absolute: '$Path'."
    }

    $full = [System.IO.Path]::GetFullPath($Path)

    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
        throw "SECURITY ERROR: oscdimg does not exist: '$full'."
    }

    $pathState = Assert-WibSafeSensitiveOutputPath -Path $full
    $actualSha = Get-WibSha256 -Path $full

    if ([string]::IsNullOrWhiteSpace($ExpectedSha256) -or
        $actualSha -ine $ExpectedSha256) {
        throw "SECURITY ERROR: oscdimg SHA-256 does not match the pinned hash: '$full'."
    }

    $signature = Get-AuthenticodeSignature -FilePath $full

    if ($signature.Status -ne
        [System.Management.Automation.SignatureStatus]::Valid) {
        throw "SECURITY ERROR: oscdimg Authenticode status is '$($signature.Status)': '$full'."
    }

    if ($null -eq $signature.SignerCertificate -or
        $signature.SignerCertificate.Subject -notmatch
        '(?i)(?:^|,\s*)O=Microsoft Corporation(?:,|$)') {
        throw "SECURITY ERROR: oscdimg signer is not Microsoft Corporation: '$full'."
    }

    return $pathState
}

function Resolve-WibTrustedNativeTool {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ToolKey,

        [string]$FilePath = '',

        [string]$ExpectedSha256 = ''
    )

    # Validate the logical tool key BEFORE consulting any override.
    if ($ToolKey -notin $script:WibNativeToolNames) {
        throw "SECURITY ERROR: Unrecognized native tool key '$ToolKey'. Unapproved native tool key."
    }

    # Arbitrary path overrides are permitted only for tests.
    if ($script:WibNativeToolPathOverrides.ContainsKey($ToolKey)) {
        if (-not $script:WibAllowNativeToolMocks) {
            throw "SECURITY ERROR: Native tool overrides are disabled in production: '$ToolKey'."
        }

        $overridePath = $script:WibNativeToolPathOverrides[$ToolKey]

        if (-not [System.IO.Path]::IsPathRooted($overridePath)) {
            throw "SECURITY ERROR: Test override must be an absolute path: '$overridePath'."
        }

        $overrideFull = [System.IO.Path]::GetFullPath($overridePath)

        if (-not (Test-Path -LiteralPath $overrideFull -PathType Leaf)) {
            throw "SECURITY ERROR: Test override does not exist: '$overrideFull'."
        }

        return $overrideFull
    }

    if ($ToolKey -eq 'oscdimgExe') {
        if ([string]::IsNullOrWhiteSpace($FilePath)) {
            throw 'SECURITY ERROR: oscdimg requires an explicit absolute executable path.'
        }

        if (-not [System.IO.Path]::IsPathRooted($FilePath)) {
            throw "SECURITY ERROR: oscdimgExe must specify an absolute rooted path: '$FilePath'."
        }

        if (-not $script:WibAllowNativeToolMocks) {
            if ([string]::IsNullOrWhiteSpace($ExpectedSha256)) {
                throw "SECURITY ERROR: Production oscdimg execution requires an explicit -ExpectedSha256 pinned hash."
            }
            $null = Assert-WibMicrosoftSignedOscdimg `
                -Path $FilePath `
                -ExpectedSha256 $ExpectedSha256
        }

        return [System.IO.Path]::GetFullPath($FilePath)
    }

    if (-not $script:WibFirstPartyWindowsTools.ContainsKey($ToolKey)) {
        throw "SECURITY ERROR: Tool key '$ToolKey' has no approved Windows system executable."
    }

    $windowsRoot = Get-WibCanonicalWindowsRoot
    $system32 = Join-Path $windowsRoot 'System32'
    $sysnative = Join-Path $windowsRoot 'Sysnative'
    $exeName = $script:WibFirstPartyWindowsTools[$ToolKey]

    $candidate = $null

    if ([Environment]::Is64BitOperatingSystem -and
        -not [Environment]::Is64BitProcess) {
        if (-not (Test-Path -LiteralPath $sysnative -PathType Container)) {
            throw "SECURITY ERROR: Sysnative is unavailable for this 32-bit host: '$sysnative'."
        }

        $candidate = Join-Path $sysnative $exeName
    }
    else {
        $candidate = Join-Path $system32 $exeName
    }

    $candidate = [System.IO.Path]::GetFullPath($candidate)

    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        throw "SECURITY ERROR: Approved Windows binary is missing: '$candidate'."
    }

    $candidateState = Assert-WibSafeSensitiveOutputPath -Path $candidate

    if (-not $candidateState.LeafExists) {
        throw "SECURITY ERROR: Approved executable is missing: '$candidate'."
    }

    return $candidate
}

function Invoke-WibNativeTool {
    <#
    .SYNOPSIS
        Executes an external native tool (dism.exe, oscdimg.exe, reg.exe, compact.exe, takeown.exe,
        icacls.exe, attrib.exe) while recording invocation count, elapsed wall time, child-process peak
        working set (when launched as an OS child process), last exit code, and launch failures (WIB-018/WIB-021/WIB-029).
        Enforces approved absolute executable paths and confines test mocks behind $script:WibAllowNativeToolMocks.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ToolKey,
        [Parameter(Mandatory)][string]$FilePath,
        [AllowEmptyCollection()][string[]]$Arguments = @(),
        [Parameter()][string]$ExpectedSha256 = ''
    )
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    # WIB-021: In-process mocks are strictly confined to test mode via $script:WibAllowNativeToolMocks
    if ($script:WibAllowNativeToolMocks) {
        $cmdInfo = Get-Command -Name $FilePath -ErrorAction SilentlyContinue
        if ($null -ne $cmdInfo -and $cmdInfo.CommandType -in @('Function', 'Filter', 'Alias', 'Script')) {
            try {
                $global:LASTEXITCODE = 0
                $output = & $FilePath @Arguments 2>&1
                $exitCode = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 }
                $sw.Stop()
                Add-WibNativeToolInvocation -Tool $ToolKey -ElapsedMs $sw.ElapsedMilliseconds -WorkingSetBytes $null -WorkingSetStatus 'unavailable' -ExitCode $exitCode
                $global:LASTEXITCODE = $exitCode
                return $output
            } catch {
                $sw.Stop()
                Add-WibNativeToolInvocation -Tool $ToolKey -ElapsedMs $sw.ElapsedMilliseconds -WorkingSetBytes $null -WorkingSetStatus 'unavailable' -LaunchFailed
                throw
            }
        }
    }

    # Resolve executable to approved absolute path (WIB-021 / WIB-029)
    $trustedExePath = $null
    try {
        $trustedExePath = Resolve-WibTrustedNativeTool `
            -ToolKey $ToolKey `
            -FilePath $FilePath `
            -ExpectedSha256 $ExpectedSha256

        $trustedExeIdentity = Get-WibKernelNodeIdentity -LiteralPath $trustedExePath
        $trustedExeSha256 = Get-WibSha256 -Path $trustedExePath

        if ([string]::IsNullOrWhiteSpace($trustedExeIdentity) -or
            $trustedExeIdentity -like 'REPARSE:*' -or
            [string]::IsNullOrWhiteSpace($trustedExeSha256)) {
            throw "SECURITY ERROR: Could not establish executable identity/hash for '$trustedExePath'."
        }

        if ($ToolKey -eq 'oscdimgExe' -and
            -not $script:WibAllowNativeToolMocks -and
            -not [string]::IsNullOrWhiteSpace($ExpectedSha256) -and
            $trustedExeSha256 -ine $ExpectedSha256) {
            throw "SECURITY ERROR: oscdimg hash mismatch before launch."
        }
    } catch {
        $sw.Stop()
        Add-WibNativeToolInvocation -Tool $ToolKey -ElapsedMs $sw.ElapsedMilliseconds -WorkingSetBytes $null -WorkingSetStatus 'unavailable' -LaunchFailed
        throw
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $trustedExePath
    $quotedArgs = New-Object System.Collections.Generic.List[string]
    foreach ($a in $Arguments) {
        [void]$quotedArgs.Add((Format-WibProcessArgument -Argument $a))
    }
    $psi.Arguments = ($quotedArgs -join ' ')
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    $started = $false
    try {
        try {
            # Final executable identity and hash verification at the launch boundary (WIB-029)
            $launchResolvedPath = Resolve-WibTrustedNativeTool `
                -ToolKey $ToolKey `
                -FilePath $FilePath `
                -ExpectedSha256 $ExpectedSha256

            if ($launchResolvedPath -ine $trustedExePath) {
                throw "SECURITY ERROR: Executable path changed before launch for '$ToolKey'."
            }

            $launchIdentity = Get-WibKernelNodeIdentity -LiteralPath $trustedExePath
            $launchSha256 = Get-WibSha256 -Path $trustedExePath

            if ($launchIdentity -cne $trustedExeIdentity -or
                $launchSha256 -ine $trustedExeSha256) {
                throw "SECURITY ERROR: Executable identity/hash changed before launch: '$trustedExePath'."
            }

            # Open executable handle with FileShare.Read to prevent concurrent write/delete/truncate replacement
            # during the validation-to-launch window (WIB-038).
            $exeLockStream = $null
            try {
                $exeLockStream = [System.IO.File]::Open(
                    $trustedExePath,
                    [System.IO.FileMode]::Open,
                    [System.IO.FileAccess]::Read,
                    [System.IO.FileShare]::Read
                )

                $lockedHandleId = [WibKernelPathHelper]::GetKernelNodeIdentityFromHandle($exeLockStream.SafeFileHandle)
                if ($lockedHandleId -cne $trustedExeIdentity) {
                    throw "SECURITY ERROR: Executable identity changed upon acquiring launch lock: '$trustedExePath'."
                }

                if ($ToolKey -eq 'oscdimgExe' -and -not $script:WibAllowNativeToolMocks) {
                    if ([string]::IsNullOrWhiteSpace($ExpectedSha256)) {
                        throw "SECURITY ERROR: Production oscdimg execution requires an explicit -ExpectedSha256 pinned hash."
                    }
                    $null = Assert-WibMicrosoftSignedOscdimg `
                        -Path $trustedExePath `
                        -ExpectedSha256 $ExpectedSha256
                }

                $started = $proc.Start()
            }
            finally {
                if ($null -ne $exeLockStream) {
                    $exeLockStream.Dispose()
                }
            }
        } catch {
            $sw.Stop()
            Add-WibNativeToolInvocation -Tool $ToolKey -ElapsedMs $sw.ElapsedMilliseconds -WorkingSetBytes $null -WorkingSetStatus 'unavailable' -LaunchFailed
            throw
        }
        if (-not $started) {
            $sw.Stop()
            Add-WibNativeToolInvocation -Tool $ToolKey -ElapsedMs $sw.ElapsedMilliseconds -WorkingSetBytes $null -WorkingSetStatus 'unavailable' -LaunchFailed
            throw "Failed to start native process '$trustedExePath'."
        }

        $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
        $stderrTask = $proc.StandardError.ReadToEndAsync()

        [long]$peakWs = 0
        $wsMeasured = $false
        if (-not $script:WibDisableChildWorkingSetSampling) {
            try {
                $proc.Refresh()
                $ws = [long]$proc.PeakWorkingSet64
                if ($ws -le 0) { $ws = [long]$proc.WorkingSet64 }
                if ($ws -gt $peakWs) { $peakWs = $ws; $wsMeasured = $true }
            } catch { Write-Verbose $_.Exception.Message }
        }

        while (-not $proc.WaitForExit(10)) {
            if (-not $script:WibDisableChildWorkingSetSampling) {
                try {
                    $proc.Refresh()
                    $ws = [long]$proc.PeakWorkingSet64
                    if ($ws -le 0) { $ws = [long]$proc.WorkingSet64 }
                    if ($ws -gt $peakWs) { $peakWs = $ws; $wsMeasured = $true }
                } catch { Write-Verbose $_.Exception.Message }
            }
        }
        if (-not $script:WibDisableChildWorkingSetSampling) {
            try {
                $proc.Refresh()
                $ws = [long]$proc.PeakWorkingSet64
                if ($ws -le 0) { $ws = [long]$proc.WorkingSet64 }
                if ($ws -gt $peakWs) { $peakWs = $ws; $wsMeasured = $true }
            } catch { Write-Verbose $_.Exception.Message }
        }
        $proc.WaitForExit()
        $exitCode = [int]$proc.ExitCode
        $sw.Stop()

        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()

        $wsStatus = if ($wsMeasured -and $peakWs -gt 0) { 'measured' } else { 'unavailable' }
        $wsVal = if ($wsStatus -eq 'measured') { [long]$peakWs } else { $null }
        Add-WibNativeToolInvocation -Tool $ToolKey -ElapsedMs $sw.ElapsedMilliseconds -WorkingSetBytes $wsVal -WorkingSetStatus $wsStatus -ExitCode $exitCode
        $global:LASTEXITCODE = $exitCode

        $combined = New-Object System.Collections.Generic.List[string]
        if (-not [string]::IsNullOrEmpty($stdout)) {
            foreach ($line in ($stdout -split "\r?\n")) {
                if ($line.Length -gt 0) { [void]$combined.Add($line) }
            }
        }
        if (-not [string]::IsNullOrEmpty($stderr)) {
            foreach ($line in ($stderr -split "\r?\n")) {
                if ($line.Length -gt 0) { [void]$combined.Add($line) }
            }
        }
        return $combined.ToArray()
    } finally {
        $proc.Dispose()
    }
}

$script:WibHiveFiles    = @{
    SOFTWARE = 'Windows\System32\config\SOFTWARE'
    SYSTEM   = 'Windows\System32\config\SYSTEM'
    DEFAULT  = 'Windows\System32\config\DEFAULT'
    NTUSER   = 'Users\Default\NTUSER.DAT'
}

# ---------------------------------------------------------------- logging
function Set-WibLogPath { param([string]$Path) $script:WibLogPath = $Path }

function Write-WibLog {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'STEP', 'OK')][string]$Level = 'INFO'
    )
    $line = '[{0}] [{1}] {2}' -f (Get-Date).ToString('HH:mm:ss'), $Level, $Message
    $color = 'Gray'
    switch ($Level) {
        'WARN'  { $color = 'Yellow' }
        'ERROR' { $color = 'Red' }
        'STEP'  { $color = 'Cyan' }
        'OK'    { $color = 'Green' }
    }
    Write-Host $line -ForegroundColor $color
    if ($script:WibLogPath) { Add-Content -LiteralPath $script:WibLogPath -Value $line }
}

# ---------------------------------------------------------------- data helpers
function ConvertTo-WibHashtable {
    param($InputObject)
    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [System.Collections.IDictionary]) {
        $h = @{}
        foreach ($k in $InputObject.Keys) { $h[$k] = ConvertTo-WibHashtable $InputObject[$k] }
        return $h
    }
    if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
        $h = @{}
        foreach ($p in $InputObject.PSObject.Properties) { $h[$p.Name] = ConvertTo-WibHashtable $p.Value }
        return $h
    }
    if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
        $list = @()
        foreach ($i in $InputObject) { $list += , (ConvertTo-WibHashtable $i) }
        return , $list
    }
    return $InputObject
}

function ConvertTo-WibCanonicalObject {
    param($InputObject)
    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [System.Collections.IDictionary]) {
        $ordered = [ordered]@{}
        $sortedKeys = @($InputObject.Keys) | Sort-Object
        foreach ($k in $sortedKeys) {
            $ordered[$k] = ConvertTo-WibCanonicalObject $InputObject[$k]
        }
        return $ordered
    }
    if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
        $ordered = [ordered]@{}
        $sortedProps = @($InputObject.PSObject.Properties.Name) | Sort-Object
        foreach ($p in $sortedProps) {
            $ordered[$p] = ConvertTo-WibCanonicalObject $InputObject.$p
        }
        return $ordered
    }
    if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
        $list = @()
        foreach ($item in $InputObject) {
            $list += , (ConvertTo-WibCanonicalObject $item)
        }
        return , $list
    }
    return $InputObject
}

function ConvertTo-WibCanonicalJson {
    param($InputObject)
    $canonical = ConvertTo-WibCanonicalObject $InputObject
    $json = ConvertTo-Json -InputObject $canonical -Depth 10 -Compress
    [regex]::Replace($json, '\\u([0-9a-fA-F]{4})', {
        param($m)
        $c = [char][Convert]::ToInt32($m.Groups[1].Value, 16)
        if ([char]::IsControl($c)) { $m.Value } else { [string]$c }
    })
}

function Get-WibProfileCanonicalHash {
    param($BuildProfile)
    $profileToHash = @{}
    foreach ($k in $BuildProfile.Keys) {
        if ($k -notlike '_*') {
            $profileToHash[$k] = $BuildProfile[$k]
        }
    }
    $json = ConvertTo-WibCanonicalJson $profileToHash
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $hasher = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hashBytes = $hasher.ComputeHash($bytes)
        $sb = New-Object System.Text.StringBuilder
        foreach ($b in $hashBytes) { [void]$sb.Append($b.ToString('x2')) }
        return $sb.ToString()
    } finally {
        $hasher.Dispose()
    }
}

function Get-WibSha256 {
    param([Parameter(Mandatory)][string]$Path)
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function New-WibCryptoSecret {
    param([int]$ByteLength = 32)
    $rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
    try {
        $bytes = New-Object byte[] $ByteLength
        $rng.GetBytes($bytes)
        $sb = New-Object System.Text.StringBuilder
        foreach ($b in $hashBytes = $bytes) { [void]$sb.Append($b.ToString('x2')) }
        return $sb.ToString()
    } finally {
        $rng.Dispose()
    }
}

<#
.SYNOPSIS
    Computes an HMAC-SHA256 authentication code for crash-consistency verification.
.DESCRIPTION
    OPERATIONAL TRUST BOUNDARY:
    WIB uses HMAC-SHA256 to bind in-flight append transaction markers (checkpoint.transaction.json)
    to the workspace recovery ledger (recovery-state.json). This operates under a TRUSTED RECOVERY-LEDGER
    MODEL: it guarantees crash consistency, detects partial/interrupted appends, and prevents unauthorized
    or stale marker re-use within the workspace. It is NOT an external cryptographic root-of-trust against
    an adversary possessing arbitrary filesystem write access to the recovery ledger itself.
#>
function Get-WibHmacSha256 {
    param(
        [Parameter(Mandatory)][string]$Message,
        [Parameter(Mandatory)][string]$KeyHex
    )
    $keyLen = [int]($KeyHex.Length / 2)
    $keyBytes = New-Object byte[] $keyLen
    for ($i = 0; $i -lt $keyLen; $i++) {
        $keyBytes[$i] = [Convert]::ToByte($KeyHex.Substring($i * 2, 2), 16)
    }
    $hmac = New-Object System.Security.Cryptography.HMACSHA256 (,$keyBytes)
    try {
        $msgBytes = [System.Text.Encoding]::UTF8.GetBytes($Message)
        $hashBytes = $hmac.ComputeHash($msgBytes)
        $sb = New-Object System.Text.StringBuilder
        foreach ($b in $hashBytes) { [void]$sb.Append($b.ToString('x2')) }
        return $sb.ToString()
    } finally {
        $hmac.Dispose()
    }
}

function Get-WibAclFingerprint {
    <#
    .SYNOPSIS
        Computes a deterministic SHA-256 hex digest of a file's DACL (Access section),
        including AreAccessRulesProtected and ordinal-sorted SID-normalized access rules (WIB-016).
    #>
    [CmdletBinding()]
    param(
        [string]$Path,
        [System.Security.AccessControl.FileSecurity]$Acl
    )
    $aclObj = $Acl
    if ($null -eq $aclObj) {
        if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            throw "Get-WibAclFingerprint requires an existing file -Path or a -Acl FileSecurity object."
        }
        $fi = New-Object System.IO.FileInfo($Path)
        $aclObj = $fi.GetAccessControl([System.Security.AccessControl.AccessControlSections]::Access)
    }
    $isProtected = [bool]$aclObj.AreAccessRulesProtected
    $rules = $aclObj.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier])
    $records = New-Object System.Collections.Generic.List[string]
    foreach ($r in $rules) {
        $sidVal = $r.IdentityReference.Value
        $act = [string]$r.AccessControlType
        $rights = [int]$r.FileSystemRights
        $inh = [int]$r.InheritanceFlags
        $prop = [int]$r.PropagationFlags
        $isInh = [bool]$r.IsInherited
        [void]$records.Add(('{0}|{1}|{2}|{3}|{4}|{5}' -f $sidVal, $act, $rights, $inh, $prop, $isInh))
    }
    $sorted = @($records.ToArray())
    [Array]::Sort($sorted, [System.StringComparer]::Ordinal)
    $canonical = "Protected=$isProtected`n" + ($sorted -join "`n")
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($canonical)
    $hasher = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hashBytes = $hasher.ComputeHash($bytes)
        $sb = New-Object System.Text.StringBuilder
        foreach ($b in $hashBytes) { [void]$sb.Append($b.ToString('x2')) }
        return $sb.ToString()
    } finally {
        $hasher.Dispose()
    }
}
function Get-WibPathOwnerSid {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$IsDirectory
    )
    $sections = [System.Security.AccessControl.AccessControlSections]::Owner
    $acl = if ($IsDirectory) {
        (New-Object System.IO.DirectoryInfo($Path)).GetAccessControl($sections)
    } else {
        (New-Object System.IO.FileInfo($Path)).GetAccessControl($sections)
    }
    $ownerObj = $acl.GetOwner([System.Security.Principal.SecurityIdentifier])
    if ($null -ne $ownerObj) {
        return $ownerObj.Value
    }
    return $null
}

function Get-WibFileDaclSnapshot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$LiteralPath)
    $fi = New-Object System.IO.FileInfo($LiteralPath)
    $sections = (
        [System.Security.AccessControl.AccessControlSections]::Access -bor
        [System.Security.AccessControl.AccessControlSections]::Owner
    )
    $acl = $fi.GetAccessControl($sections)
    $ownerObj = $acl.GetOwner([System.Security.Principal.SecurityIdentifier])
    $ownerSid = if ($null -ne $ownerObj) { $ownerObj.Value } else { $null }
    $daclSddl = $acl.GetSecurityDescriptorSddlForm([System.Security.AccessControl.AccessControlSections]::Access)
    $fullSddl = $acl.GetSecurityDescriptorSddlForm($sections)
    $fp = Get-WibAclFingerprint -Acl $acl
    if ([string]::IsNullOrWhiteSpace($daclSddl) -or [string]::IsNullOrWhiteSpace($fp)) {
        throw "Failed to capture complete DACL snapshot for '$LiteralPath'."
    }
    return @{
        Acl         = $acl
        Sddl        = $daclSddl
        FullSddl    = $fullSddl
        OwnerSid    = $ownerSid
        Fingerprint = $fp
    }
}

function Restore-WibFileDaclSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$LiteralPath,
        [Parameter(Mandatory)]$Snapshot
    )
    if ($null -eq $Snapshot -or [string]::IsNullOrWhiteSpace([string]$Snapshot.Sddl)) {
        throw "Invalid or empty DACL snapshot supplied for '$LiteralPath'."
    }
    $fi = New-Object System.IO.FileInfo($LiteralPath)
    $restoreAcl = New-Object System.Security.AccessControl.FileSecurity

    $restoredFull = $false
    if (-not [string]::IsNullOrWhiteSpace([string]$Snapshot.FullSddl)) {
        try {
            $sections = (
                [System.Security.AccessControl.AccessControlSections]::Access -bor
                [System.Security.AccessControl.AccessControlSections]::Owner
            )
            $restoreAcl.SetSecurityDescriptorSddlForm([string]$Snapshot.FullSddl, $sections)
            $fi.SetAccessControl($restoreAcl)
            $restoredFull = $true
        } catch { }
    }

    if (-not $restoredFull) {
        $restoreAcl.SetSecurityDescriptorSddlForm([string]$Snapshot.Sddl, [System.Security.AccessControl.AccessControlSections]::Access)
        $fi.SetAccessControl($restoreAcl)
    }

    $currentFp = Get-WibAclFingerprint -Path $LiteralPath
    if ($currentFp -ine [string]$Snapshot.Fingerprint) {
        throw "CRITICAL ROLLBACK FAILURE: Restored DACL fingerprint does not match original for '$LiteralPath'."
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$Snapshot.OwnerSid)) {
        $currentOwner = $null
        try {
            $currentAcl = $fi.GetAccessControl([System.Security.AccessControl.AccessControlSections]::Owner)
            $ownerObj = $currentAcl.GetOwner([System.Security.Principal.SecurityIdentifier])
            $currentOwner = if ($null -ne $ownerObj) { $ownerObj.Value } else { $null }
        } catch { }

        if ($currentOwner -ine [string]$Snapshot.OwnerSid) {
            throw "CRITICAL ROLLBACK FAILURE: Unable to restore original owner SID '$($Snapshot.OwnerSid)' (current: '$currentOwner') on '$LiteralPath'."
        }
    }
}

function Invoke-WibFileReplace {
    <#
    .SYNOPSIS
        Atomically replaces a destination file with a staged source file, creating a backup copy.
    .DESCRIPTION
        Enforces handle-bound destination identity and SHA-256 validation before invoking Win32 ReplaceFileW.
        If the destination file does not match the expected kernel node identity or content, replacement
        is rejected fail-closed without modifying, moving, or replacing the destination occupant.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$DestinationPath,
        [Parameter(Mandatory)][string]$BackupPath,
        [string]$ExpectedDestinationIdentity = '',
        [string]$ExpectedDestinationSha256 = ''
    )
    if (-not [string]::IsNullOrWhiteSpace($ExpectedDestinationIdentity)) {
        $replaceErr = $null
        $replaced = [WibKernelPathHelper]::ReplaceFileIfDestinationMatches(
            $SourcePath,
            $DestinationPath,
            $BackupPath,
            $ExpectedDestinationIdentity,
            $ExpectedDestinationSha256,
            [ref]$replaceErr
        )
        if (-not $replaced) {
            throw "SECURITY ERROR: Atomic replacement failed for '$DestinationPath': $replaceErr"
        }
    } else {
        [System.IO.File]::Replace($SourcePath, $DestinationPath, $BackupPath)
    }
}

function Set-WibDurableJsonFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyCollection()][AllowNull()]$Data,
        [int]$Depth = 10,
        [switch]$ProtectAcl
    )
    $leafName = Split-Path -Leaf $Path
    $isSensitiveLedger = ($ProtectAcl -or ($leafName -in @('recovery-state.json', 'checkpoint.transaction.json', 'terminal-state.json')))
    if ($isSensitiveLedger) {
        if (-not (Get-Command Test-WibVolumePersistentAclSupport -ErrorAction SilentlyContinue) -or
            -not (Get-Command Protect-WibSensitiveFileAcl -ErrorAction SilentlyContinue)) {
            throw "SECURITY ERROR: Mandatory ACL protection helpers (Test-WibVolumePersistentAclSupport / Protect-WibSensitiveFileAcl) are unavailable; refusing to write sensitive file '$Path'."
        }
    }

    $pathSnapshot = Assert-WibSafeSensitiveOutputPath `
        -Path $Path `
        -AllowMissingLeaf `
        -CreateMissingParent `
        -ProtectCreatedDirectories:$isSensitiveLedger

    $Path = $pathSnapshot.Path
    $parentDir = [System.IO.Path]::GetDirectoryName($Path)

    if ([string]::IsNullOrWhiteSpace($parentDir)) {
        throw "SECURITY ERROR: Could not determine output parent directory for '$Path'."
    }

    if ($isSensitiveLedger) {
        if (-not (Test-WibVolumePersistentAclSupport -Path $parentDir)) {
            throw "SECURITY ERROR: Destination volume does not support persistent ACLs: '$Path'."
        }
    }

    $existedBefore = $pathSnapshot.LeafExists
    $origDestAclSnapshot = $null
    $origDestSha256 = $null
    $origDestKernelId = $pathSnapshot.LeafIdentity

    if ($existedBefore) {
        try {
            $origDestSha256 = Get-WibSha256 -Path $Path

            if ([string]::IsNullOrWhiteSpace($origDestSha256)) {
                throw 'Could not capture the original target SHA-256.'
            }

            $origDestAclSnapshot = Get-WibFileDaclSnapshot -LiteralPath $Path

            Assert-WibSensitivePathSnapshot -Snapshot $pathSnapshot | Out-Null

            if ((Get-WibSha256 -Path $Path) -ine $origDestSha256) {
                throw 'Destination bytes changed while the original state was being captured.'
            }
        }
        catch {
            throw "Cannot safely overwrite '$Path': failed to capture original file hash or DACL snapshot before mutation: $($_.Exception.Message)"
        }
    }

    $tmpPath = "$Path.$([System.Guid]::NewGuid().ToString('N')).tmp"
    $bakPath = "$Path.$([System.Guid]::NewGuid().ToString('N')).bak"
    $transactionCommitted = $false
    $newTargetMoveSucceeded = $false
    $stageCreatedKernelId = $null
    $stageSnapshot = $null
    $backupKernelId = $null

    try {
        $json = ConvertTo-Json -InputObject $Data -Depth $Depth

        # Always create a new, empty stage file atomically with FileMode.CreateNew and capture handle identity (WIB-033).
        $stageCreatedKernelId = $null
        $stageCreateStream = $null
        try {
            $stageCreateStream = [System.IO.File]::Open(
                $tmpPath,
                [System.IO.FileMode]::CreateNew,
                [System.IO.FileAccess]::ReadWrite,
                [System.IO.FileShare]::None
            )

            $stageCreatedKernelId = [WibKernelPathHelper]::GetKernelNodeIdentityFromHandle(
                $stageCreateStream.SafeFileHandle
            )

            if ([string]::IsNullOrWhiteSpace($stageCreatedKernelId) -or
                $stageCreatedKernelId -like 'REPARSE:*') {
                throw "SECURITY ERROR: Could not establish the created stage identity: '$tmpPath'."
            }

            $stageCreateStream.Flush($true)
        }
        finally {
            if ($null -ne $stageCreateStream) {
                $stageCreateStream.Dispose()
            }
        }

        # Keep stage empty while applying sensitive ACL; verify identity before and after
        if ($isSensitiveLedger) {
            $beforeAclId = Get-WibKernelNodeIdentity -LiteralPath $tmpPath
            if ($beforeAclId -cne $stageCreatedKernelId) {
                throw "SECURITY ERROR: Stage identity changed before ACL protection: '$tmpPath'."
            }
            if (-not (Protect-WibSensitiveFileAcl -Path $tmpPath)) {
                throw "Failed to protect staging file ACL: '$tmpPath'."
            }
            $afterAclId = Get-WibKernelNodeIdentity -LiteralPath $tmpPath
            if ($afterAclId -cne $stageCreatedKernelId) {
                throw "SECURITY ERROR: Stage identity changed during ACL protection: '$tmpPath'."
            }
        }

        # Reopen the created stage exclusively, verify handle identity, and write payload through handle (never truncate)
        $fs = [System.IO.File]::Open(
            $tmpPath,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::ReadWrite,
            [System.IO.FileShare]::None
        )

        try {
            $fsHandleId = [WibKernelPathHelper]::GetKernelNodeIdentityFromHandle($fs.SafeFileHandle)
            if ($fsHandleId -cne $stageCreatedKernelId) {
                throw "SECURITY ERROR: Stage identity changed prior to payload write: '$tmpPath'."
            }

            $utf8NoBom = New-Object System.Text.UTF8Encoding -ArgumentList @($false)
            $writer = New-Object System.IO.StreamWriter -ArgumentList $fs, $utf8NoBom

            $writer.Write($json)
            $writer.Flush()
            $fs.Flush($true)
        }
        finally {
            if ($writer) { $writer.Dispose() }
            if ($fs) { $fs.Dispose() }
        }

        $stageSnapshot = Get-WibValidatedStageSnapshot `
            -Path $tmpPath `
            -PayloadKind Json `
            -RequireSensitiveAcl:$isSensitiveLedger

        if ($stageSnapshot.KernelIdentity -cne $stageCreatedKernelId) {
            throw "SECURITY ERROR: Staging identity changed between creation and validation: '$tmpPath'."
        }

        # Final pre-commit validation. Both checks must pass before any mutation.
        Invoke-WibSensitiveCommitTestHook `
            -Boundary 'BeforeFinalValidation' `
            -StagePath $tmpPath `
            -DestinationPath $Path

        Assert-WibSensitivePathSnapshot -Snapshot $pathSnapshot | Out-Null
        Assert-WibStagedFileStillMatches -Snapshot $stageSnapshot | Out-Null

        if ($existedBefore) {
            if ((Get-WibKernelNodeIdentity -LiteralPath $Path) -cne $origDestKernelId) {
                throw "SECURITY ERROR: TOCTOU identity mismatch on destination file '$Path' before replacement."
            }

            if ((Get-WibSha256 -Path $Path) -ine $origDestSha256) {
                throw "SECURITY ERROR: Existing destination bytes changed before replacement: '$Path'."
            }

            if ($isSensitiveLedger) {
                if (-not (Protect-WibSensitiveFileAcl -Path $Path)) {
                    throw "Failed to secure existing target before replacement: '$Path'."
                }
            }

            # Recheck after ACL mutation, immediately before the replacement call.
            Assert-WibSensitivePathSnapshot -Snapshot $pathSnapshot | Out-Null
            Assert-WibStagedFileStillMatches -Snapshot $stageSnapshot | Out-Null

            Invoke-WibSensitiveCommitTestHook `
                -Boundary 'AfterFinalValidationBeforeReplace' `
                -StagePath $tmpPath `
                -DestinationPath $Path

            Invoke-WibFileReplace `
                -SourcePath $tmpPath `
                -DestinationPath $Path `
                -BackupPath $bakPath `
                -ExpectedDestinationIdentity $origDestKernelId `
                -ExpectedDestinationSha256 $origDestSha256

            # Capture the replacement backup and verify it contains the original bytes.
            if (Test-Path -LiteralPath $bakPath -PathType Leaf) {
                $backupKernelId = Get-WibKernelNodeIdentity -LiteralPath $bakPath
                $backupSha = Get-WibSha256 -Path $bakPath

                if ([string]::IsNullOrWhiteSpace($backupKernelId) -or
                    $backupKernelId -like 'REPARSE:*') {
                    throw "CRITICAL: Invalid replacement backup identity: '$bakPath'."
                }

                if ($backupSha -ine $origDestSha256) {
                    throw "CRITICAL: Replacement backup integrity mismatch: '$bakPath'."
                }
            }
        }
        else {
            # In the create-new branch, run final validation first, then test hook, then File.Move (WIB-036)
            Assert-WibSensitivePathSnapshot -Snapshot $pathSnapshot | Out-Null
            Assert-WibStagedFileStillMatches -Snapshot $stageSnapshot | Out-Null

            Invoke-WibSensitiveCommitTestHook `
                -Boundary 'AfterFinalValidationBeforeNewTargetMove' `
                -StagePath $tmpPath `
                -DestinationPath $Path

            Invoke-WibSensitiveCommitTestHook `
                -Boundary 'ImmediatelyBeforeNewTargetMove' `
                -StagePath $tmpPath `
                -DestinationPath $Path

            [System.IO.File]::Move($tmpPath, $Path)

            # Set only after File.Move returns successfully.
            $newTargetMoveSucceeded = $true
        }

        # Post-mutation target verification
        $committedIdentity = Get-WibKernelNodeIdentity -LiteralPath $Path
        $committedSha = Get-WibSha256 -Path $Path

        if ($committedIdentity -cne $stageSnapshot.KernelIdentity) {
            throw "SECURITY ERROR: Committed target does not match the verified staging file identity: '$Path'."
        }

        if ($committedSha -ine $stageSnapshot.Sha256) {
            throw "SECURITY ERROR: Committed target does not match the verified staging SHA-256: '$Path'."
        }

        if ($isSensitiveLedger) {
            if (-not (Protect-WibSensitiveFileAcl -Path $Path)) {
                throw "Post-replace Protect-WibSensitiveFileAcl returned false for target '$Path'."
            }
        }

        $postReadBack = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
        $postParsed = ConvertFrom-Json -InputObject $postReadBack -ErrorAction Stop
        if ($null -eq $postParsed -and ($postReadBack.Trim() -replace '\s+', '') -eq '[]') {
            $postParsed = @()
        }
        if ($null -eq $postParsed -and $null -ne $Data) {
            throw "Post-replacement JSON verification failed for '$Path'."
        }

        # TRANSACTION COMMITTED: Target file is fully verified and committed
        $transactionCommitted = $true

        # Post-commit backup cleanup
        if (Test-Path -LiteralPath $bakPath -PathType Leaf) {
            $backupCleanup = Complete-WibBackupCleanup `
                -Path $bakPath `
                -ExpectedIdentity $backupKernelId `
                -ExpectedSha256 $origDestSha256 `
                -Sensitive:$isSensitiveLedger `
                -Outcome Committed

            $script:WibLastFileTransactionStatus = $backupCleanup
            $global:WibLastFileTransactionStatus = $backupCleanup
        }
    }
    catch {
        $writeErr = $_.Exception.Message

        # Clean up temporary staging file (only if created by this transaction)
        if (Test-Path -LiteralPath $tmpPath) {
            try {
                if (-not [string]::IsNullOrWhiteSpace($stageCreatedKernelId)) {
                    Remove-WibOwnedFileIfMatches `
                        -Path $tmpPath `
                        -ExpectedIdentity $stageCreatedKernelId
                }
                else {
                    Write-Warning "Unowned staging artifact preserved for manual review: '$tmpPath'."
                }
            }
            catch {
                Write-Warning "Staging cleanup failed; artifact preserved: '$tmpPath'. $($_.Exception.Message)"
            }
        }

        if ($transactionCommitted) {
            Write-Warning "Post-commit warning on '$Path': $writeErr"
            return
        }

        if ($existedBefore) {
            # Pre-commit failure: rollback is required
            $rollbackErr = $null
            try {
                $currentDestinationId = Get-WibKernelNodeIdentity -LiteralPath $Path

                $permittedRollbackIds = @($origDestKernelId)
                if ($null -ne $stageSnapshot) {
                    $permittedRollbackIds += $stageSnapshot.KernelIdentity
                }

                if ($currentDestinationId -notin $permittedRollbackIds) {
                    throw "CRITICAL ROLLBACK FAILURE: Destination identity changed unexpectedly. Backup preserved at '$bakPath'."
                }

                if (Test-Path -LiteralPath $bakPath -PathType Leaf) {
                    if ((Get-WibSha256 -Path $bakPath) -ine $origDestSha256) {
                        throw "CRITICAL ROLLBACK FAILURE: Original backup SHA-256 mismatch. Backup preserved at '$bakPath'."
                    }
                    [System.IO.File]::Copy($bakPath, $Path, $true)
                } elseif (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
                    throw "CRITICAL ROLLBACK FAILURE: Target file is missing and original backup is missing at '$bakPath'."
                }
                Restore-WibFileDaclSnapshot -LiteralPath $Path -Snapshot $origDestAclSnapshot

                if ((Get-WibSha256 -Path $Path) -ine $origDestSha256) {
                    throw "CRITICAL ROLLBACK FAILURE: Restored JSON content does not match the original."
                }

                if ((Get-WibAclFingerprint -Path $Path) -ine $origDestAclSnapshot.Fingerprint) {
                    throw "CRITICAL ROLLBACK FAILURE: Restored JSON DACL does not match the original."
                }

                if (-not [string]::IsNullOrWhiteSpace($origDestAclSnapshot.OwnerSid)) {
                    $rollbackOwner = Get-WibPathOwnerSid -Path $Path
                    if ($rollbackOwner -ine $origDestAclSnapshot.OwnerSid) {
                        throw "CRITICAL ROLLBACK FAILURE: Restored JSON owner '$rollbackOwner' does not match original '$($origDestAclSnapshot.OwnerSid)'."
                    }
                }
            }
            catch {
                $rollbackErr = $_.Exception.Message
            }

            if ($null -ne $rollbackErr) {
                throw "CRITICAL ROLLBACK FAILURE on '$Path' (backup preserved at '$bakPath'): primary error: [$writeErr]; rollback error: [$rollbackErr]"
            }

            if (Test-Path -LiteralPath $bakPath -PathType Leaf) {
                $backupCleanup = Complete-WibBackupCleanup `
                    -Path $bakPath `
                    -ExpectedIdentity $backupKernelId `
                    -ExpectedSha256 $origDestSha256 `
                    -Sensitive:$isSensitiveLedger `
                    -Outcome RolledBack
                $script:WibLastFileTransactionStatus = $backupCleanup
                $global:WibLastFileTransactionStatus = $backupCleanup
            }

            throw "Failed durable JSON write to '$Path' (prior file and permissions restored and verified): $writeErr"
        }
        else {
            # No pre-existing target was present.
            # If File.Move failed, the target may belong to another process.
            # Preserve it unless this transaction successfully moved its own
            # staging file and the current object still matches the expected ID/hash.
            if ($newTargetMoveSucceeded -and $null -ne $stageSnapshot) {
                try {
                    Remove-WibOwnedFileIfMatches `
                        -Path $Path `
                        -ExpectedIdentity $stageSnapshot.KernelIdentity `
                        -ExpectedSha256 $stageSnapshot.Sha256
                }
                catch {
                    throw "CRITICAL OWNERSHIP FAILURE after durable JSON write error '$Path': original error: [$writeErr]; cleanup error: [$($_.Exception.Message)]. The unexpected destination was preserved."
                }
            }

            throw "Failed durable JSON write to '$Path': $writeErr"
        }
    }
}

function New-WibResult {
    param([string]$Module, [string]$Item, [string]$Status, [string]$Detail = '')
    @{ Module = $Module; Item = $Item; Status = $Status; Detail = $Detail }
}

function Format-WibBytes {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N1} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N0} KB' -f ($Bytes / 1KB)) }
    return "$Bytes B"
}

function New-WibPlanItem {
    param(
        [string]$Module,
        [string]$Action,
        [string]$Target,
        [string]$Reason = '',
        [bool]$Reversible = $true,
        [ValidateSet('journal', 'reinstallable', 'permanent')][string]$Reversibility,
        [long]$EstimatedBytes = 0,
        [string]$NewValue = '',
        [string]$NewKind = ''
    )
    $actualReversibility = $Reversibility
    if (-not $actualReversibility) {
        if ($Reversible) {
            $actualReversibility = 'journal'
        } else {
            $actualReversibility = 'permanent'
        }
    }
    $isReversible = ($actualReversibility -ne 'permanent')
    @{
        Module         = $Module
        Action         = $Action
        Target         = $Target
        Reason         = $Reason
        Reversible     = $isReversible
        Reversibility  = $actualReversibility
        EstimatedBytes = $EstimatedBytes
        NewValue       = $NewValue
        NewKind        = $NewKind
    }
}

# ---------------------------------------------------------------- profiles
function Import-WibProfile {
    param([Parameter(Mandatory)][string]$Path, [int]$Depth = 0)
    if ($Depth -gt 5) { throw "Profile 'extends' chain is too deep (cycle?)." }
    if (-not (Test-Path -LiteralPath $Path)) { throw "Profile not found: $Path" }

    $p = ConvertTo-WibHashtable (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
    foreach ($req in 'profile', 'version', 'modules') {
        if (-not $p.ContainsKey($req)) { throw "Profile '$Path' is missing required field '$req'." }
    }
    if (-not $p.ContainsKey('parentChain')) {
        $p['parentChain'] = @()
    }

    if ($p.ContainsKey('extends') -and $p['extends']) {
        $parentName = [string]$p['extends']
        if (-not $parentName.EndsWith('.json')) { $parentName = "$parentName.json" }
        $parentPath = Join-Path (Split-Path -Parent $Path) $parentName
        if (-not (Test-Path -LiteralPath $parentPath)) {
            $toolRoot = Split-Path -Parent $PSScriptRoot
            $fallbackPath = Join-Path (Join-Path $toolRoot 'profiles') $parentName
            if (Test-Path -LiteralPath $fallbackPath) {
                $parentPath = $fallbackPath
            }
        }
        $parent = Import-WibProfile -Path $parentPath -Depth ($Depth + 1)
        
        $parents = @($p['extends'])
        if ($parent.ContainsKey('parentChain') -and $parent['parentChain']) {
            $parents += @($parent['parentChain'])
        }
        $p['parentChain'] = $parents

        $merged = @{}
        foreach ($k in $parent['modules'].Keys) { $merged[$k] = $parent['modules'][$k] }
        foreach ($k in $p['modules'].Keys) {
            if ($merged.ContainsKey($k)) {
                $m = @{}
                foreach ($x in $merged[$k].Keys) { $m[$x] = $merged[$k][$x] }
                foreach ($x in $p['modules'][$k].Keys) { $m[$x] = $p['modules'][$k][$x] }   # child overrides; arrays replace
                $merged[$k] = $m
            } else {
                $merged[$k] = $p['modules'][$k]
            }
        }
        $p['modules'] = $merged
        if ($parent.ContainsKey('output') -or $p.ContainsKey('output')) {
            $mergedOut = @{}
            if ($parent.ContainsKey('output') -and $parent['output'] -is [System.Collections.IDictionary]) {
                foreach ($k in $parent['output'].Keys) { $mergedOut[$k] = $parent['output'][$k] }
            }
            if ($p.ContainsKey('output') -and $p['output'] -is [System.Collections.IDictionary]) {
                foreach ($k in $p['output'].Keys) { $mergedOut[$k] = $p['output'][$k] }
            }
            $p['output'] = $mergedOut
        }
        if ($parent.ContainsKey('safety') -or $p.ContainsKey('safety')) {
            $mergedSafety = @{}
            if ($parent.ContainsKey('safety') -and $parent['safety'] -is [System.Collections.IDictionary]) {
                foreach ($k in $parent['safety'].Keys) { $mergedSafety[$k] = $parent['safety'][$k] }
            }
            if ($p.ContainsKey('safety') -and $p['safety'] -is [System.Collections.IDictionary]) {
                foreach ($k in $p['safety'].Keys) { $mergedSafety[$k] = $p['safety'][$k] }
            }
            $p['safety'] = $mergedSafety
        }
    }
    return $p
}

$script:WibBuiltInProfiles = @('balanced', 'lean', 'adaptive', 'hardening')

function Test-WibProfile {
    param(
        [Parameter(Mandatory)][hashtable]$BuildProfile,
        [switch]$AcceptRisk
    )
    # 1. Root structure validation
    $allowedRootKeys = @('profile', 'version', 'extends', 'description', 'modules', 'output', 'safety', 'parentChain', 'adaptive', 'hardwareSpec')
    foreach ($rk in $BuildProfile.Keys) {
        if ($allowedRootKeys -notcontains $rk -and $rk -notlike '_*') {
            throw "Profile contains unknown root property '$rk'."
        }
    }
    $versionVal = $BuildProfile['version']
    $parsedInt = 0
    if ($versionVal -isnot [int] -and -not [int]::TryParse([string]$versionVal, [ref]$parsedInt)) {
        throw "Profile 'version' must be an integer."
    }
    if (-not ($BuildProfile['modules'] -is [System.Collections.IDictionary])) {
        throw "Profile 'modules' must be an object/hashtable."
    }

    # 2. Per-module validation
    foreach ($id in $BuildProfile['modules'].Keys) {
        if (-not $script:WibModules.Contains($id)) {
            throw "Profile references unknown module '$id'. Known: $($script:WibModules.Keys -join ', ')"
        }
        $mod = $script:WibModules[$id]
        $modSettings = $BuildProfile['modules'][$id]
        if ($null -eq $modSettings) { continue }
        if ($modSettings -isnot [System.Collections.IDictionary]) {
            throw "Settings for module '$id' must be an object/hashtable."
        }

        # Check high-risk opt-in rules
        $isEnabled = $true
        if ($modSettings.ContainsKey('enabled') -and ($modSettings['enabled'] -eq $false)) {
            $isEnabled = $false
        }
        if ($isEnabled -and $mod.ContainsKey('Risk') -and $mod.Risk -eq 'high') {
            $profName = [string]$BuildProfile['profile']
            if ($profName.ToLower() -in $script:WibBuiltInProfiles) {
                throw "Module '$id' has risk 'high' and is strictly prohibited in built-in profile '$profName'. Create a custom profile to enable high-risk modules."
            }
            if (-not $AcceptRisk) {
                $tradeoffMsg = if ($mod.ContainsKey('Tradeoff') -and $mod.Tradeoff) { $mod.Tradeoff } else { 'Removes key Windows security mitigations or protections' }
                throw "Module '$id' has risk 'high' (tradeoff: '$tradeoffMsg'). To proceed, you must explicitly pass -AcceptRisk."
            }
        }

        # Check allowed keys in module settings
        $schema = @{}
        if ($mod.ContainsKey('Schema') -and $mod.Schema) {
            $schema = $mod.Schema
        }
        # 'enabled' is always permitted for every module
        $allowedKeys = @('enabled') + @($schema.Keys)

        foreach ($sk in $modSettings.Keys) {
            if ($allowedKeys -notcontains $sk) {
                throw "Module '$id' does not accept setting '$sk'. Allowed: $($allowedKeys -join ', ')"
            }
            # Type validation
            $val = $modSettings[$sk]
            if ($null -eq $val) { continue } # null is permitted

            $expectedType = 'string'
            if ($sk -eq 'enabled') {
                $expectedType = 'bool'
            } elseif ($schema.ContainsKey($sk)) {
                $expectedType = [string]$schema[$sk]
            }

            switch ($expectedType) {
                'bool' {
                    if ($val -isnot [bool]) {
                        throw "Module '$id' setting '$sk' must be a boolean (true/false), got $($val.GetType().Name)."
                    }
                }
                'string' {
                    if ($val -isnot [string]) {
                        throw "Module '$id' setting '$sk' must be a string, got $($val.GetType().Name)."
                    }
                }
                'int' {
                    $testInt = 0
                    if ($val -isnot [int] -and -not [int]::TryParse([string]$val, [ref]$testInt)) {
                        throw "Module '$id' setting '$sk' must be an integer, got $($val.GetType().Name)."
                    }
                }
                'array' {
                    if ($val -is [string] -or $val -is [System.Collections.IDictionary] -or $val -isnot [System.Collections.IEnumerable]) {
                        throw "Module '$id' setting '$sk' must be an array/list, got $($val.GetType().Name)."
                    }
                }
                'hashtable' {
                    if ($val -isnot [System.Collections.IDictionary]) {
                        throw "Module '$id' setting '$sk' must be an object/hashtable, got $($val.GetType().Name)."
                    }
                }
            }
        }

        if ($mod.ContainsKey('Validate') -and $mod.Validate) {
            & $mod.Validate $modSettings
        }
    }

    # 3. Output section validation
    if ($BuildProfile.ContainsKey('output') -and $BuildProfile['output'] -is [System.Collections.IDictionary] -and $BuildProfile['output'].ContainsKey('compression')) {
        if (@('none','fast','max','recovery') -notcontains [string]$BuildProfile['output']['compression']) {
            throw "output.compression must be none, fast, max or recovery."
        }
    }
}

function Test-WibModuleEnabled {
    param($Cfg)
    if ($null -eq $Cfg) { return $true }
    if ($Cfg -is [System.Collections.IDictionary] -and $Cfg.ContainsKey('enabled') -and ($Cfg['enabled'] -eq $false)) {
        return $false
    }
    return $true
}

function Get-WibNeverTouchServices {
    @(
        'BFE', 'mpssvc', 'Dnscache', 'StateRepository', 'TrustedInstaller',
        'Winmgmt', 'LanmanWorkstation', 'nsi', 'Dhcp', 'WinDefend',
        'RpcSs', 'RpcEptMapper', 'DcomLaunch', 'LSM', 'SamSs', 'sppsvc',
        'PlugPlay', 'Power', 'SystemEventsBroker', 'BrokerInfrastructure',
        'EventLog', 'ProfSvc', 'UserManager', 'CryptSvc'
    )
}
$script:WibNeverTouchServices = Get-WibNeverTouchServices

function Get-WibModuleSettings {
    param([hashtable]$BuildProfile, [string]$Id)
    if ($BuildProfile['modules'].ContainsKey($Id) -and $BuildProfile['modules'][$Id]) { return $BuildProfile['modules'][$Id] }
    return @{}
}

function Get-WibEnabledModuleIds {
    param([hashtable]$BuildProfile, [string]$Image = 'install')
    $ids = @()
    foreach ($id in $BuildProfile['modules'].Keys) {
        if (-not $script:WibModules.Contains($id)) { continue }
        $s = Get-WibModuleSettings $BuildProfile $id
        if (-not (Test-WibModuleEnabled $s)) { continue }
        if ($script:WibModules[$id].Scope -notcontains $Image) { continue }
        $ids += $id
    }
    $ids | Sort-Object { $script:WibModules[$_].Order }, { $_ }
}

# ---------------------------------------------------------------- module registry
function Register-WibModule {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Description,
        [ValidateSet('low', 'medium', 'high')][string]$Risk = 'low',
        [bool]$Reversible = $true,
        [ValidateSet('journal', 'reinstallable', 'permanent')][string]$Reversibility,
        [string]$Tradeoff = '',
        [string]$HardwareHint = '',
        [hashtable]$AppliesWhen = @{},
        [ValidateSet('ignore', 'log', 'halt')][string]$OnError = 'log',
        [hashtable]$Schema = @{},
        [scriptblock]$Validate,
        [string[]]$Scope = @('install'),     # 'boot' scope = registry tweaks only
        [int]$Order = 50,
        [object[]]$Tweaks = @(),
        [scriptblock]$TweakProvider,         # param($S) -> tweaks, when tweaks depend on settings
        [scriptblock]$Plan,                  # param($Ctx,$S) -> plan items
        [scriptblock]$Apply,                 # param($Ctx,$S) -> results (file-level work, hives NOT loaded)
        [scriptblock]$Verify,                # param($Ctx,$S) -> results (hives loaded)
        [scriptblock]$Post                   # param($Ctx,$S) -> results (after hives unloaded, before commit)
    )
    $actualReversibility = $Reversibility
    if (-not $actualReversibility) {
        if ($Reversible) {
            $actualReversibility = 'journal'
        } else {
            $actualReversibility = 'permanent'
        }
    }
    $isReversible = ($actualReversibility -ne 'permanent')

    $script:WibModules[$Id] = @{
        Id            = $Id
        Description   = $Description
        Risk          = $Risk
        Reversible    = $isReversible
        Reversibility = $actualReversibility
        Tradeoff      = $Tradeoff
        HardwareHint  = $HardwareHint
        AppliesWhen   = $AppliesWhen
        OnError       = $OnError
        Schema        = $Schema
        Validate      = $Validate
        Scope         = $Scope
        Order         = $Order
        Tweaks        = $Tweaks
        TweakProvider = $TweakProvider
        Plan          = $Plan
        Apply         = $Apply
        Verify        = $Verify
        Post          = $Post
    }
}

function Get-WibModuleTweaks {
    param($Module, [hashtable]$Settings)
    if ($Module.TweakProvider) { return @(& $Module.TweakProvider $Settings) }
    return @($Module.Tweaks)
}

function Get-WibMountedImage {
    param(
        [Alias('Path')][string]$MountDir
    )
    if (-not $MountDir) { return @() }
    $want = $MountDir.TrimEnd('\')
    try {
        @(Get-WindowsImage -Mounted -ErrorAction Stop | Where-Object {
            $p = [string]$_.Path
            if ($p) { $p.TrimEnd('\') -ieq $want } else { $false }
        })
    } catch {
        return @()
    }
}

if (-not ([System.Management.Automation.PSTypeName]'WibKernelPathHelper').Type) {
    try {
        Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Text.RegularExpressions;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

public static class WibKernelPathHelper {
    private static readonly Regex KernelIdRegex =
        new Regex(@"^OK:[0-9A-Fa-f]{8}:[0-9A-Fa-f]{8}:[0-9A-Fa-f]{8}$", RegexOptions.Compiled);
    private static readonly Regex Sha256Regex =
        new Regex(@"^[0-9A-Fa-f]{64}$", RegexOptions.Compiled);

    private const uint FILE_SHARE_READ = 0x00000001;
    private const uint FILE_SHARE_WRITE = 0x00000002;
    private const uint FILE_SHARE_DELETE = 0x00000004;
    private const uint OPEN_EXISTING = 3;
    private const uint FILE_FLAG_BACKUP_SEMANTICS = 0x02000000;
    private const uint FILE_FLAG_OPEN_REPARSE_POINT = 0x00200000;
    private const uint FILE_ATTRIBUTE_REPARSE_POINT = 0x00000400;
    private const uint FILE_ATTRIBUTE_DIRECTORY = 0x00000010;
    private const uint FILE_PERSISTENT_ACLS = 0x00000008;
    private const uint DELETE = 0x00010000;
    private const uint FILE_READ_ATTRIBUTES = 0x00000080;
    private const uint FILE_READ_DATA = 0x00000001;

    [StructLayout(LayoutKind.Sequential)]
    public struct FILE_DISPOSITION_INFO {
        [MarshalAs(UnmanagedType.U1)]
        public byte DeleteFile;
    }

    private const int FileDispositionInfo = 4;

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetFileInformationByHandle(
        SafeFileHandle hFile,
        int FileInformationClass,
        ref FILE_DISPOSITION_INFO lpFileInformation,
        uint dwBufferSize);

    [StructLayout(LayoutKind.Sequential)]
    private struct BY_HANDLE_FILE_INFORMATION {
        public uint dwFileAttributes;
        public uint ftCreationTimeLow;
        public uint ftCreationTimeHigh;
        public uint ftLastAccessTimeLow;
        public uint ftLastAccessTimeHigh;
        public uint ftLastWriteTimeLow;
        public uint ftLastWriteTimeHigh;
        public uint dwVolumeSerialNumber;
        public uint nFileSizeHigh;
        public uint nFileSizeLow;
        public uint nNumberOfLinks;
        public uint nFileIndexHigh;
        public uint nFileIndexLow;
    }

    [DllImport("kernel32.dll", EntryPoint = "CreateFileW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern SafeFileHandle CreateFileW(
        string lpFileName,
        uint dwDesiredAccess,
        uint dwShareMode,
        IntPtr lpSecurityAttributes,
        uint dwCreationDisposition,
        uint dwFlagsAndAttributes,
        IntPtr hTemplateFile);

    [DllImport("kernel32.dll", EntryPoint = "GetFinalPathNameByHandleW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern uint GetFinalPathNameByHandleW(
        SafeFileHandle hFile,
        StringBuilder lpszFilePath,
        uint cchFilePath,
        uint dwFlags);

    [DllImport("kernel32.dll", EntryPoint = "GetFileInformationByHandle", SetLastError = true)]
    private static extern bool GetFileInformationByHandle(
        SafeFileHandle hFile,
        out BY_HANDLE_FILE_INFORMATION lpFileInformation);

    [DllImport("kernel32.dll", EntryPoint = "GetVolumeInformationW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool GetVolumeInformationW(
        string lpRootPathName,
        StringBuilder lpVolumeNameBuffer,
        uint nVolumeNameSize,
        out uint lpVolumeSerialNumber,
        out uint lpMaximumComponentLength,
        out uint lpFileSystemFlags,
        StringBuilder lpFileSystemNameBuffer,
        uint nFileSystemNameSize);

    [DllImport("kernel32.dll", EntryPoint = "ReplaceFileW", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool ReplaceFileW(
        string lpReplacedFileName,
        string lpReplacementFileName,
        string lpBackupFileName,
        int dwReplaceFlags,
        IntPtr lpExclude,
        IntPtr lpReserved);

    public static string GetKernelFinalPath(string path) {
        using (SafeFileHandle h = CreateFileW(
            path,
            0,
            FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
            IntPtr.Zero,
            OPEN_EXISTING,
            FILE_FLAG_BACKUP_SEMANTICS,
            IntPtr.Zero)) {
            if (h == null || h.IsInvalid) {
                return null;
            }
            StringBuilder sb = new StringBuilder(1024);
            uint len = GetFinalPathNameByHandleW(h, sb, (uint)sb.Capacity, 0);
            if (len == 0) {
                return null;
            }
            if (len >= sb.Capacity) {
                sb = new StringBuilder((int)len + 1);
                len = GetFinalPathNameByHandleW(h, sb, (uint)sb.Capacity, 0);
                if (len == 0) return null;
            }
            string resolved = sb.ToString();
            if (resolved.StartsWith(@"\\?\UNC\", StringComparison.OrdinalIgnoreCase)) {
                resolved = @"\\" + resolved.Substring(8);
            } else if (resolved.StartsWith(@"\\?\", StringComparison.OrdinalIgnoreCase)) {
                resolved = resolved.Substring(4);
            }
            return resolved;
        }
    }

    public static string GetKernelNodeIdentity(string path) {
        using (SafeFileHandle h = CreateFileW(
            path,
            0,
            FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
            IntPtr.Zero,
            OPEN_EXISTING,
            FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT,
            IntPtr.Zero)) {
            if (h == null || h.IsInvalid) {
                return null;
            }
            BY_HANDLE_FILE_INFORMATION info;
            if (!GetFileInformationByHandle(h, out info)) {
                return null;
            }
            bool isReparse = (info.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0;
            string prefix = isReparse ? "REPARSE" : "OK";
            return string.Format("{0}:{1:X8}:{2:X8}:{3:X8}", prefix, info.dwVolumeSerialNumber, info.nFileIndexHigh, info.nFileIndexLow);
        }
    }

    public static string GetKernelNodeIdentityFromHandle(SafeFileHandle h) {
        if (h == null || h.IsInvalid || h.IsClosed) {
            return null;
        }

        BY_HANDLE_FILE_INFORMATION info;
        if (!GetFileInformationByHandle(h, out info)) {
            return null;
        }

        bool isReparse = (info.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0;
        string prefix = isReparse ? "REPARSE" : "OK";

        return string.Format(
            "{0}:{1:X8}:{2:X8}:{3:X8}",
            prefix,
            info.dwVolumeSerialNumber,
            info.nFileIndexHigh,
            info.nFileIndexLow
        );
    }

    public static bool DeleteFileByHandleIfIdentityMatches(string path, string expectedKernelId, string expectedSha256, out string error) {
        error = null;
        if (string.IsNullOrEmpty(path)) {
            error = "Path is null or empty.";
            return false;
        }

        if (string.IsNullOrWhiteSpace(expectedKernelId) || !KernelIdRegex.IsMatch(expectedKernelId)) {
            error = "Expected kernel identity is mandatory and must match format 'OK:XXXXXXXX:XXXXXXXX:XXXXXXXX'.";
            return false;
        }

        if (!string.IsNullOrEmpty(expectedSha256) && !Sha256Regex.IsMatch(expectedSha256)) {
            error = "Expected SHA-256 is malformed; must be exactly 64 hexadecimal characters.";
            return false;
        }

        uint access = DELETE | FILE_READ_ATTRIBUTES;
        if (!string.IsNullOrEmpty(expectedSha256)) {
            access |= FILE_READ_DATA;
        }

        using (SafeFileHandle h = CreateFileW(
            path,
            access,
            FILE_SHARE_READ,
            IntPtr.Zero,
            OPEN_EXISTING,
            FILE_FLAG_OPEN_REPARSE_POINT,
            IntPtr.Zero)) {

            if (h == null || h.IsInvalid) {
                int err = Marshal.GetLastWin32Error();
                error = "CreateFileW failed with Win32 error " + err;
                return false;
            }

            BY_HANDLE_FILE_INFORMATION info;
            if (!GetFileInformationByHandle(h, out info)) {
                int err = Marshal.GetLastWin32Error();
                error = "GetFileInformationByHandle failed with Win32 error " + err;
                return false;
            }

            if ((info.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0) {
                error = "Target is a reparse point; refusing handle deletion.";
                return false;
            }

            if ((info.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0) {
                error = "Target is a directory; refusing handle file deletion.";
                return false;
            }

            string actualId = string.Format("OK:{0:X8}:{1:X8}:{2:X8}",
                info.dwVolumeSerialNumber, info.nFileIndexHigh, info.nFileIndexLow);

            if (!string.Equals(actualId, expectedKernelId, StringComparison.OrdinalIgnoreCase)) {
                error = string.Format("Kernel identity mismatch: expected '{0}', got '{1}'.", expectedKernelId, actualId);
                return false;
            }

            if (!string.IsNullOrEmpty(expectedSha256)) {
                using (System.IO.FileStream fs = new System.IO.FileStream(h, System.IO.FileAccess.Read)) {
                    using (var sha = System.Security.Cryptography.SHA256.Create()) {
                        byte[] hashBytes = sha.ComputeHash(fs);
                        StringBuilder sb = new StringBuilder(64);
                        for (int i = 0; i < hashBytes.Length; i++) {
                            sb.Append(hashBytes[i].ToString("X2"));
                        }
                        string actualHash = sb.ToString();
                        if (!string.Equals(actualHash, expectedSha256, StringComparison.OrdinalIgnoreCase)) {
                            error = string.Format("Hash mismatch: expected '{0}', got '{1}'.", expectedSha256, actualHash);
                            return false;
                        }
                    }
                    FILE_DISPOSITION_INFO disp = new FILE_DISPOSITION_INFO();
                    disp.DeleteFile = 1;
                    if (!SetFileInformationByHandle(h, FileDispositionInfo, ref disp, (uint)Marshal.SizeOf(typeof(FILE_DISPOSITION_INFO)))) {
                        int err = Marshal.GetLastWin32Error();
                        error = "SetFileInformationByHandle failed with Win32 error " + err;
                        return false;
                    }
                }
                return true;
            } else {
                FILE_DISPOSITION_INFO disp = new FILE_DISPOSITION_INFO();
                disp.DeleteFile = 1;
                if (!SetFileInformationByHandle(h, FileDispositionInfo, ref disp, (uint)Marshal.SizeOf(typeof(FILE_DISPOSITION_INFO)))) {
                    int err = Marshal.GetLastWin32Error();
                    error = "SetFileInformationByHandle failed with Win32 error " + err;
                    return false;
                }
                return true;
            }
        }
    }

    public static bool ReplaceFileIfDestinationMatches(
        string sourcePath,
        string destinationPath,
        string backupPath,
        string expectedDestKernelId,
        string expectedDestSha256,
        out string error)
    {
        error = null;
        if (string.IsNullOrEmpty(sourcePath) || string.IsNullOrEmpty(destinationPath)) {
            error = "Source or destination path is null or empty.";
            return false;
        }

        if (string.IsNullOrWhiteSpace(expectedDestKernelId) || !KernelIdRegex.IsMatch(expectedDestKernelId)) {
            error = "Expected destination kernel identity is mandatory and must match format 'OK:XXXXXXXX:XXXXXXXX:XXXXXXXX'.";
            return false;
        }

        if (!string.IsNullOrEmpty(expectedDestSha256) && !Sha256Regex.IsMatch(expectedDestSha256)) {
            error = "Expected destination SHA-256 is malformed; must be exactly 64 hexadecimal characters.";
            return false;
        }

        // Open destination handle with restrictive sharing to verify its identity and hash
        using (SafeFileHandle hDest = CreateFileW(
            destinationPath,
            FILE_READ_DATA | FILE_READ_ATTRIBUTES,
            FILE_SHARE_READ,
            IntPtr.Zero,
            OPEN_EXISTING,
            FILE_FLAG_OPEN_REPARSE_POINT,
            IntPtr.Zero))
        {
            if (hDest == null || hDest.IsInvalid) {
                int err = Marshal.GetLastWin32Error();
                error = "CreateFileW on destination failed with Win32 error " + err;
                return false;
            }

            BY_HANDLE_FILE_INFORMATION info;
            if (!GetFileInformationByHandle(hDest, out info)) {
                int err = Marshal.GetLastWin32Error();
                error = "GetFileInformationByHandle on destination failed with Win32 error " + err;
                return false;
            }

            if ((info.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0) {
                error = "Destination is a reparse point; refusing replacement.";
                return false;
            }

            if ((info.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0) {
                error = "Destination is a directory; refusing file replacement.";
                return false;
            }

            string actualId = string.Format("OK:{0:X8}:{1:X8}:{2:X8}",
                info.dwVolumeSerialNumber, info.nFileIndexHigh, info.nFileIndexLow);

            if (!string.Equals(actualId, expectedDestKernelId, StringComparison.OrdinalIgnoreCase)) {
                error = string.Format("Destination identity mismatch: expected '{0}', got '{1}'.", expectedDestKernelId, actualId);
                return false;
            }

            if (!string.IsNullOrEmpty(expectedDestSha256)) {
                using (System.IO.FileStream fs = new System.IO.FileStream(hDest, System.IO.FileAccess.Read)) {
                    using (var sha = System.Security.Cryptography.SHA256.Create()) {
                        byte[] hashBytes = sha.ComputeHash(fs);
                        StringBuilder sb = new StringBuilder(64);
                        for (int i = 0; i < hashBytes.Length; i++) {
                            sb.Append(hashBytes[i].ToString("X2"));
                        }
                        string actualHash = sb.ToString();
                        if (!string.Equals(actualHash, expectedDestSha256, StringComparison.OrdinalIgnoreCase)) {
                            error = string.Format("Destination SHA-256 mismatch: expected '{0}', got '{1}'.", expectedDestSha256, actualHash);
                            return false;
                        }
                    }
                }
            }
        }

        // Invoke Win32 ReplaceFileW
        if (!ReplaceFileW(destinationPath, sourcePath, string.IsNullOrEmpty(backupPath) ? null : backupPath, 0, IntPtr.Zero, IntPtr.Zero)) {
            int win32Err = Marshal.GetLastWin32Error();
            error = "ReplaceFileW failed with Win32 error " + win32Err;
            return false;
        }

        return true;
    }

    public static bool SupportsPersistentAcls(string rootPath) {
        uint serial, maxComp, fsFlags;
        if (!GetVolumeInformationW(rootPath, null, 0, out serial, out maxComp, out fsFlags, null, 0)) {
            return false;
        }
        return (fsFlags & FILE_PERSISTENT_ACLS) != 0;
    }
}
'@ -ErrorAction SilentlyContinue
    } catch { Write-Verbose $_.Exception.Message }
}

function Test-WibVolumePersistentAclSupport {
    <#
    .SYNOPSIS
        Verifies via Win32 GetVolumeInformationW that the target path resides on a volume
        supporting persistent NTFS/ReFS access-control lists (FILE_PERSISTENT_ACLS = 0x00000008).
        Returns $false on FAT32/exFAT or unresolvable volumes so callers can fail closed before
        materializing sensitive files on volumes incapable of enforcing DACLs (WIB-008).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    try {
        $full = [System.IO.Path]::GetFullPath($Path)
        $root = [System.IO.Path]::GetPathRoot($full)
        if (-not $root) { return $false }
        if (-not $root.EndsWith('\')) { $root = "$root\" }
        if (([System.Management.Automation.PSTypeName]'WibKernelPathHelper').Type) {
            return [WibKernelPathHelper]::SupportsPersistentAcls($root)
        }
        $driveLetter = $root.TrimEnd('\', ':')
        if ($driveLetter.Length -eq 1) {
            $driveInfo = New-Object System.IO.DriveInfo($driveLetter)
            return ($driveInfo.DriveFormat -in @('NTFS', 'ReFS'))
        }
        return $false
    } catch {
        return $false
    }
}

function Get-WibKernelNodeIdentity {
    <#
    .SYNOPSIS
        Returns the 64-bit NTFS File ID (OK:VolSerial:IdxHigh:IdxLow or REPARSE:VolSerial:IdxHigh:IdxLow)
        for a filesystem node via CreateFileW(FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT)
        + GetFileInformationByHandle.
        Fails closed (throws a terminating error) if WibKernelPathHelper is unavailable, disabled, or
        returns null/empty, refusing to silently downgrade to unverified path operations (WIB-014).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$LiteralPath)
    if ($script:WibDisableKernelIdentityHelper -or -not ([System.Management.Automation.PSTypeName]'WibKernelPathHelper').Type) {
        throw "SECURITY ERROR: Kernel 64-bit File ID helper (WibKernelPathHelper) is unavailable or failed to initialize. Refusing to downgrade destructive or confined filesystem operations to unverified mode."
    }
    $nodeId = [WibKernelPathHelper]::GetKernelNodeIdentity($LiteralPath)
    if ([string]::IsNullOrWhiteSpace($nodeId)) {
        throw "SECURITY ERROR: Kernel 64-bit File ID resolution returned null/empty identity for '$LiteralPath'."
    }
    return $nodeId
}

function Test-WibUnattendPasswordHash {
    <#
    .SYNOPSIS
        Validates that a supplied -PasswordHash conforms strictly to the Microsoft Windows System Image Manager
        (WSIM) / Microsoft-Windows-Shell-Setup unattend specification for <PlainText>false</PlainText> credentials.
    .DESCRIPTION
        In Windows Setup (Microsoft-Windows-Shell-Setup), when <PlainText>false</PlainText> is set on a
        LocalAccount or AutoLogon <Password>, <Value> must be the canonical Base64 encoding of the UTF-16LE
        (Encoding.Unicode) byte sequence of '<password>Password' (or '<password>AdministratorPassword' for the
        built-in Administrator account). This function validates Base64 canonical encoding, UTF-16LE byte alignment,
        absence of NUL (U+0000) code units, non-empty password prefix, and exact UTF-16LE suffix bytes directly in a
        scrubbed byte[] array without allocating a decoded plaintext System.String on the managed heap (WIB-010/WIB-015).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$PasswordHash,
        [switch]$AllowAdministratorSuffix
    )
    $trimmed = if ($null -ne $PasswordHash) { $PasswordHash.Trim() } else { '' }
    if ([string]::IsNullOrEmpty($trimmed)) {
        throw "Invalid -PasswordHash format: value cannot be empty or whitespace."
    }
    if (($trimmed.Length % 4) -ne 0 -or $trimmed -notmatch '^[A-Za-z0-9+/]+={0,2}$') {
        throw "Invalid -PasswordHash format: value is not a valid canonical Base64 string."
    }
    $decodedBytes = $null
    try {
        try {
            $decodedBytes = [Convert]::FromBase64String($trimmed)
        } catch {
            throw "Invalid -PasswordHash format: Base64 decoding failed ($($_.Exception.Message))."
        }
        if ($null -eq $decodedBytes -or $decodedBytes.Length -eq 0) {
            throw "Invalid -PasswordHash format: decoded payload is empty."
        }
        if ([Convert]::ToBase64String($decodedBytes) -cne $trimmed) {
            throw "Invalid -PasswordHash format: non-canonical Base64 padding or encoding."
        }
        if (($decodedBytes.Length % 2) -ne 0) {
            throw "Invalid -PasswordHash format: decoded byte length ($($decodedBytes.Length)) is odd; Windows Setup requires UTF-16LE (Encoding.Unicode) byte encoding."
        }
        for ($i = 0; $i -lt $decodedBytes.Length; $i += 2) {
            if ($decodedBytes[$i] -eq 0 -and $decodedBytes[$i + 1] -eq 0) {
                throw "Invalid -PasswordHash format: decoded UTF-16LE payload contains embedded NUL (U+0000) code units."
            }
        }

        $stdSuffixBytes = [System.Text.Encoding]::Unicode.GetBytes('Password') # 16 bytes
        $adminSuffixBytes = [System.Text.Encoding]::Unicode.GetBytes('AdministratorPassword') # 42 bytes

        $matchesStd = $false
        if ($decodedBytes.Length -ge ($stdSuffixBytes.Length + 2)) {
            $matchesStd = $true
            $offset = $decodedBytes.Length - $stdSuffixBytes.Length
            for ($j = 0; $j -lt $stdSuffixBytes.Length; $j++) {
                if ($decodedBytes[$offset + $j] -ne $stdSuffixBytes[$j]) {
                    $matchesStd = $false
                    break
                }
            }
        } elseif ($decodedBytes.Length -eq $stdSuffixBytes.Length) {
            throw "Invalid -PasswordHash format: decoded UTF-16LE payload contains only the 'Password' suffix with an empty password prefix."
        }

        $matchesAdmin = $false
        if ($AllowAdministratorSuffix -and $decodedBytes.Length -ge ($adminSuffixBytes.Length + 2)) {
            $matchesAdmin = $true
            $offsetA = $decodedBytes.Length - $adminSuffixBytes.Length
            for ($j = 0; $j -lt $adminSuffixBytes.Length; $j++) {
                if ($decodedBytes[$offsetA + $j] -ne $adminSuffixBytes[$j]) {
                    $matchesAdmin = $false
                    break
                }
            }
        }

        if (-not $matchesStd -and -not $matchesAdmin) {
            throw "Invalid -PasswordHash format: decoded payload must be UTF-16LE (Encoding.Unicode) ending with the required Microsoft WSIM 'Password' suffix (minimum 18 UTF-16LE bytes)."
        }
        return $trimmed
    } finally {
        if ($null -ne $decodedBytes -and $decodedBytes.Length -gt 0) {
            [Array]::Clear($decodedBytes, 0, $decodedBytes.Length)
        }
    }
}

function Assert-WibSensitiveAclIntegrity {
    <#
    .SYNOPSIS
        Verifies that a sensitive file or directory DACL strictly matches the intended
        access control policy: inheritance protected, no unauthorized principals, and FullControl
        granted only to CurrentUser, BUILTIN\Administrators, and NT AUTHORITY\SYSTEM (WIB-024, WIB-030, WIB-035).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [System.Security.AccessControl.FileSystemSecurity]$Acl,

        [switch]$IsDirectory
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "ACL verification failed: path does not exist: '$Path'."
    }

    $sections = (
        [System.Security.AccessControl.AccessControlSections]::Access -bor
        [System.Security.AccessControl.AccessControlSections]::Owner
    )

    if ($IsDirectory) {
        $actualAcl = (New-Object System.IO.DirectoryInfo($Path)).GetAccessControl($sections)
    }
    else {
        $actualAcl = (New-Object System.IO.FileInfo($Path)).GetAccessControl($sections)
    }

    # Treat the on-disk descriptor as authoritative for all subsequent checks (WIB-035).
    $Acl = $actualAcl

    if (-not $Acl.AreAccessRulesProtected) {
        throw "ACL verification failed for '$Path': inheritance is not protected."
    }

    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $currentSid = $identity.User

    $adminSid = New-Object System.Security.Principal.SecurityIdentifier(
        [System.Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid,
        $null
    )

    $systemSid = New-Object System.Security.Principal.SecurityIdentifier(
        [System.Security.Principal.WellKnownSidType]::LocalSystemSid,
        $null
    )

    # Read owner directly from authoritative on-disk path or owner provider.
    $ownerSid = $null
    try {
        $ownerSid = Get-WibPathOwnerSid -Path $Path -IsDirectory:$IsDirectory
    } catch { }

    if ([string]::IsNullOrWhiteSpace($ownerSid)) {
        try {
            $ownerFromAcl = $Acl.GetOwner([System.Security.Principal.SecurityIdentifier])
            if ($null -ne $ownerFromAcl) {
                $ownerSid = $ownerFromAcl.Value
            }
        } catch { }
    }

    if ([string]::IsNullOrWhiteSpace($ownerSid)) {
        throw "ACL verification failed for '$Path': unable to read owner."
    }

    $allowedOwners = @(
        $currentSid.Value,
        $adminSid.Value,
        $systemSid.Value
    )

    if ($ownerSid -notin $allowedOwners) {
        throw "ACL verification failed for '$Path': unapproved owner '$ownerSid'."
    }

    # Build the exact expected principal set.
    $expectedSids = New-Object System.Collections.Generic.HashSet[string]
    [void]$expectedSids.Add($currentSid.Value)
    [void]$expectedSids.Add($adminSid.Value)
    [void]$expectedSids.Add($systemSid.Value)

    $fullControl = [long][System.Security.AccessControl.FileSystemRights]::FullControl

    $expectedInheritance = [System.Security.AccessControl.InheritanceFlags]::None
    if ($IsDirectory) {
        $expectedInheritance = (
            [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor
            [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
        )
    }

    $expectedPropagation = [System.Security.AccessControl.PropagationFlags]::None

    $rules = @(
        $Acl.GetAccessRules(
            $true,
            $false,
            [System.Security.Principal.SecurityIdentifier]
        )
    )

    $seen = New-Object System.Collections.Generic.HashSet[string]

    foreach ($rule in $rules) {
        $sid = $rule.IdentityReference.Value

        if (-not $expectedSids.Contains($sid)) {
            throw "ACL verification failed for '$Path': unexpected or unauthorized principal '$sid'."
        }

        if ($rule.AccessControlType -ne
            [System.Security.AccessControl.AccessControlType]::Allow) {
            throw "ACL verification failed for '$Path': deny or non-Allow ACE found for '$sid'."
        }

        if ([long]$rule.FileSystemRights -ne $fullControl) {
            throw "ACL verification failed for '$Path': rights for '$sid' are '$($rule.FileSystemRights)', not exactly FullControl."
        }

        if ($rule.IsInherited) {
            throw "ACL verification failed for '$Path': inherited ACE found for '$sid'."
        }

        if ([int]$rule.InheritanceFlags -ne [int]$expectedInheritance) {
            throw "ACL verification failed for '$Path': incorrect inheritance flags for '$sid'."
        }

        if ([int]$rule.PropagationFlags -ne [int]$expectedPropagation) {
            throw "ACL verification failed for '$Path': incorrect propagation flags for '$sid'."
        }

        if (-not $seen.Add($sid)) {
            throw "ACL verification failed for '$Path': duplicate ACE found for '$sid'."
        }
    }

    if ($rules.Count -ne $expectedSids.Count) {
        throw "ACL verification failed for '$Path': expected exactly $($expectedSids.Count) explicit ACEs; found $($rules.Count)."
    }

    foreach ($sid in $expectedSids) {
        if (-not $seen.Contains($sid)) {
            throw "ACL verification failed for '$Path': required principal '$sid' is missing."
        }
    }

    return $true
}

function Protect-WibSensitiveFileAcl {
    <#
    .SYNOPSIS
        Enforces strict NTFS ACL permissions on a sensitive file (CurrentUser, Administrators, SYSTEM only).
        Disables inheritance, strips inherited or broad read rules (e.g. BUILTIN\Users, Everyone),
        and verifies FILE_PERSISTENT_ACLS volume capability, approved owner, and exact read-back DACL rules (WIB-008/WIB-024/WIB-030).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-WibVolumePersistentAclSupport -Path $Path)) {
        throw "Cannot apply sensitive ACL protection to '$Path': target volume does not support persistent ACLs (FILE_PERSISTENT_ACLS). Use an NTFS-formatted volume."
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Cannot apply sensitive ACL protection; file not found: $Path"
    }
    $fileInfo = New-Object System.IO.FileInfo($Path)
    $sections = [System.Security.AccessControl.AccessControlSections]::Access -bor [System.Security.AccessControl.AccessControlSections]::Owner
    $acl = $fileInfo.GetAccessControl($sections)

    $currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $currentSid = $currentIdentity.User
    $adminSid = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid, $null)
    $systemSid = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::LocalSystemSid, $null)

    $ownerSid = $acl.GetOwner([System.Security.Principal.SecurityIdentifier])
    $approvedOwnerSids = @($currentSid.Value, $adminSid.Value, $systemSid.Value)

    if ($null -eq $ownerSid -or $ownerSid.Value -notin $approvedOwnerSids) {
        try {
            $acl.SetOwner($currentSid)
        } catch {
            throw "SECURITY ERROR: Cannot establish an approved owner for '$Path': $($_.Exception.Message)"
        }
    }

    $acl.SetAccessRuleProtection($true, $false)
    foreach ($existingRule in @($acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier]))) {
        [void]$acl.RemoveAccessRuleSpecific($existingRule)
    }

    $ruleUser = New-Object System.Security.AccessControl.FileSystemAccessRule($currentSid, 'FullControl', 'Allow')
    $ruleAdmin = New-Object System.Security.AccessControl.FileSystemAccessRule($adminSid, 'FullControl', 'Allow')
    $ruleSys = New-Object System.Security.AccessControl.FileSystemAccessRule($systemSid, 'FullControl', 'Allow')

    $acl.AddAccessRule($ruleUser)
    $acl.AddAccessRule($ruleAdmin)
    $acl.AddAccessRule($ruleSys)
    $fileInfo.SetAccessControl($acl)

    $verifyInfo = New-Object System.IO.FileInfo($Path)
    $verifyAcl = $verifyInfo.GetAccessControl([System.Security.AccessControl.AccessControlSections]::Access)
    [void](Assert-WibSensitiveAclIntegrity -Path $Path -Acl $verifyAcl)
    return $true
}

function Protect-WibSensitiveDirectoryAcl {
    <#
    .SYNOPSIS
        Enforces strict NTFS ACL permissions on a sensitive directory (CurrentUser, Administrators, SYSTEM only).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-WibVolumePersistentAclSupport -Path $Path)) {
        throw "Cannot apply sensitive directory ACL protection to '$Path': target volume does not support persistent ACLs (FILE_PERSISTENT_ACLS). Use an NTFS-formatted volume."
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Cannot apply sensitive directory ACL protection; directory not found: $Path"
    }
    $dirInfo = New-Object System.IO.DirectoryInfo($Path)
    $sections = [System.Security.AccessControl.AccessControlSections]::Access -bor [System.Security.AccessControl.AccessControlSections]::Owner
    $acl = $dirInfo.GetAccessControl($sections)

    $currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $currentSid = $currentIdentity.User
    $adminSid = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid, $null)
    $systemSid = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::LocalSystemSid, $null)

    $ownerSid = $acl.GetOwner([System.Security.Principal.SecurityIdentifier])
    $approvedOwnerSids = @($currentSid.Value, $adminSid.Value, $systemSid.Value)

    if ($null -eq $ownerSid -or $ownerSid.Value -notin $approvedOwnerSids) {
        try {
            $acl.SetOwner($currentSid)
        } catch {
            throw "SECURITY ERROR: Cannot establish an approved owner for '$Path': $($_.Exception.Message)"
        }
    }

    $acl.SetAccessRuleProtection($true, $false)
    foreach ($existingRule in @($acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier]))) {
        [void]$acl.RemoveAccessRuleSpecific($existingRule)
    }

    $inheritFlags = [System.Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit'
    $propFlags = [System.Security.AccessControl.PropagationFlags]::None

    $ruleUser = New-Object System.Security.AccessControl.FileSystemAccessRule($currentSid, 'FullControl', $inheritFlags, $propFlags, 'Allow')
    $ruleAdmin = New-Object System.Security.AccessControl.FileSystemAccessRule($adminSid, 'FullControl', $inheritFlags, $propFlags, 'Allow')
    $ruleSys = New-Object System.Security.AccessControl.FileSystemAccessRule($systemSid, 'FullControl', $inheritFlags, $propFlags, 'Allow')

    $acl.AddAccessRule($ruleUser)
    $acl.AddAccessRule($ruleAdmin)
    $acl.AddAccessRule($ruleSys)
    $dirInfo.SetAccessControl($acl)

    $verifyDir = New-Object System.IO.DirectoryInfo($Path)
    $verifyAcl = $verifyDir.GetAccessControl([System.Security.AccessControl.AccessControlSections]::Access)
    [void](Assert-WibSensitiveAclIntegrity -Path $Path -Acl $verifyAcl -IsDirectory)
    return $true
}

function Assert-WibSafeSensitiveOutputPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [switch]$AllowMissingLeaf,
        [switch]$CreateMissingParent,
        [switch]$ProtectCreatedDirectories
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw 'SECURITY ERROR: Output path cannot be empty.'
    }

    $rawPath = $Path.Trim()

    # Reject UNC paths and Win32 device namespace paths.
    if ($rawPath -match '^[\\/]{2}') {
        throw "SECURITY ERROR: UNC/device paths are prohibited: '$rawPath'."
    }

    # A volume-qualified, local Windows path is required.
    $fullPath = [System.IO.Path]::GetFullPath($rawPath)
    $root = [System.IO.Path]::GetPathRoot($fullPath)

    if ($root -notmatch '^[A-Za-z]:\\$') {
        throw "SECURITY ERROR: Unsupported or non-local output path: '$fullPath'."
    }

    # Reject alternate data streams and embedded colons.
    $afterDrive = $fullPath.Substring(2)
    if ($afterDrive.IndexOf(':') -ge 0) {
        throw "SECURITY ERROR: Alternate data streams are prohibited: '$fullPath'."
    }

    # Never use a volume root as a file output path.
    if ($fullPath.TrimEnd('\', '/') -ieq $root.TrimEnd('\', '/')) {
        throw "SECURITY ERROR: A volume root cannot be an output file: '$fullPath'."
    }

    $leaf = [System.IO.Path]::GetFileName($fullPath)

    if ([string]::IsNullOrWhiteSpace($leaf) -or
        $leaf -in @('.', '..') -or
        $leaf -match '[. ]$' -or
        $leaf -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\..*)?$') {
        throw "SECURITY ERROR: Invalid or ambiguous output filename: '$leaf'."
    }

    $relative = $fullPath.Substring($root.Length)
    $parts = @(
        $relative.Split(
            [char[]]@('\', '/'),
            [System.StringSplitOptions]::RemoveEmptyEntries
        )
    )

    if ($parts.Count -eq 0) {
        throw "SECURITY ERROR: Output path has no filename: '$fullPath'."
    }

    $parentCount = $parts.Count - 1
    $current = $root
    $chain = New-Object System.Collections.Generic.List[object]

    for ($i = 0; $i -lt $parentCount; $i++) {
        $part = $parts[$i]
        if ($part -in @('.', '..') -or
            $part -match '[. ]$' -or
            $part -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\..*)?$') {
            throw "SECURITY ERROR: Reserved DOS device name or invalid ancestor component: '$part'."
        }
        $next = Join-Path $current $part
        $item = $null
        $createdComponent = $false

        try {
            $item = Get-Item -LiteralPath $next -Force -ErrorAction Stop
        }
        catch {
            $isMissing = $_.FullyQualifiedErrorId -match '(?i)(PathNotFound|ItemNotFound)'

            if (-not $isMissing) {
                throw "SECURITY ERROR: Cannot inspect path component '$next': $($_.Exception.Message)"
            }

            if (-not $CreateMissingParent) {
                throw "SECURITY ERROR: Parent directory does not exist: '$next'."
            }

            # Recheck all previously inspected ancestors before creating
            # the next directory component.
            foreach ($entry in $chain) {
                $nowId = Get-WibKernelNodeIdentity -LiteralPath $entry.Path

                if ($nowId -cne $entry.Identity -or
                    $nowId -like 'REPARSE:*') {
                    throw "SECURITY ERROR: Parent chain changed before creating '$next'."
                }
            }

            [System.IO.Directory]::CreateDirectory($next) | Out-Null
            $createdComponent = $true

            $item = Get-Item -LiteralPath $next -Force -ErrorAction Stop
        }

        if (-not $item.PSIsContainer) {
            throw "SECURITY ERROR: Path component is not a directory: '$next'."
        }

        if (($item.Attributes -band
            [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "SECURITY ERROR: Reparse point or junction detected in ancestor path: '$next'."
        }

        $identity = Get-WibKernelNodeIdentity -LiteralPath $next

        if ([string]::IsNullOrWhiteSpace($identity) -or
            $identity -like 'REPARSE:*') {
            throw "SECURITY ERROR: Could not establish safe identity for '$next'."
        }

        if ($createdComponent -and $ProtectCreatedDirectories) {
            if (-not (Protect-WibSensitiveDirectoryAcl -Path $next)) {
                throw "SECURITY ERROR: Failed to protect newly created directory '$next'."
            }

            $verifiedId = Get-WibKernelNodeIdentity -LiteralPath $next

            if ($verifiedId -cne $identity -or $verifiedId -like 'REPARSE:*') {
                throw "SECURITY ERROR: Directory identity changed during ACL protection: '$next'."
            }
        }

        $chain.Add([pscustomobject]@{
            Path     = $next
            Identity = $identity
        })

        $current = $next
    }

    $leafItem = $null

    try {
        $leafItem = Get-Item -LiteralPath $fullPath -Force -ErrorAction Stop
    }
    catch {
        $isMissing = $_.FullyQualifiedErrorId -match '(?i)(PathNotFound|ItemNotFound)'

        if (-not $isMissing) {
            throw "SECURITY ERROR: Cannot inspect destination '$fullPath': $($_.Exception.Message)"
        }

        if (-not $AllowMissingLeaf) {
            throw "SECURITY ERROR: Destination does not exist: '$fullPath'."
        }
    }

    $leafExists = ($null -ne $leafItem)
    $leafIdentity = $null

    if ($leafExists) {
        if ($leafItem.PSIsContainer) {
            throw "SECURITY ERROR: Destination is a directory, not a file: '$fullPath'."
        }

        if (($leafItem.Attributes -band
            [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "SECURITY ERROR: Destination is a reparse point or junction: '$fullPath'."
        }

        $leafIdentity = Get-WibKernelNodeIdentity -LiteralPath $fullPath

        if ([string]::IsNullOrWhiteSpace($leafIdentity) -or
            $leafIdentity -like 'REPARSE:*') {
            throw "SECURITY ERROR: Could not establish safe destination identity for '$fullPath'."
        }
    }

    return [pscustomobject]@{
        Path         = $fullPath
        LeafExists   = $leafExists
        LeafIdentity = $leafIdentity
        Chain        = @($chain.ToArray())
    }
}

function Assert-WibSensitivePathSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSObject]$Snapshot
    )

    $current = Assert-WibSafeSensitiveOutputPath `
        -Path $Snapshot.Path `
        -AllowMissingLeaf

    if ($current.Chain.Count -ne $Snapshot.Chain.Count) {
        throw "SECURITY ERROR: Path-chain depth changed for '$($Snapshot.Path)'."
    }

    for ($i = 0; $i -lt $Snapshot.Chain.Count; $i++) {
        if ($current.Chain[$i].Path -ine $Snapshot.Chain[$i].Path -or
            $current.Chain[$i].Identity -cne $Snapshot.Chain[$i].Identity) {
            throw "SECURITY ERROR: Ancestor identity changed for '$($Snapshot.Path)'."
        }
    }

    if ($current.LeafExists -ne $Snapshot.LeafExists) {
        throw "SECURITY ERROR: Destination existence changed for '$($Snapshot.Path)'."
    }

    if ($Snapshot.LeafExists -and
        $current.LeafIdentity -cne $Snapshot.LeafIdentity) {
        throw "SECURITY ERROR: TOCTOU identity mismatch on destination file '$($Snapshot.Path)' before replacement."
    }

    return $true
}

function Get-WibValidatedStageSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [ValidateSet('Json', 'Xml')]
        [string]$PayloadKind,

        [switch]$RequireSensitiveAcl
    )

    $pathSnapshot = Assert-WibSafeSensitiveOutputPath -Path $Path

    # WIB-047: Open stage with exclusive access (FileShare.None) and compute
    # identity, hash, length, and read exact bytes once into an immutable buffer through that single open stream handle.
    $identity = $null
    $sha256 = $null
    $length = 0L
    $text = $null
    $daclFingerprint = $null

    $fs = New-Object System.IO.FileStream(
        $pathSnapshot.Path,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::None
    )
    try {
        $identity = [WibKernelPathHelper]::GetKernelNodeIdentityFromHandle($fs.SafeFileHandle)
        if ([string]::IsNullOrWhiteSpace($identity) -or
            $identity -like 'REPARSE:*' -or
            $identity -ne $pathSnapshot.LeafIdentity -or
            $fs.Length -le 0) {
            throw "SECURITY ERROR: Staging file handle snapshot is invalid or mismatch: '$Path'."
        }

        $length = [long]$fs.Length

        # Read exact stream bytes once into an immutable byte buffer (WIB-047)
        $buffer = New-Object byte[] $length
        $totalRead = 0
        while ($totalRead -lt $length) {
            $bytesRead = $fs.Read($buffer, $totalRead, $length - $totalRead)
            if ($bytesRead -le 0) { break }
            $totalRead += $bytesRead
        }
        if ($totalRead -ne $length) {
            throw "SECURITY ERROR: Failed to read complete staging payload into memory buffer: '$Path'."
        }

        # Compute SHA-256 directly from the captured buffer bytes
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            $hashBytes = $sha.ComputeHash($buffer)
            $sb = New-Object System.Text.StringBuilder -ArgumentList 64
            foreach ($b in $hashBytes) {
                [void]$sb.Append($b.ToString('X2'))
            }
            $sha256 = $sb.ToString()
        }
        finally {
            $sha.Dispose()
        }

        # Decode string directly from the captured buffer bytes (guaranteed identical to hashed bytes)
        $text = [System.Text.Encoding]::UTF8.GetString($buffer).TrimStart([char]0xFEFF)

        # Parse payload directly from the decoded string
        switch ($PayloadKind) {
            'Json' {
                $null = ConvertFrom-Json -InputObject $text -ErrorAction Stop
            }
            'Xml' {
                $null = [xml]$text
            }
        }

        # If sensitive ACL is required, query access control directly through the open FileStream handle
        if ($RequireSensitiveAcl) {
            $acl = $fs.GetAccessControl()
            [void](Assert-WibSensitiveAclIntegrity `
                -Path $pathSnapshot.Path `
                -Acl $acl)
            $daclFingerprint = Get-WibAclFingerprint -Acl $acl
        }

        # Verify identity from handle remains unchanged before closing
        $identityAfter = [WibKernelPathHelper]::GetKernelNodeIdentityFromHandle($fs.SafeFileHandle)
        if ($identityAfter -ne $identity) {
            throw "SECURITY ERROR: Staging file handle identity mutated during read: '$Path'."
        }
    }
    finally {
        $fs.Dispose()
    }

    return [pscustomobject]@{
        Path                 = $pathSnapshot.Path
        KernelIdentity       = $identity
        Sha256               = $sha256
        Length               = [long]$length
        DaclFingerprint      = $daclFingerprint
        PathSnapshot         = $pathSnapshot
        PayloadKind          = $PayloadKind
        RequiresSensitiveAcl = [bool]$RequireSensitiveAcl
    }
}

function Assert-WibStagedFileStillMatches {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSObject]$Snapshot
    )

    Assert-WibSensitivePathSnapshot -Snapshot $Snapshot.PathSnapshot | Out-Null

    # WIB-047: Open staging file under FileShare.None to verify identity, length, hash, and ACL in one handle-bound transaction
    $fs = New-Object System.IO.FileStream(
        $Snapshot.Path,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::None
    )
    try {
        $hId = [WibKernelPathHelper]::GetKernelNodeIdentityFromHandle($fs.SafeFileHandle)
        if ($hId -cne $Snapshot.KernelIdentity) {
            throw "SECURITY ERROR: Staging file identity changed: '$($Snapshot.Path)'."
        }

        if ($fs.Length -ne $Snapshot.Length) {
            throw "SECURITY ERROR: Staging file length changed: '$($Snapshot.Path)'."
        }

        $sha = [System.Security.Cryptography.SHA256]::Create()
        $actualSha = $null
        try {
            $hashBytes = $sha.ComputeHash($fs)
            $sb = New-Object System.Text.StringBuilder -ArgumentList 64
            foreach ($b in $hashBytes) {
                [void]$sb.Append($b.ToString('X2'))
            }
            $actualSha = $sb.ToString()
        }
        finally {
            $sha.Dispose()
        }

        if ($actualSha -ine $Snapshot.Sha256) {
            throw "SECURITY ERROR: Staging file SHA-256 changed: '$($Snapshot.Path)'."
        }

        if ($Snapshot.RequiresSensitiveAcl) {
            $acl = $fs.GetAccessControl()
            [void](Assert-WibSensitiveAclIntegrity `
                -Path $Snapshot.Path `
                -Acl $acl)

            $fp = Get-WibAclFingerprint -Acl $acl
            if ($fp -cne $Snapshot.DaclFingerprint) {
                throw "SECURITY ERROR: Staging DACL changed: '$($Snapshot.Path)'."
            }
        }
    }
    finally {
        $fs.Dispose()
    }

    return $true
}

function Remove-WibOwnedFileIfMatches {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$ExpectedIdentity,

        [string]$ExpectedSha256 = ''
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $true
    }

    if ([string]::IsNullOrWhiteSpace($ExpectedIdentity) -or
        $ExpectedIdentity -notmatch '^OK:[0-9A-Fa-f]{8}:[0-9A-Fa-f]{8}:[0-9A-Fa-f]{8}$') {
        throw "CRITICAL OWNERSHIP FAILURE: Expected identity is mandatory and must match format 'OK:XXXXXXXX:XXXXXXXX:XXXXXXXX': '$ExpectedIdentity'."
    }

    if (-not [string]::IsNullOrWhiteSpace($ExpectedSha256) -and
        $ExpectedSha256 -notmatch '^[0-9A-Fa-f]{64}$') {
        throw "CRITICAL OWNERSHIP FAILURE: Expected SHA-256 is malformed; must be exactly 64 hexadecimal characters: '$ExpectedSha256'."
    }

    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop

    if ($item.PSIsContainer -or
        (($item.Attributes -band
          [System.IO.FileAttributes]::ReparsePoint) -ne 0)) {
        throw "SECURITY ERROR: Refusing cleanup of unexpected path '$Path'."
    }

    # Handle-bound deletion: opens exact leaf with restrictive sharing, validates File ID through handle,
    # verifies SHA-256 (if supplied) while holding open handle, and marks handle for deletion via SetFileInformationByHandle (WIB-034/WIB-039).
    $delErr = $null
    $delOk = [WibKernelPathHelper]::DeleteFileByHandleIfIdentityMatches($Path, $ExpectedIdentity, $ExpectedSha256, [ref]$delErr)

    if (-not $delOk) {
        throw "CRITICAL OWNERSHIP FAILURE: Refusing deletion of '$Path': $delErr"
    }

    if (Test-Path -LiteralPath $Path) {
        throw "Failed to remove transaction-owned file '$Path'."
    }

    return $true
}

function Complete-WibBackupCleanup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [string]$ExpectedIdentity = '',
        [string]$ExpectedSha256 = '',

        [switch]$Sensitive,

        [ValidateSet('Committed', 'RolledBack')]
        [string]$Outcome = 'Committed'
    )

    $status = [ordered]@{
        outcome       = $Outcome
        backupPath    = $Path
        backupRemoved = $false
        status        = 'noBackup'
        cleanupError  = $null
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        $result = [pscustomobject]$status
        $script:WibLastFileTransactionStatus = $result
        return $result
    }

    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop

        if ($item.PSIsContainer -or
            (($item.Attributes -band
              [System.IO.FileAttributes]::ReparsePoint) -ne 0)) {
            throw "Backup path is not a regular file."
        }

        if ([string]::IsNullOrWhiteSpace($ExpectedIdentity) -or
            $ExpectedIdentity -notmatch '^OK:[0-9A-Fa-f]{8}:[0-9A-Fa-f]{8}:[0-9A-Fa-f]{8}$') {
            throw "Backup identity was not captured or is malformed; refusing deletion."
        }

        if (-not [string]::IsNullOrWhiteSpace($ExpectedSha256) -and
            $ExpectedSha256 -notmatch '^[0-9A-Fa-f]{64}$') {
            throw "Backup SHA-256 is malformed; refusing deletion."
        }

        $deleteHook = if ($null -ne $script:WibBeforeBackupDeleteHook) { $script:WibBeforeBackupDeleteHook } else { $global:WibBeforeBackupDeleteHook }
        $faultEnabled = $script:WibFaultInjectionEnabled -or $global:WibFaultInjectionEnabled
        if ($faultEnabled -and $deleteHook -is [scriptblock]) {
            & $deleteHook -Path $Path
        }

        # Handle-bound deletion of backup file (WIB-034)
        $delErr = $null
        $delOk = [WibKernelPathHelper]::DeleteFileByHandleIfIdentityMatches($Path, $ExpectedIdentity, $ExpectedSha256, [ref]$delErr)

        if (-not $delOk) {
            throw "Handle-bound backup deletion failed: $delErr"
        }

        if (Test-Path -LiteralPath $Path) {
            throw "Backup remains after the deletion request."
        }

        $status.backupRemoved = $true
        $status.status = 'backupRemoved'
    }
    catch {
        $status.cleanupError = $_.Exception.Message

        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            $isSameBackup = $false
            if (-not [string]::IsNullOrWhiteSpace($ExpectedIdentity)) {
                try {
                    $currentBackupId = Get-WibKernelNodeIdentity -LiteralPath $Path
                    if ($currentBackupId -eq $ExpectedIdentity) {
                        $isSameBackup = $true
                    }
                }
                catch {
                    $isSameBackup = $false
                }
            }

            if (-not $isSameBackup) {
                # WIB-040: Unowned replacement file at backup path; preserve completely untouched (do NOT touch ACL)
                $status.status = 'backupPathReplacedByUnownedFile'
            }
            else {
                # WIB-048 test seam: allow injecting a substitution right between identity check and ACL handling
                $aclHook = if ($null -ne $script:WibBeforeBackupAclHook) { $script:WibBeforeBackupAclHook } else { $global:WibBeforeBackupAclHook }
                if ($faultEnabled -and $aclHook -is [scriptblock]) {
                    & $aclHook -Path $Path
                }

                # Re-verify identity and bind ACL protection strictly to the verified open handle (WIB-048)
                if ($Sensitive) {
                    $bkFs = $null
                    try {
                        $bkFs = [System.IO.File]::Open(
                            $Path,
                            [System.IO.FileMode]::Open,
                            [System.IO.FileAccess]::ReadWrite,
                            [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete
                        )
                        $bkHandleId = [WibKernelPathHelper]::GetKernelNodeIdentityFromHandle($bkFs.SafeFileHandle)
                        if ($bkHandleId -eq $ExpectedIdentity) {
                            $bkAcl = $bkFs.GetAccessControl()
                            $bkAcl.SetAccessRuleProtection($true, $false)
                            $bkFs.SetAccessControl($bkAcl)
                        } else {
                            $status.status = 'backupPathReplacedByUnownedFile'
                        }
                    }
                    catch {
                        $checkId = $null
                        try { $checkId = Get-WibKernelNodeIdentity -LiteralPath $Path } catch {}
                        if ($checkId -ne $ExpectedIdentity) {
                            $status.status = 'backupPathReplacedByUnownedFile'
                        } else {
                            $status.cleanupError += "; ACL re-protection failed: $($_.Exception.Message)"
                        }
                    }
                    finally {
                        if ($null -ne $bkFs) { $bkFs.Dispose() }
                    }
                }

                if ($status.status -ne 'backupPathReplacedByUnownedFile') {
                    if ($Outcome -eq 'Committed') {
                        $status.status = 'committedWithBackupRemaining'
                    }
                    else {
                        $status.status = 'rolledBackWithBackupRemaining'
                    }
                }
            }
        }
        else {
            $status.status = 'backupAbsentAfterCleanupError'
        }

        Write-Warning (
            "WIB backup cleanup warning: status={0}; path='{1}'; error={2}" -f
            $status.status, $Path, $status.cleanupError
        )

        if (Get-Command Write-WibLog -ErrorAction SilentlyContinue) {
            Write-WibLog `
                -Message ("Backup cleanup status={0}; path='{1}'; error={2}" -f
                    $status.status, $Path, $status.cleanupError) `
                -Level 'WARN'
        }
    }

    $result = [pscustomobject]$status
    $script:WibLastFileTransactionStatus = $result
    $global:WibLastFileTransactionStatus = $result

    return $result
}

function Invoke-WibSensitiveCommitTestHook {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Boundary,

        [Parameter(Mandatory)]
        [string]$StagePath,

        [Parameter(Mandatory)]
        [string]$DestinationPath
    )

    $faultEnabled = $script:WibFaultInjectionEnabled -or $global:WibFaultInjectionEnabled
    if (-not $faultEnabled) {
        return
    }

    $hook = if ($null -ne $script:WibSensitiveCommitTestHook) { $script:WibSensitiveCommitTestHook } else { $global:WibSensitiveCommitTestHook }
    if ($hook -is [scriptblock]) {
        & $hook `
            -Boundary $Boundary `
            -StagePath $StagePath `
            -DestinationPath $DestinationPath
    }
}

function New-WibSecureTempFile {
    param([string]$Extension = '.tmp')
    $tempPath = [System.IO.Path]::GetTempPath()
    $fileName = "wib-" + [System.Guid]::NewGuid().ToString('N') + $Extension
    $fullPath = Join-Path $tempPath $fileName
    [System.IO.File]::WriteAllBytes($fullPath, [byte[]]@())
    try {
        [void](Protect-WibSensitiveFileAcl -Path $fullPath)
    } catch {
        if (Test-Path -LiteralPath $fullPath) {
            Remove-Item -LiteralPath $fullPath -Force -ErrorAction SilentlyContinue
        }
        throw "Failed to enforce secure ACL permissions on temporary file '$fullPath': $($_.Exception.Message)"
    }
    return $fullPath
}

function Get-WibShortPath {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $Path }
    try {
        $fso = New-Object -ComObject Scripting.FileSystemObject
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            $short = $fso.GetFile($Path).ShortPath
        } else {
            $short = $fso.GetFolder($Path).ShortPath
        }
        if ($short -and -not [string]::IsNullOrEmpty($short)) {
            return $short
        }
    } catch {
        Write-Verbose "Get-WibShortPath could not resolve short path for '$Path': $($_.Exception.Message)"
    }
    return $Path
}

function Lock-WibWorkspace {
    param(
        [Parameter(Mandatory)][string]$WorkDir,
        [Parameter(Mandatory)][string]$RunId
    )
    if (-not (Test-Path -LiteralPath $WorkDir)) {
        New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
    }
    if (Get-Command Protect-WibSensitiveDirectoryAcl -ErrorAction SilentlyContinue) {
        [void](Protect-WibSensitiveDirectoryAcl -Path $WorkDir)
    }
    $lockFile = Join-Path $WorkDir 'build.lock.json'
    try {
        $stream = [System.IO.File]::Open($lockFile, [System.IO.FileMode]::Create, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        $lockInfo = [ordered]@{
            pid       = $PID
            machine   = $env:COMPUTERNAME
            runId     = $RunId
            started   = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            user      = $env:USERNAME
        }
        $raw = $lockInfo | ConvertTo-Json -Compress
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($raw)
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush()
        return $stream
    } catch [System.IO.IOException] {
        throw "Workspace '$WorkDir' is locked by an active build process ($lockFile). Concurrent builds in the same workspace are forbidden to prevent image and hive corruption. Specify a different -WorkDir or wait for the active build to complete."
    }
}

function Unlock-WibWorkspace {
    param(
        $LockStream,
        [string]$WorkDir
    )
    if ($LockStream) {
        try {
            $LockStream.Close()
            $LockStream.Dispose()
        } catch {
            Write-Verbose $_.Exception.Message
        }
    }
    # Note: build.lock.json is intentionally NOT deleted. The exclusive OS FileStream
    # handle with FileShare.None is the lock. Leaving the file avoids a TOCTOU race
    # where Process A closes, Process B locks, and Process A deletes Process B's file.
}

function Test-WibPathContainment {
    <#
    .SYNOPSIS
        Validates that a path is strictly contained within an authorized base directory
        and does not cross filesystem boundaries via NTFS junctions, symbolic links, or reparse points.
        Uses both per-segment attribute inspection and kernel handle GetFinalPathNameByHandleW verification.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$BaseDir,
        [switch]$AllowReparsePoint
    )
    if ($Path -match '^[\\/]{2}' -or $BaseDir -match '^[\\/]{2}') {
        throw "UNC network and Win32 device namespace paths are forbidden for security: $Path"
    }
    # Reject NTFS Alternate Data Streams (any colon outside a leading drive letter 'X:')
    $colonCheck = $Path
    if ($colonCheck -match '^[a-zA-Z]:') {
        $colonCheck = $colonCheck.Substring(2)
    }
    if ($colonCheck.IndexOf(':') -ge 0) {
        throw "Path containment violation: NTFS alternate data streams or embedded colons are forbidden: $Path"
    }

    $baseFull = [System.IO.Path]::GetFullPath($BaseDir)
    $baseRoot = [System.IO.Path]::GetPathRoot($baseFull)
    $baseTrimmed = $baseFull.TrimEnd('\', '/')
    if ($baseRoot -and ($baseTrimmed -ieq $baseRoot.TrimEnd('\', '/'))) {
        throw "Path containment violation: BaseDir '$BaseDir' cannot be a volume drive root."
    }

    $canonicalBase = $baseTrimmed + [System.IO.Path]::DirectorySeparatorChar
    $rawTarget = if ([System.IO.Path]::IsPathRooted($Path)) {
        [System.IO.Path]::GetFullPath($Path)
    } else {
        [System.IO.Path]::GetFullPath((Join-Path $baseTrimmed $Path))
    }
    $targetRoot = [System.IO.Path]::GetPathRoot($rawTarget)
    $targetPath = $rawTarget.TrimEnd('\', '/')
    if ($targetRoot -and ($targetPath -ieq $targetRoot.TrimEnd('\', '/'))) {
        throw "Path traversal violation: '$Path' resolves to volume drive root '$rawTarget', which is outside allowed base directory '$BaseDir'"
    }

    if (-not $targetPath.StartsWith($canonicalBase, [System.StringComparison]::OrdinalIgnoreCase) -and
        $targetPath -ine $baseTrimmed) {
        throw "Path traversal violation: '$Path' resolves to '$targetPath', which is outside allowed base directory '$BaseDir'"
    }

    # Inspect path segments and kernel-resolved handle paths for adversarial reparse points / junctions
    if (-not $AllowReparsePoint) {
        $probe = $targetPath
        $deepestExisting = $null
        while ($probe -and $probe.Length -ge $baseTrimmed.Length) {
            if (Test-Path -LiteralPath $probe) {
                if (-not $deepestExisting) {
                    $deepestExisting = $probe
                }
                $item = Get-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
                if ($item -and [bool]($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
                    throw "Reparse point violation: Path '$probe' is an NTFS junction or symbolic link. Reparse points are forbidden within confined paths to prevent filesystem redirection attacks."
                }
            }
            $parent = Split-Path -Parent $probe
            if (-not $parent -or $parent -eq $probe) { break }
            $probe = $parent.TrimEnd('\', '/')
        }

        # Kernel handle final-path containment check via GetFinalPathNameByHandleW
        if ($deepestExisting -and (Test-Path -LiteralPath $baseTrimmed) -and ([System.Management.Automation.PSTypeName]'WibKernelPathHelper').Type) {
            $kernelBase = [WibKernelPathHelper]::GetKernelFinalPath($baseTrimmed)
            $kernelTarget = [WibKernelPathHelper]::GetKernelFinalPath($deepestExisting)
            if ($kernelBase -and $kernelTarget) {
                $kBaseTrim = $kernelBase.TrimEnd('\', '/')
                $kBasePrefix = $kBaseTrim + [System.IO.Path]::DirectorySeparatorChar
                $kTargetTrim = $kernelTarget.TrimEnd('\', '/')
                if (-not $kTargetTrim.StartsWith($kBasePrefix, [System.StringComparison]::OrdinalIgnoreCase) -and
                    $kTargetTrim -ine $kBaseTrim) {
                    throw "Reparse point violation: Kernel handle resolution for '$deepestExisting' resolved to '$kTargetTrim', escaping base directory '$kBaseTrim'."
                }
            }
        }
    }

    return $targetPath
}

function Assert-WibNoReparsePointsInTree {
    <#
    .SYNOPSIS
        Validates path containment and recursively inspects all descendant items using a non-following
        directory stack to ensure no nested NTFS junctions or symbolic links exist inside the target tree.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$BaseDir
    )
    $resolvedTarget = Test-WibPathContainment -Path $Path -BaseDir $BaseDir
    if (Test-Path -LiteralPath $resolvedTarget) {
        $rootItem = Get-Item -LiteralPath $resolvedTarget -Force -ErrorAction Stop
        if ([bool]($rootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
            throw "Reparse point violation: Path '$resolvedTarget' is an NTFS junction or symbolic link."
        }
        if ($rootItem -is [System.IO.DirectoryInfo]) {
            $stack = New-Object System.Collections.Stack
            $stack.Push($rootItem)
            while ($stack.Count -gt 0) {
                $currentDir = [System.IO.DirectoryInfo]$stack.Pop()
                foreach ($fsi in $currentDir.GetFileSystemInfos()) {
                    if ([bool]($fsi.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
                        throw "Reparse point violation: Descendant path '$($fsi.FullName)' inside '$resolvedTarget' is an NTFS junction or symbolic link. Reparse points are forbidden within confined trees."
                    }
                    if ($fsi -is [System.IO.DirectoryInfo]) {
                        $stack.Push($fsi)
                    }
                }
            }
        }
    }
    return $resolvedTarget
}

function Resolve-WibConfinedPath {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$BaseDir,
        [string[]]$AllowedExtensions = @('.xml'),
        [switch]$AllowReparsePoint
    )
    if ($Path -match '^[\\/]{2}') {
        throw "UNC network paths are forbidden for security: $Path"
    }
    $ext = [System.IO.Path]::GetExtension($Path)
    if ($AllowedExtensions.Count -gt 0 -and ($AllowedExtensions -notcontains $ext)) {
        throw "Invalid file extension '$ext'. Allowed extensions: $($AllowedExtensions -join ', ')"
    }
    return (Test-WibPathContainment -Path $Path -BaseDir $BaseDir -AllowReparsePoint:$AllowReparsePoint)
}

function Get-WibHiveKeyName {
    param([Parameter(Mandatory)][string]$Hive)
    $pfx = if ($script:WibHivePrefix) { $script:WibHivePrefix } else { 'wib_' }
    "$pfx$Hive"
}

function Get-WibHiveRegistryPath {
    param([Parameter(Mandatory)][string]$Hive, [string]$SubPath = '')
    $pfx = if ($script:WibHivePrefix) { $script:WibHivePrefix } else { 'wib_' }
    $prefix = "Registry::HKEY_LOCAL_MACHINE\$pfx$Hive"
    if ($SubPath) {
        if ($SubPath.StartsWith('\')) {
            return "$prefix$SubPath"
        } else {
            return "$prefix\$SubPath"
        }
    }
    return $prefix
}

function Get-WibOfflineTaskCacheGuids {
    param([string]$SubkeyFilter = '')
    $results = New-Object System.Collections.ArrayList
    $pfx = if ($script:WibHivePrefix) { $script:WibHivePrefix } else { 'wib_' }
    try {
        $regKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("${pfx}SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tasks")
        if ($regKey) {
            try {
                $subNames = $regKey.GetSubKeyNames()
                foreach ($sn in $subNames) {
                    $childKey = $regKey.OpenSubKey($sn)
                    if ($childKey) {
                        try {
                            $pathVal = [string]$childKey.GetValue('Path')
                            if ($pathVal) {
                                if (-not $SubkeyFilter -or $pathVal -like "*$SubkeyFilter*") {
                                    [void]$results.Add(@{ Guid = $sn; Path = $pathVal })
                                }
                            }
                        } finally {
                            $childKey.Close()
                            $childKey.Dispose()
                        }
                    }
                }
            } finally {
                $regKey.Close()
                $regKey.Dispose()
            }
        }
    } catch {
        Write-Verbose "Get-WibOfflineTaskCacheGuids: $($_.Exception.Message)"
    }
    return $results
}

function Clear-WibStaleHives {
    param([string]$Prefix = '')
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
    [System.GC]::Collect()
    $pfx = if ($Prefix) { $Prefix } elseif ($script:WibHivePrefix) { $script:WibHivePrefix } else { 'wib_' }
    try {
        $hklm = [Microsoft.Win32.Registry]::LocalMachine
        $loadedKeys = @($hklm.GetSubKeyNames() | Where-Object { $_ -like 'wib_*' -or $_ -like "$pfx*" })
        foreach ($kName in $loadedKeys) {
            $isOwnRun = ($pfx -and $kName.StartsWith($pfx, [System.StringComparison]::OrdinalIgnoreCase))
            $unloaded = $false
            for ($attempt = 0; $attempt -lt 3; $attempt++) {
                [void](Invoke-WibNativeTool -ToolKey 'regExe' -FilePath 'reg.exe' -Arguments @('unload', "HKLM\$kName"))
                if ($LASTEXITCODE -eq 0) {
                    $unloaded = $true
                    Write-WibLog "Unloaded stale hive HKLM\$kName from a previous run." 'WARN'
                    break
                }
                Start-Sleep -Milliseconds 250
                [System.GC]::Collect()
                [System.GC]::WaitForPendingFinalizers()
                [System.GC]::Collect()
            }
            if (-not $unloaded -and $isOwnRun) {
                if (Test-Path -LiteralPath "Registry::HKEY_LOCAL_MACHINE\$kName") {
                    throw "Stale hive HKLM\$kName is still loaded and cannot be unloaded. Close regedit or processes accessing it."
                }
            } elseif (-not $unloaded) {
                Write-WibLog "Hive HKLM\$kName is currently held by an active process or concurrent build; skipping cleanup." 'VERBOSE'
            }
        }
    } catch {
        if ($_.Exception.Message -like '*Stale hive*') { throw }
        Write-Verbose "Clear-WibStaleHives: $($_.Exception.Message)"
    }
}

# ---------------------------------------------------------------- offline registry
function New-WibTweak {
    param(
        [Parameter(Mandatory)][ValidateSet('SOFTWARE', 'SYSTEM', 'DEFAULT', 'NTUSER')][string]$Hive,
        [Parameter(Mandatory)][string]$Path,
        [string]$Name,
        [ValidateSet('DWord', 'QWord', 'String', 'ExpandString', 'MultiString', 'Binary', 'None')][string]$Type = 'DWord',
        $Value,
        [ValidateSet('Set', 'DeleteKey', 'DeleteValue')][string]$Action = 'Set'
    )
    @{ Hive = $Hive; Path = $Path; Name = $Name; Type = $Type; Value = $Value; Action = $Action }
}

function Mount-WibHives {
    param(
        [Parameter(Mandatory)][string]$MountDir,
        [string]$Prefix = ''
    )
    if ($Prefix) {
        $script:WibHivePrefix = $Prefix
    } elseif (-not $script:WibHivePrefix) {
        $script:WibHivePrefix = 'wib_'
    }
    Clear-WibStaleHives -Prefix $script:WibHivePrefix
    try {
        foreach ($name in $script:WibHiveFiles.Keys) {
            $file = Join-Path $MountDir $script:WibHiveFiles[$name]
            if (-not (Test-Path -LiteralPath $file)) { Write-WibLog "Hive $name not found in image, skipping." 'WARN'; continue }
            $hiveKey = "$($script:WibHivePrefix)$name"
            [void](Invoke-WibNativeTool -ToolKey 'regExe' -FilePath 'reg.exe' -Arguments @('load', "HKLM\$hiveKey", $file))
            if ($LASTEXITCODE -ne 0) { throw "Failed to load hive $name from $file" }
            $script:WibLoadedHives += $name
        }
    } catch {
        [void](Dismount-WibHives)
        throw
    }
}

function Dismount-WibHives {
    param([switch]$ThrowOnFailure)
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
    [System.GC]::Collect()
    $stillLoaded = @()
    $pfx = if ($script:WibHivePrefix) { $script:WibHivePrefix } else { 'wib_' }
    foreach ($name in @($script:WibLoadedHives)) {
        $hiveKey = "$pfx$name"
        $ok = $false
        for ($i = 0; $i -lt 6 -and -not $ok; $i++) {
            [void](Invoke-WibNativeTool -ToolKey 'regExe' -FilePath 'reg.exe' -Arguments @('unload', "HKLM\$hiveKey"))
            if ($LASTEXITCODE -eq 0) { $ok = $true } else {
                Start-Sleep -Seconds 1
                [System.GC]::Collect()
                [System.GC]::WaitForPendingFinalizers()
                [System.GC]::Collect()
            }
        }
        if (-not $ok) {
            Write-WibLog "Could not unload hive $hiveKey (a handle may still be open)." 'WARN'
            $stillLoaded += $name
        }
    }
    $script:WibLoadedHives = $stillLoaded
    $success = ($stillLoaded.Count -eq 0)
    if (-not $success -and $ThrowOnFailure) {
        throw "Failed to unload offline registry hives: $($stillLoaded -join ', '). Ensure all open handles and keys are closed."
    }
    return $success
}

function Get-WibTweakPath {
    param($T)
    $pfx = if ($script:WibHivePrefix) { $script:WibHivePrefix } else { 'wib_' }
    "Registry::HKEY_LOCAL_MACHINE\$pfx$($T.Hive)\$($T.Path)"
}

function Get-WibTweakLabel {
    param($T)
    $label = "$($T.Hive)\$($T.Path)"
    if ($T.Name) { $label = "$label\$($T.Name)" }
    $label
}

function ConvertTo-WibUInt32 {
    param($Val)
    if ($Val -is [uint32]) { return [uint32]$Val }
    if ($Val -is [string] -and $Val.StartsWith('0x', [System.StringComparison]::OrdinalIgnoreCase)) {
        return [Convert]::ToUInt32($Val, 16)
    }
    $masked = ([int64]$Val) -band 0x00000000FFFFFFFFL
    return [uint32]$masked
}

function ConvertTo-WibUInt64 {
    param($Val)
    if ($Val -is [uint64]) { return [uint64]$Val }
    if ($Val -is [string] -and $Val.StartsWith('0x', [System.StringComparison]::OrdinalIgnoreCase)) {
        return [Convert]::ToUInt64($Val, 16)
    }
    if ($Val -is [string] -and $Val -match '^-') {
        return [BitConverter]::ToUInt64([BitConverter]::GetBytes([int64]$Val), 0)
    }
    if ($Val -is [int64] -or $Val -is [int32] -or $Val -is [int]) {
        return [BitConverter]::ToUInt64([BitConverter]::GetBytes([int64]$Val), 0)
    }
    return [uint64]$Val
}

function Get-WibTweakState {
    param($T)
    $state = @{ Exists = $false; Value = $null; Kind = $null }
    $p = Get-WibTweakPath $T
    if (Test-Path -LiteralPath $p) {
        $key = Get-Item -LiteralPath $p
        try {
            if ($T.Name -and ($key.GetValueNames() -contains $T.Name)) {
                $state.Exists = $true
                $state.Value = $key.GetValue($T.Name)
                $state.Kind = [string]$key.GetValueKind($T.Name)
            }
        } finally {
            $key.Close()
            $key.Dispose()
        }
    }
    $state
}

function Set-WibTweak {
    param($T, [System.Collections.IList]$Journal, [string]$Image = 'install')
    $p = Get-WibTweakPath $T

    $targetScope = if ($T.Hive -eq 'NTUSER') { 'default-user-only' } else { 'system' }
    $scopeNote = if ($T.Hive -eq 'NTUSER') {
        'Applies only to newly created user accounts (Users\Default\NTUSER.DAT). Does not alter existing user accounts on live system.'
    } else {
        'Applies system-wide.'
    }

    if ($T.Action -eq 'DeleteKey') {
        $existed = Test-Path -LiteralPath $p
        $exportedReg = $null
        if ($existed) {
            $tempReg = New-WibSecureTempFile -Extension '.reg'
            try {
                $pfx = if ($script:WibHivePrefix) { $script:WibHivePrefix } else { 'wib_' }
                [void](Invoke-WibNativeTool -ToolKey 'regExe' -FilePath 'reg.exe' -Arguments @('export', "HKLM\$pfx$($T.Hive)\$($T.Path)", $tempReg, '/y'))
                if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $tempReg)) {
                    $exportedReg = Get-Content -LiteralPath $tempReg -Raw -ErrorAction SilentlyContinue
                }
            } catch { Write-Verbose $_.Exception.Message }
            finally {
                Remove-Item -LiteralPath $tempReg -Force -ErrorAction SilentlyContinue
            }
        }
        $isTaskCache = ($T.Hive -eq 'SOFTWARE' -and $T.Path -match 'Schedule\\TaskCache')
        $restorable = ($existed -and ($null -ne $exportedReg) -and -not $isTaskCache)
        
        if ($existed) {
            if ($isTaskCache) {
                try {
                    $ids = New-Object System.Collections.ArrayList
                    $keyItem = Get-Item -LiteralPath $p -ErrorAction SilentlyContinue
                    if ($keyItem) {
                        $rootId = $keyItem.GetValue('Id')
                        if ($rootId) { [void]$ids.Add([string]$rootId) }
                        $keyItem.Close()
                    }
                    $childKeys = Get-ChildItem -LiteralPath $p -Recurse -ErrorAction SilentlyContinue
                    foreach ($ck in @($childKeys)) {
                        $cid = $ck.GetValue('Id')
                        if ($cid) { [void]$ids.Add([string]$cid) }
                        $ck.Close()
                    }
                    if ($ids.Count -gt 0) {
                        $pfx = if ($script:WibHivePrefix) { $script:WibHivePrefix } else { 'wib_' }
                        $cacheRoot = "Registry::HKEY_LOCAL_MACHINE\${pfx}SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache"
                        foreach ($tid in $ids) {
                            foreach ($sub in @('Tasks', 'Boot', 'Plain', 'Maintenance')) {
                                $guidPath = "$cacheRoot\$sub\$tid"
                                if (Test-Path -LiteralPath $guidPath) {
                                    Remove-Item -LiteralPath $guidPath -Recurse -Force -ErrorAction SilentlyContinue
                                }
                            }
                        }
                    }
                } catch { Write-Verbose $_.Exception.Message }
            }
            Remove-Item -LiteralPath $p -Recurse -Force
        }

        [void]$Journal.Add(@{
            Image       = $Image
            Action      = 'DeleteKey'
            Hive        = $T.Hive
            Path        = $T.Path
            Existed     = $existed
            Restorable  = $restorable
            ExportedReg = $exportedReg
            TargetScope = $targetScope
            ScopeNote   = $scopeNote
            Timestamp   = (Get-Date).ToUniversalTime().ToString('o')
        })
        return
    }

    if ($T.Action -eq 'DeleteValue') {
        $oldState = Get-WibTweakState $T
        $existed = $oldState.Exists
        $pfx = if ($script:WibHivePrefix) { $script:WibHivePrefix } else { 'wib_' }
        $hiveRoot = "Registry::HKEY_LOCAL_MACHINE\$pfx$($T.Hive)"
        if (Test-Path -LiteralPath $hiveRoot) {
            if (Test-Path -LiteralPath $p) {
                if ($existed) {
                    Remove-ItemProperty -LiteralPath $p -Name $T.Name -Force -ErrorAction SilentlyContinue
                }
            }
        }
        [void]$Journal.Add(@{
            Image       = $Image
            Action      = 'DeleteValue'
            Hive        = $T.Hive
            Path        = $T.Path
            Name        = $T.Name
            Existed     = $existed
            OldValue    = $oldState.Value
            OldKind     = $oldState.Kind
            Restorable  = $existed
            TargetScope = $targetScope
            ScopeNote   = $scopeNote
            Timestamp   = (Get-Date).ToUniversalTime().ToString('o')
        })
        return
    }

    $old = Get-WibTweakState $T
    $pfx = if ($script:WibHivePrefix) { $script:WibHivePrefix } else { 'wib_' }
    $hiveRoot = "Registry::HKEY_LOCAL_MACHINE\$pfx$($T.Hive)"
    if (Test-Path -LiteralPath $hiveRoot) {
        if (-not (Test-Path -LiteralPath $p)) { $null = New-Item -LiteralPath $p -Force }
        $val = $T.Value
        if ($T.Type -eq 'DWord') {
            if ($val -is [string] -and $val.StartsWith('0x', [System.StringComparison]::OrdinalIgnoreCase)) {
                $uVal = [Convert]::ToUInt32($val, 16)
                $val = [BitConverter]::ToInt32([BitConverter]::GetBytes($uVal), 0)
            } elseif ($val -is [uint32] -or ($val -is [int64] -and $val -ge 0 -and $val -le [uint32]::MaxValue)) {
                $uVal = [uint32]$val
                $val = [BitConverter]::ToInt32([BitConverter]::GetBytes($uVal), 0)
            } else {
                $val = [int]$val
            }
        } elseif ($T.Type -eq 'QWord') {
            $val = [int64]$val
        } elseif ($T.Type -eq 'Binary') {
            $val = [byte[]]$val
        } elseif ($T.Type -eq 'ExpandString') {
            $val = [string]$val
        } elseif ($T.Type -eq 'MultiString') {
            $val = [string[]]$val
        }
        $propType = $T.Type
        if ($propType -eq 'None') { $propType = 'DWord' }
        $null = New-ItemProperty -LiteralPath $p -Name $T.Name -Value $val -PropertyType $propType -Force
    }

    [void]$Journal.Add(@{
        Image       = $Image
        Action      = 'Set'
        Hive        = $T.Hive
        Path        = $T.Path
        Name        = $T.Name
        Existed     = $old.Exists
        OldValue    = $old.Value
        OldKind     = $old.Kind
        NewValue    = $T.Value
        NewKind     = $T.Type
        Restorable  = $true
        TargetScope = $targetScope
        ScopeNote   = $scopeNote
        Timestamp   = (Get-Date).ToUniversalTime().ToString('o')
    })
}

function Test-WibTweak {
    param($T)
    $label = Get-WibTweakLabel $T
    $pfx = if ($script:WibHivePrefix) { $script:WibHivePrefix } else { 'wib_' }
    if ($T.Hive -eq 'SYSTEM' -and $T.Path -match '^ControlSet001\\Services\\([^\\]+)') {
        if (-not (Test-Path -LiteralPath "Registry::HKEY_LOCAL_MACHINE\${pfx}SYSTEM\ControlSet001\Services\$($Matches[1])")) {
            return (New-WibResult 'verify' $label 'skip' 'service not present in image')
        }
    }
    if ($T.Action -eq 'DeleteKey') {
        if (Test-Path -LiteralPath (Get-WibTweakPath $T)) { return (New-WibResult 'verify' $label 'fail' 'key still present') }
        return (New-WibResult 'verify' $label 'pass')
    }
    if ($T.Action -eq 'DeleteValue') {
        $s = Get-WibTweakState $T
        if ($s.Exists) { return (New-WibResult 'verify' $label 'fail' 'value still present') }
        return (New-WibResult 'verify' $label 'pass')
    }
    $s = Get-WibTweakState $T
    if (-not $s.Exists) { return (New-WibResult 'verify' $label 'fail' 'value missing') }
    if ($T.Type -eq 'DWord') {
        $expectedDword = ConvertTo-WibUInt32 $T.Value
        $actualDword = ConvertTo-WibUInt32 $s.Value
        if ($expectedDword -ne $actualDword) {
            return (New-WibResult 'verify' $label 'fail' "expected '$expectedDword', found '$actualDword'")
        }
    } elseif ($T.Type -eq 'QWord') {
        $expectedNum = ConvertTo-WibUInt64 $T.Value
        $actualNum = ConvertTo-WibUInt64 $s.Value
        if ($expectedNum -ne $actualNum) {
            return (New-WibResult 'verify' $label 'fail' "expected '$expectedNum', found '$actualNum'")
        }
    } elseif ($T.Type -eq 'Binary') {
        $expectedStr = ([byte[]]$T.Value) -join ','
        $actualStr = ([byte[]]$s.Value) -join ','
        if ($expectedStr -ne $actualStr) {
            return (New-WibResult 'verify' $label 'fail' "expected '$expectedStr', found '$actualStr'")
        }
    } elseif ($T.Type -eq 'MultiString') {
        $expectedArr = @($T.Value) -join "`n"
        $actualArr = @($s.Value) -join "`n"
        if ($expectedArr -ne $actualArr) {
            return (New-WibResult 'verify' $label 'fail' "expected '$expectedArr', found '$actualArr'")
        }
    } else {
        if ([string]$s.Value -ne [string]$T.Value) { return (New-WibResult 'verify' $label 'fail' "expected '$($T.Value)', found '$($s.Value)'") }
    }
    New-WibResult 'verify' $label 'pass'
}

function Invoke-WibTweaks {
    param([object[]]$Tweaks, [string]$ModuleId, [System.Collections.IList]$Journal, [string]$Image = 'install')
    $results = @()
    $pfx = if ($script:WibHivePrefix) { $script:WibHivePrefix } else { 'wib_' }
    foreach ($t in $Tweaks) {
        $label = Get-WibTweakLabel $t
        if ($script:WibLoadedHives -notcontains $t.Hive) {
            $results += (New-WibResult $ModuleId $label 'skipped' "hive $($t.Hive) not loaded")
            continue
        }
        if ($t.Hive -eq 'SYSTEM' -and $t.Path -match '^ControlSet001\\Services\\([^\\]+)') {
            if (-not (Test-Path -LiteralPath "Registry::HKEY_LOCAL_MACHINE\${pfx}SYSTEM\ControlSet001\Services\$($Matches[1])")) {
                $results += (New-WibResult $ModuleId $label 'skipped' 'service not present in image')
                continue
            }
        }
        try {
            Set-WibTweak -T $t -Journal $Journal -Image $Image
            $results += (New-WibResult $ModuleId $label 'applied')
        } catch {
            $results += (New-WibResult $ModuleId $label 'failed' $_.Exception.Message)
        }
    }
    $results
}

# ---------------------------------------------------------------- file-level helpers
function Grant-WibAccess {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$BaseDir = ''
    )
    if ($BaseDir) {
        $Path = Assert-WibNoReparsePointsInTree -Path $Path -BaseDir $BaseDir
    } else {
        $parentBase = Split-Path -Parent ([System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/'))
        if ($parentBase) {
            $Path = Assert-WibNoReparsePointsInTree -Path $Path -BaseDir $parentBase
        }
    }
    if (Test-Path -LiteralPath $Path -PathType Container) {
        [void](Invoke-WibNativeTool -ToolKey 'takeownExe' -FilePath 'takeown.exe' -Arguments @('/f', $Path, '/r', '/d', 'Y'))
        if ($LASTEXITCODE -ne 0) {
            throw "takeown.exe failed with exit code $LASTEXITCODE on container '$Path'."
        }
        [void](Invoke-WibNativeTool -ToolKey 'icaclsExe' -FilePath 'icacls.exe' -Arguments @($Path, '/grant', '*S-1-5-32-544:(F)', '/t', '/c'))
        if ($LASTEXITCODE -ne 0) {
            throw "icacls.exe failed with exit code $LASTEXITCODE on container '$Path'."
        }
    } else {
        [void](Invoke-WibNativeTool -ToolKey 'takeownExe' -FilePath 'takeown.exe' -Arguments @('/f', $Path))
        if ($LASTEXITCODE -ne 0) {
            throw "takeown.exe failed with exit code $LASTEXITCODE on file '$Path'."
        }
        [void](Invoke-WibNativeTool -ToolKey 'icaclsExe' -FilePath 'icacls.exe' -Arguments @($Path, '/grant', '*S-1-5-32-544:(F)', '/c'))
        if ($LASTEXITCODE -ne 0) {
            throw "icacls.exe failed with exit code $LASTEXITCODE on file '$Path'."
        }
    }
}

function Get-WibPathPlanItems {
    param($Ctx, [string]$Module, [string[]]$RelPaths, [string]$Reason, [string]$Reversibility = 'permanent')
    foreach ($rel in $RelPaths) {
        $full = Test-WibPathContainment -Path $rel -BaseDir $Ctx.MountDir
        if (Test-Path -LiteralPath $full) {
            $bytes = 0
            try {
                if (Test-Path -LiteralPath $full -PathType Container) {
                    $measured = Get-ChildItem -LiteralPath $full -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum
                    if ($measured -and $null -ne $measured.Sum) { $bytes = [long]$measured.Sum }
                } else {
                    $item = Get-Item -LiteralPath $full -ErrorAction SilentlyContinue
                    if ($item) { $bytes = [long]$item.Length }
                }
            } catch { Write-Verbose $_.Exception.Message }
            New-WibPlanItem $Module 'Delete path' $rel $Reason -Reversibility $Reversibility -EstimatedBytes $bytes
        }
    }
}

function Remove-WibConfinedTreeSafe {
    <#
    .SYNOPSIS
        Performs a handle-identity-verified, non-following bottom-up tree deletion within a confined base directory.
    .DESCRIPTION
        Closes the validation-to-deletion race window (WIB-009 & WIB-014) by:
        1. Validating path containment and non-reparse status via Assert-WibNoReparsePointsInTree.
        2. Requiring Get-WibKernelNodeIdentity (64-bit NTFS File ID via CreateFileW(FILE_FLAG_BACKUP_SEMANTICS |
           FILE_FLAG_OPEN_REPARSE_POINT) + GetFileInformationByHandle) to succeed fail-closed with zero
           fallback downgrade if kernel identity support is unavailable.
        3. Deleting files and directories bottom-up using single-node APIs ([System.IO.File]::Delete and
           non-recursive [System.IO.Directory]::Delete(path, false)), re-verifying immediately before each
           unlink that the node's 64-bit NTFS File ID is unchanged and that it has not been converted into
           a reparse point or junction.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$BaseDir,
        [scriptblock]$OnBeforeNodeDelete
    )
    $resolvedRoot = Assert-WibNoReparsePointsInTree -Path $Path -BaseDir $BaseDir
    if (-not (Test-Path -LiteralPath $resolvedRoot)) { return }

    $rootItem = Get-Item -LiteralPath $resolvedRoot -Force -ErrorAction Stop
    if ([bool]($rootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
        throw "Reparse point violation: Root path '$resolvedRoot' is an NTFS junction or symbolic link."
    }

    if ($rootItem -isnot [System.IO.DirectoryInfo]) {
        $expectedFileId = Get-WibKernelNodeIdentity -LiteralPath $resolvedRoot
        if (-not $expectedFileId -or $expectedFileId.StartsWith('REPARSE:')) {
            throw "Reparse point or identity violation on leaf '$resolvedRoot' ($expectedFileId)."
        }
        if ($OnBeforeNodeDelete) { & $OnBeforeNodeDelete $resolvedRoot 'File' }
        $currentFileId = Get-WibKernelNodeIdentity -LiteralPath $resolvedRoot
        if ($currentFileId -ne $expectedFileId) {
            throw "TOCTOU node identity mismatch before deleting file '$resolvedRoot': expected '$expectedFileId', found '$currentFileId'."
        }
        if ([bool]($rootItem.Attributes -band [System.IO.FileAttributes]::ReadOnly)) {
            $rootItem.Attributes = $rootItem.Attributes -band (-bnot [System.IO.FileAttributes]::ReadOnly)
        }
        [System.IO.File]::Delete($resolvedRoot)
        return
    }

    $fileNodes = New-Object System.Collections.ArrayList
    $dirNodes = New-Object System.Collections.ArrayList
    $walkStack = New-Object System.Collections.Stack
    $walkStack.Push($rootItem)

    while ($walkStack.Count -gt 0) {
        $currDir = [System.IO.DirectoryInfo]$walkStack.Pop()
        $dirFull = $currDir.FullName
        $dirId = Get-WibKernelNodeIdentity -LiteralPath $dirFull
        if (-not $dirId -or $dirId.StartsWith('REPARSE:')) {
            throw "Reparse point or kernel identity violation during enumeration of directory '$dirFull' ($dirId)."
        }
        [void]$dirNodes.Add(@{ Path = $dirFull; ExpectedId = $dirId })

        foreach ($fsi in $currDir.GetFileSystemInfos()) {
            if ([bool]($fsi.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
                throw "Reparse point violation: Descendant path '$($fsi.FullName)' inside '$resolvedRoot' is an NTFS junction or symbolic link."
            }
            $nodeFull = $fsi.FullName
            $nodeId = Get-WibKernelNodeIdentity -LiteralPath $nodeFull
            if (-not $nodeId -or $nodeId.StartsWith('REPARSE:')) {
                throw "Reparse point or kernel identity violation during enumeration of '$nodeFull' ($nodeId)."
            }
            if ($fsi -is [System.IO.DirectoryInfo]) {
                $walkStack.Push($fsi)
            } else {
                [void]$fileNodes.Add(@{ Path = $nodeFull; ExpectedId = $nodeId })
            }
        }
    }

    # 1. Delete leaf files after re-verifying each file's 64-bit NTFS File ID
    foreach ($fNode in $fileNodes) {
        $fPath = $fNode.Path
        if ($OnBeforeNodeDelete) { & $OnBeforeNodeDelete $fPath 'File' }
        if (-not (Test-Path -LiteralPath $fPath)) { continue }
        $currId = Get-WibKernelNodeIdentity -LiteralPath $fPath
        if ($currId -ne $fNode.ExpectedId) {
            throw "TOCTOU node identity mismatch before deleting file '$fPath': expected '$($fNode.ExpectedId)', found '$currId'. Aborting deletion."
        }
        $fItem = Get-Item -LiteralPath $fPath -Force -ErrorAction Stop
        if ([bool]($fItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
            throw "TOCTOU reparse point detected before deleting file '$fPath'."
        }
        if ([bool]($fItem.Attributes -band [System.IO.FileAttributes]::ReadOnly)) {
            $fItem.Attributes = $fItem.Attributes -band (-bnot [System.IO.FileAttributes]::ReadOnly)
        }
        [System.IO.File]::Delete($fPath)
    }

    # 2. Delete directories bottom-up using non-recursive Directory::Delete(path, false)
    for ($idx = $dirNodes.Count - 1; $idx -ge 0; $idx--) {
        $dNode = $dirNodes[$idx]
        $dPath = $dNode.Path
        if ($OnBeforeNodeDelete) { & $OnBeforeNodeDelete $dPath 'Directory' }
        if (-not (Test-Path -LiteralPath $dPath)) { continue }
        $currId = Get-WibKernelNodeIdentity -LiteralPath $dPath
        if ($currId -ne $dNode.ExpectedId) {
            throw "TOCTOU node identity mismatch before deleting directory '$dPath': expected '$($dNode.ExpectedId)', found '$currId'. Aborting deletion."
        }
        $dItem = Get-Item -LiteralPath $dPath -Force -ErrorAction Stop
        if ([bool]($dItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
            throw "TOCTOU reparse point detected before deleting directory '$dPath'."
        }
        if ([bool]($dItem.Attributes -band [System.IO.FileAttributes]::ReadOnly)) {
            $dItem.Attributes = $dItem.Attributes -band (-bnot [System.IO.FileAttributes]::ReadOnly)
        }
        [System.IO.Directory]::Delete($dPath, $false)
    }
}

function Remove-WibImagePaths {
    param($Ctx, [string]$Module, [string[]]$RelPaths)
    $res = @()
    foreach ($rel in $RelPaths) {
        try {
            $full = Assert-WibNoReparsePointsInTree -Path $rel -BaseDir $Ctx.MountDir
            if (-not (Test-Path -LiteralPath $full)) { continue }
            Grant-WibAccess -Path $full -BaseDir $Ctx.MountDir
            # Re-verify containment and perform per-node 64-bit NTFS File ID verified bottom-up deletion (WIB-009)
            Remove-WibConfinedTreeSafe -Path $full -BaseDir $Ctx.MountDir
            $res += (New-WibResult $Module $rel 'applied')
        } catch {
            $res += (New-WibResult $Module $rel 'failed' $_.Exception.Message)
        }
    }
    $res
}

function Test-WibPathsGone {
    param($Ctx, [string]$Module, [string[]]$RelPaths)
    foreach ($rel in $RelPaths) {
        if (Test-Path -LiteralPath (Join-Path $Ctx.MountDir $rel)) { New-WibResult 'verify' "$Module : $rel" 'fail' 'path still present' }
        else { New-WibResult 'verify' "$Module : $rel" 'pass' }
    }
}

# ---------------------------------------------------------------- manifest integrity & signatures
function Protect-WibManifest {
    param(
        [Parameter(Mandatory)][string]$ManifestPath,
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,
        [string]$Thumbprint
    )
    if (-not (Test-Path -LiteralPath $ManifestPath)) { throw "Manifest file not found: $ManifestPath" }

    if (-not $Certificate -and $Thumbprint) {
        $cleanThumb = $Thumbprint.Trim().Replace(' ', '')
        $Certificate = Get-Item "Cert:\CurrentUser\My\$cleanThumb" -ErrorAction SilentlyContinue
        if (-not $Certificate) {
            $Certificate = Get-Item "Cert:\LocalMachine\My\$cleanThumb" -ErrorAction SilentlyContinue
        }
        if (-not $Certificate) {
            throw "Requested signing certificate with thumbprint '$cleanThumb' not found in CurrentUser\My or LocalMachine\My."
        }
    }

    # 1. Detached SHA-256 checksum file (.sha256 = detached checksum)
    $hash = Get-WibSha256 $ManifestPath
    $chkPath = "$ManifestPath.sha256"
    "$hash *$(Split-Path $ManifestPath -Leaf)" | Set-Content -LiteralPath $chkPath -Encoding UTF8
    Write-WibLog "Detached manifest checksum written: $chkPath ($hash)" 'INFO'

    # 2. If certificate provided or requested, sign using detached RSA SHA-256 signature (.sig = detached signature)
    $sigStatus = 'unsigned'
    if ($Certificate) {
        try {
            $bytes = [System.IO.File]::ReadAllBytes($ManifestPath)
            $rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($Certificate)
            if (-not $rsa) {
                throw "Certificate does not contain an accessible RSA private key."
            }
            $sig = $rsa.SignData($bytes, [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
            [System.IO.File]::WriteAllBytes("$ManifestPath.sig", $sig)

            # Self-verify: read the .sig file back and confirm it round-trips through
            # VerifyData before reporting signing success. This catches filesystem
            # write errors and truncation before the caller relies on the signature.
            $sigBytesBack = [System.IO.File]::ReadAllBytes("$ManifestPath.sig")
            $rsaPub = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPublicKey($Certificate)
            if (-not $rsaPub.VerifyData($bytes, $sigBytesBack, [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)) {
                throw "Signature self-verification failed after writing .sig - the written bytes do not verify against the certificate's public key."
            }

            $sigStatus = 'rsa-sha256-detached'
            Write-WibLog "Detached manifest signature written: $ManifestPath.sig ($($Certificate.Subject))" 'INFO'
        } catch {
            throw "Manifest signing failed for certificate $($Certificate.Subject): $($_.Exception.Message)"
        }
    }
    @{ Checksum = $hash; SignatureStatus = $sigStatus }
}

function Test-WibManifest {
    param(
        [Parameter(Mandatory)][string]$ManifestPath,
        [string]$PublicCertPath
    )
    if (-not (Test-Path -LiteralPath $ManifestPath)) { throw "Manifest file not found: $ManifestPath" }

    $chkPath = "$ManifestPath.sha256"
    $hasChecksum = Test-Path -LiteralPath $chkPath
    $checksumValid = $false
    if ($hasChecksum) {
        $expectedLine = (Get-Content -LiteralPath $chkPath -Raw).Trim()
        if ($expectedLine -match '^([0-9a-fA-F]{64})') {
            $expectedHash = $matches[1].ToUpper()
            $actualHash = (Get-WibSha256 $ManifestPath).ToUpper()
            $checksumValid = ($expectedHash -eq $actualHash)
        }
    }

    $sigPath = "$ManifestPath.sig"
    $hasSignature = Test-Path -LiteralPath $sigPath
    $signatureValid = $false
    $signer = ''
    if ($hasSignature -and $PublicCertPath -and (Test-Path -LiteralPath $PublicCertPath)) {
        try {
            $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 ($PublicCertPath)
            $signer = $cert.Subject
            $rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPublicKey($cert)
            $bytes = [System.IO.File]::ReadAllBytes($ManifestPath)
            $sigBytes = [System.IO.File]::ReadAllBytes($sigPath)
            $signatureValid = $rsa.VerifyData($bytes, $sigBytes, [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
        } catch {
            Write-Verbose "Signature verification error: $($_.Exception.Message)"
        }
    }

    @{
        ManifestPath    = $ManifestPath
        HasChecksum     = $hasChecksum
        ChecksumValid   = $checksumValid
        HasSignature    = $hasSignature
        SignatureValid  = $signatureValid
        Signer          = $signer
    }
}

if ($PSScriptRoot -and (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'Hardware.ps1'))) {
    . (Join-Path $PSScriptRoot 'Hardware.ps1')
}
if ($PSScriptRoot -and (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'Compact.ps1'))) {
    . (Join-Path $PSScriptRoot 'Compact.ps1')
}
