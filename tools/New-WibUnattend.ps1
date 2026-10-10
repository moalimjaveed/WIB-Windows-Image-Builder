#Requires -Version 5.1
<#
.SYNOPSIS
    Generates an offline autounattend.xml file for unattended Windows 11 installation.
    Configures local administrator account, suppresses cloud account prompts, and injects LabConfig bypasses.
    Zero external downloads; 100% offline and PowerShell 5.1 compatible.

.EXAMPLE
    $secPass = Read-Host -Prompt "Enter local administrator password" -AsSecureString
    .\tools\New-WibUnattend.ps1 -OutputPath autounattend.xml -Username "Admin" -SecurePassword $secPass -AutoLogon -AcceptCredentialExposureRisk
#>

[CmdletBinding()]
param(
    [string]$OutputPath = 'autounattend.xml',
    [string]$Username = 'WibUser',
    [System.Security.SecureString]$SecurePassword,
    [object]$Password = '',
    [string]$PasswordHash = '',
    [string]$DisplayName = 'WIB User',
    [switch]$AutoLogon,
    [switch]$HardwareBypass,
    [switch]$SkipHardwareBypass,
    [switch]$ObscurePassword,
    [switch]$PlainTextPassword,
    [switch]$AllowPlaintextCredentials,
    [switch]$AcceptCredentialExposureRisk,
    [switch]$TestOnly,
    [switch]$Force,
    [ValidateSet('amd64', 'arm64')][string]$Arch = 'amd64',
    [string]$TemplatePath
)

$ErrorActionPreference = 'Stop'
$scriptRoot = $PSScriptRoot
$repoRoot = Split-Path -Parent $scriptRoot

if (-not (Get-Command Get-WibSha256 -ErrorAction SilentlyContinue)) {
    $coreLibPath = Join-Path $repoRoot 'lib\Core.ps1'
    if (-not (Test-Path -LiteralPath $coreLibPath -PathType Leaf)) {
        throw "SECURITY ERROR: Required core library '$coreLibPath' is missing; refusing to generate unattended answer file."
    }
    . $coreLibPath
}

$mandatoryAclCmds = @('Test-WibPathContainment', 'Test-WibVolumePersistentAclSupport', 'Protect-WibSensitiveFileAcl', 'Get-WibAclFingerprint', 'Get-WibFileDaclSnapshot', 'Restore-WibFileDaclSnapshot')
$missingAclCmds = @($mandatoryAclCmds | Where-Object { -not (Get-Command $_ -ErrorAction SilentlyContinue) })
if ($missingAclCmds.Count -gt 0) {
    throw "SECURITY ERROR: Mandatory security/ACL helpers ($($missingAclCmds -join ', ')) are unavailable; refusing to generate unattended answer file."
}

# 1. Validate Username and Parameter Contract Consistency
$reservedNames = @('Administrator', 'Guest', 'DefaultAccount', 'WDAGUtilityAccount', 'SYSTEM', 'LOCAL SERVICE', 'NETWORK SERVICE')
if ($reservedNames -contains $Username) {
    throw "Username '$Username' is a reserved Windows system account name and cannot be created as a standard local account."
}
if ($Username -notmatch '^[^"/\\\[\]:;|=,+*?<>@]{1,20}$') {
    throw "Username '$Username' contains invalid characters or exceeds 20 characters (cannot contain `"/\[]:;|=,+*?<>@)."
}
if ($ObscurePassword -and $PlainTextPassword) {
    throw 'Conflicting parameters: -ObscurePassword and -PlainTextPassword cannot be specified together.'
}
$passwordHashBound = $PSBoundParameters.ContainsKey('PasswordHash')
if ($passwordHashBound) {
    $trimmedBoundHash = if ($null -ne $PasswordHash) { $PasswordHash.Trim() } else { '' }
    if ([string]::IsNullOrEmpty($trimmedBoundHash)) {
        throw 'Invalid -PasswordHash format: value cannot be empty or whitespace when -PasswordHash is specified.'
    }
}
if ($passwordHashBound -and ($SecurePassword -or ($null -ne $Password -and [string]$Password -ne ''))) {
    throw 'Conflicting parameters: -PasswordHash cannot be combined with -SecurePassword or -Password.'
}
if ($passwordHashBound -and ($ObscurePassword -or $PlainTextPassword)) {
    throw 'Conflicting parameters: -PasswordHash cannot be combined with -ObscurePassword or -PlainTextPassword.'
}

$fullPath = [System.IO.Path]::GetFullPath($OutputPath)

# WIB-002: Enforce strict test-fixture confinement when -TestOnly is specified.
# -TestOnly is restricted to disposable test fixtures inside the system temporary directory
# and NEVER waives credential-exposure risk gates.
if ($TestOnly) {
    $tempBase = [System.IO.Path]::GetTempPath()
    try {
        $null = Test-WibPathContainment -Path $fullPath -BaseDir $tempBase
    } catch {
        throw "SECURITY ERROR: -TestOnly output path '$fullPath' is outside the system temporary directory '$tempBase'. -TestOnly is restricted to disposable test fixtures in the system temp directory."
    }
}

$parentDir = Split-Path -Parent $fullPath
if (-not $parentDir) { $parentDir = '.' }
if (-not (Test-Path -LiteralPath $parentDir)) {
    New-Item -ItemType Directory -Force -Path $parentDir | Out-Null
    [void](Protect-WibSensitiveDirectoryAcl -Path $parentDir)
}

# WIB-023: Reject reparse points on parent directory across all execution modes
$parentKernelId = Get-WibKernelNodeIdentity -LiteralPath $parentDir
if ($parentKernelId -like 'REPARSE:*') {
    throw "SECURITY ERROR: Parent directory '$parentDir' is a reparse point or junction ($parentKernelId); refusing to generate unattended answer file."
}

if (-not (Test-WibVolumePersistentAclSupport -Path $parentDir)) {
    throw "SECURITY ERROR: Target path '$fullPath' resides on a filesystem volume that does not support persistent NTFS/ReFS ACLs (FILE_PERSISTENT_ACLS). Writing unattended answer files to volumes incapable of enforcing file-level DACLs is forbidden."
}

$plainPassword = ''
$obscuredBytes = $null
$unmanagedUnicodePtr = [IntPtr]::Zero
$aclProtected = $false

try {
    # 2. Extract or Obscure Password Credential (WIB-010: Best-Effort Secret-Lifetime Reduction)
    # When a SecureString is supplied and -PlainTextPassword is NOT requested, we copy UTF-16LE
    # characters directly from unmanaged memory (Marshal.SecureStringToGlobalAllocUnicode) into a
    # mutable byte[] array ($obscuredBytes) and deterministically zero both buffers in finally,
    # avoiding allocating an intermediate plaintext System.String on the .NET managed heap.
    # NOTE ON MANAGED MEMORY LIMITS: The resulting Base64 token ($xmlPasswordValue), the assembled
    # XML string ($rawXml), and any password passed as a plaintext CLI -Password argument are
    # immutable .NET System.String objects whose heap memory cannot be deterministically erased
    # from user-mode PowerShell prior to CLR garbage collection.
    $secureInput = $null
    if ($SecurePassword) {
        $secureInput = $SecurePassword
    } elseif ($Password -is [System.Security.SecureString]) {
        $secureInput = [System.Security.SecureString]$Password
    }

    $hasPasswordCredential = $false
    if ($null -ne $secureInput) {
        if ($secureInput.Length -gt 0) {
            $hasPasswordCredential = $true
            if ($PlainTextPassword) {
                $unmanagedUnicodePtr = [System.Runtime.InteropServices.Marshal]::SecureStringToGlobalAllocUnicode($secureInput)
                try {
                    $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringUni($unmanagedUnicodePtr)
                } finally {
                    if ($unmanagedUnicodePtr -ne [IntPtr]::Zero) {
                        [System.Runtime.InteropServices.Marshal]::ZeroFreeGlobalAllocUnicode($unmanagedUnicodePtr)
                        $unmanagedUnicodePtr = [IntPtr]::Zero
                    }
                }
            } else {
                $unmanagedUnicodePtr = [System.Runtime.InteropServices.Marshal]::SecureStringToGlobalAllocUnicode($secureInput)
                try {
                    $passByteLen = $secureInput.Length * 2
                    $suffixBytes = [System.Text.Encoding]::Unicode.GetBytes('Password')
                    $obscuredBytes = New-Object byte[] ($passByteLen + $suffixBytes.Length)
                    [System.Runtime.InteropServices.Marshal]::Copy($unmanagedUnicodePtr, $obscuredBytes, 0, $passByteLen)
                    [System.Array]::Copy($suffixBytes, 0, $obscuredBytes, $passByteLen, $suffixBytes.Length)
                } finally {
                    if ($unmanagedUnicodePtr -ne [IntPtr]::Zero) {
                        [System.Runtime.InteropServices.Marshal]::ZeroFreeGlobalAllocUnicode($unmanagedUnicodePtr)
                        $unmanagedUnicodePtr = [IntPtr]::Zero
                    }
                }
            }
        }
    } elseif ($null -ne $Password -and [string]$Password -ne '') {
        if (-not ($AllowPlaintextCredentials -or $AcceptCredentialExposureRisk)) {
            throw "SECURITY ERROR: Passing credentials as plaintext CLI arguments is disallowed by default. Pass credentials via -SecurePassword (Read-Host -AsSecureString), or pass -AllowPlaintextCredentials to explicitly acknowledge command-line process/history exposure."
        }
        Write-Warning "SECURITY WARNING: Passing passwords as plaintext strings on the command line exposes credentials to PowerShell history, process enumeration, and system logging. Use -SecurePassword (Read-Host -AsSecureString) instead."
        $plainPassword = [string]$Password
        $hasPasswordCredential = $true
    }

    if ($ObscurePassword -and -not $hasPasswordCredential) {
        throw 'Parameter error: -ObscurePassword requires a password supplied via -SecurePassword or -Password.'
    }
    if ($PlainTextPassword -and -not $hasPasswordCredential) {
        throw 'Parameter error: -PlainTextPassword requires a password supplied via -SecurePassword or -Password.'
    }

    # 3. Credential Exposure Risk Gate (P2-01 & WIB-002: -TestOnly does NOT bypass credential gating)
    $credentialEmbedded = [bool]($passwordHashBound -or $hasPasswordCredential)
    if ($credentialEmbedded -and -not $AcceptCredentialExposureRisk) {
        if ($TestOnly) {
            throw "SECURITY ERROR: -TestOnly does not waive credential exposure risk gates. Pass -AcceptCredentialExposureRisk to explicitly acknowledge that credentials will be persisted in the unattended answer file."
        }
        throw "SECURITY ERROR: Embedding credentials in unattended answer files creates high-risk credential exposure on install media. Pass -AcceptCredentialExposureRisk to explicitly acknowledge that credentials will be persisted on the installation media root, or omit credentials to use interactive/credentialless setup."
    }

    # 4. AutoLogon Risk Gate (WIB-002: -TestOnly does NOT bypass AutoLogon gating)
    if ($AutoLogon) {
        if (-not $AcceptCredentialExposureRisk) {
            if ($TestOnly) {
                throw "SECURITY ERROR: -TestOnly does not waive -AutoLogon credential exposure risk gates. Pass -AcceptCredentialExposureRisk to explicitly confirm risk acceptance."
            }
            throw "SECURITY ERROR: Enabling -AutoLogon embeds credentials into the unattended answer file (autounattend.xml) on the install media, creating credential exposure risk for anyone with read access to the ISO/USB image. Pass -AcceptCredentialExposureRisk to confirm risk acceptance for automated lab or test environments, or omit -AutoLogon to require interactive credential entry."
        }
        Write-Warning "SECURITY NOTICE: -AutoLogon is enabled. Credentials are embedded in autounattend.xml on installation media. While %SystemRoot%\Panther answer files are scrubbed post-setup, the installation media retains these credentials. Rotate credentials after initial setup."
    }

    # 5. Format XML Credential Tokens
    $xmlPasswordValue = ''
    $xmlPlainText = 'true'
    $passwordMode = 'credentialless'

    if ($passwordHashBound) {
        # WIB-015 / WIB-020: Validate pre-calculated unattend hash against Microsoft WSIM UTF-16LE '<password>Password' Base64 format
        $validatedHash = Test-WibUnattendPasswordHash -PasswordHash $PasswordHash
        $xmlPasswordValue = [System.Security.SecurityElement]::Escape($validatedHash)
        $xmlPlainText = 'false'
        $passwordMode = 'hashed'
        Write-Host 'Using pre-hashed unattend credential (<PlainText>false</PlainText>).' -ForegroundColor Gray
    } elseif ($hasPasswordCredential) {
        if ($PlainTextPassword) {
            if (-not ($AllowPlaintextCredentials -or $AcceptCredentialExposureRisk)) {
                throw "Plaintext password storage in unattended answer files creates high-risk credential exposure on install media. Pass -AllowPlaintextCredentials or -AcceptCredentialExposureRisk to acknowledge this risk, or omit -PlainTextPassword to use obscured/hashed credentials."
            }
            $xmlPasswordValue = [System.Security.SecurityElement]::Escape($plainPassword)
            $xmlPlainText = 'true'
            $passwordMode = 'plaintext'
            Write-Warning "SECURITY WARNING: Plaintext password specified for user '$Username'. Plaintext credentials will be readable on the ISO/USB installer media root and in %SystemRoot%\Panther\unattend.xml. Recommended practice: omit -PlainTextPassword to auto-obscure, supply -PasswordHash, or configure credentials post-install."
        } else {
            # Default behavior (or explicit -ObscurePassword): Microsoft unattend password obscuring (<PlainText>false</PlainText>)
            if ($null -eq $obscuredBytes) {
                $obscuredBytes = [System.Text.Encoding]::Unicode.GetBytes($plainPassword + 'Password')
            }
            $xmlPasswordValue = [Convert]::ToBase64String($obscuredBytes)
            $xmlPlainText = 'false'
            $passwordMode = 'obscured'
            Write-Host 'Applied Microsoft unattend password obscuring (<PlainText>false</PlainText>).' -ForegroundColor Gray
            Write-Warning "SECURITY NOTICE: Unattend password obscuring (<PlainText>false</PlainText>) is reversible Base64 obfuscation. Panther files will be purged post-install via SetupComplete.cmd and FirstLogonCommands, but credentials remain on the installation media until explicitly wiped. Recommend rotating administrator credentials after initial setup."
        }
    } else {
        # Blank password (prompt at logon / no initial password)
        $xmlPasswordValue = ''
        $xmlPlainText = 'true'
        $passwordMode = 'credentialless'
    }

    if (-not $TemplatePath) {
        $TemplatePath = Join-Path $repoRoot 'templates\autounattend.template.xml'
    }

    if (-not (Test-Path -LiteralPath $TemplatePath -PathType Leaf)) {
        throw "Unattend template file not found at: $TemplatePath"
    }

    $rawXml = Get-Content -LiteralPath $TemplatePath -Raw -Encoding UTF8

    # Replace architecture tokens if needed
    if ($Arch -ne 'amd64') {
        $rawXml = $rawXml.Replace('processorArchitecture="amd64"', ('processorArchitecture="{0}"' -f $Arch))
    }

    # Replace account tokens
    $rawXml = $rawXml.Replace('__USERNAME__', [System.Security.SecurityElement]::Escape($Username))
    $rawXml = $rawXml.Replace('__DISPLAY_NAME__', [System.Security.SecurityElement]::Escape($DisplayName))
    $rawXml = $rawXml.Replace('__PASSWORD__', $xmlPasswordValue)
    $rawXml = $rawXml.Replace('__PASSWORD_PLAINTEXT__', $xmlPlainText)
    if ($xmlPlainText -eq 'false') {
        $rawXml = $rawXml.Replace('<PlainText>true</PlainText>', '<PlainText>false</PlainText>')
    }

    # Handle AutoLogon
    if ($AutoLogon) {
        $rawXml = $rawXml.Replace('__AUTOLOGON_ENABLED__', 'true')
    } else {
        # Completely strip AutoLogon XML element when disabled to avoid setup warnings and credential leakage
        $rawXml = [System.Text.RegularExpressions.Regex]::Replace($rawXml, '(?s)\s*<AutoLogon>.*?</AutoLogon>', '')
    }

    # Handle HardwareBypass (default: false / opt-in only per safety rule 5)
    $applyBypass = $false
    if ($PSBoundParameters.ContainsKey('HardwareBypass')) {
        $applyBypass = [bool]$HardwareBypass
    }
    if ($SkipHardwareBypass) {
        $applyBypass = $false
    }
    if (-not $applyBypass) {
        # Remove RunSynchronous LabConfig section from windowsPE pass
        $rawXml = [System.Text.RegularExpressions.Regex]::Replace($rawXml, '(?s)\s*<RunSynchronous>.*?</RunSynchronous>', '')
    }

    if ($TestOnly) {
        $fixtureBanner = "<!-- WIB-TEST-ONLY-FIXTURE: DO NOT USE ON PRODUCTION INSTALLATION MEDIA -->`r`n"
        if ($rawXml.StartsWith('<?xml')) {
            $firstNewline = $rawXml.IndexOf("`n")
            if ($firstNewline -ge 0) {
                $rawXml = $rawXml.Substring(0, $firstNewline + 1) + $fixtureBanner + $rawXml.Substring($firstNewline + 1)
            } else {
                $rawXml = $fixtureBanner + $rawXml
            }
        } else {
            $rawXml = $fixtureBanner + $rawXml
        }
    }

    # Validate/create the local parent chain before staging any credential bytes.
    $pathSnapshot = Assert-WibSafeSensitiveOutputPath `
        -Path $fullPath `
        -AllowMissingLeaf `
        -CreateMissingParent `
        -ProtectCreatedDirectories

    $fullPath = $pathSnapshot.Path
    $parentDir = [System.IO.Path]::GetDirectoryName($fullPath)
    $existedBefore = $pathSnapshot.LeafExists

    if (-not (Test-WibVolumePersistentAclSupport -Path $parentDir)) {
        throw "SECURITY ERROR: Target volume cannot enforce persistent ACLs: '$fullPath'."
    }

    if ($existedBefore -and -not $Force) {
        throw "Output file already exists at '$fullPath'. Specify -Force to overwrite the existing answer file."
    }

    $origDestAclSnapshot = $null
    $origDestSha256 = $null
    $origDestKernelId = $pathSnapshot.LeafIdentity
    if ($existedBefore) {
        try {
            $origDestSha256 = Get-WibSha256 -Path $fullPath
            if ([string]::IsNullOrWhiteSpace($origDestSha256)) {
                throw "Get-WibSha256 returned empty digest."
            }
            $origDestAclSnapshot = Get-WibFileDaclSnapshot -LiteralPath $fullPath

            Assert-WibSensitivePathSnapshot -Snapshot $pathSnapshot | Out-Null

            if ((Get-WibSha256 -Path $fullPath) -ine $origDestSha256) {
                throw "Destination bytes changed while original state was being captured."
            }
        } catch {
            throw "Cannot safely overwrite existing answer file '$fullPath': failed to capture original file hash or DACL snapshot before mutation: $($_.Exception.Message)"
        }
    }

    $stagePath = "$fullPath.$([System.Guid]::NewGuid().ToString('N')).tmp"
    $bakPath = "$fullPath.$([System.Guid]::NewGuid().ToString('N')).bak"
    $transactionCommitted = $false
    $newTargetMoveSucceeded = $false
    $stageCreatedKernelId = $null
    $stageSnapshot = $null
    $backupKernelId = $null

    try {
        $stageCreatedKernelId = $null
        $stageCreateStream = $null
        try {
            $stageCreateStream = [System.IO.File]::Open(
                $stagePath,
                [System.IO.FileMode]::CreateNew,
                [System.IO.FileAccess]::ReadWrite,
                [System.IO.FileShare]::None
            )

            $stageCreatedKernelId = [WibKernelPathHelper]::GetKernelNodeIdentityFromHandle(
                $stageCreateStream.SafeFileHandle
            )

            if ([string]::IsNullOrWhiteSpace($stageCreatedKernelId) -or
                $stageCreatedKernelId -like 'REPARSE:*') {
                throw "SECURITY ERROR: Unable to establish staging-file ownership: '$stagePath'."
            }

            $stageCreateStream.Flush($true)
        }
        finally {
            if ($null -ne $stageCreateStream) {
                $stageCreateStream.Dispose()
            }
        }

        $beforeAclId = Get-WibKernelNodeIdentity -LiteralPath $stagePath
        if ($beforeAclId -cne $stageCreatedKernelId) {
            throw "SECURITY ERROR: Staging identity changed before ACL protection: '$stagePath'."
        }

        if (-not (Protect-WibSensitiveFileAcl -Path $stagePath)) {
            throw "SECURITY ERROR: Failed to protect staging file: '$stagePath'."
        }

        $afterAclId = Get-WibKernelNodeIdentity -LiteralPath $stagePath
        if ($afterAclId -cne $stageCreatedKernelId) {
            throw "SECURITY ERROR: Staging identity changed during ACL protection: '$stagePath'."
        }

        $fs = [System.IO.File]::Open($stagePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        try {
            $fsHandleId = [WibKernelPathHelper]::GetKernelNodeIdentityFromHandle($fs.SafeFileHandle)
            if ($fsHandleId -cne $stageCreatedKernelId) {
                throw "SECURITY ERROR: Stage identity changed prior to payload write: '$stagePath'."
            }

            $utf8Encoding = New-Object System.Text.UTF8Encoding -ArgumentList @($true)
            $writer = New-Object System.IO.StreamWriter -ArgumentList $fs, $utf8Encoding
            $writer.Write($rawXml)
            $writer.Flush()
            $fs.Flush($true)
        } finally {
            if ($writer) { $writer.Dispose() }
            if ($fs) { $fs.Dispose() }
        }

        $stageSnapshot = Get-WibValidatedStageSnapshot `
            -Path $stagePath `
            -PayloadKind Xml `
            -RequireSensitiveAcl

        if ($stageSnapshot.KernelIdentity -cne $stageCreatedKernelId) {
            throw "SECURITY ERROR: Staging identity changed between creation and validation: '$stagePath'."
        }

        Assert-WibStagedFileStillMatches -Snapshot $stageSnapshot | Out-Null

        Invoke-WibSensitiveCommitTestHook `
            -Boundary 'BeforeFinalValidation' `
            -StagePath $stagePath `
            -DestinationPath $fullPath

        Assert-WibSensitivePathSnapshot -Snapshot $pathSnapshot | Out-Null
        Assert-WibStagedFileStillMatches -Snapshot $stageSnapshot | Out-Null

        if ($existedBefore) {
            if ((Get-WibKernelNodeIdentity -LiteralPath $fullPath) -cne $origDestKernelId) {
                throw "SECURITY ERROR: TOCTOU identity mismatch on destination file '$fullPath' before replacement."
            }

            if ((Get-WibSha256 -Path $fullPath) -ine $origDestSha256) {
                throw "SECURITY ERROR: Existing destination bytes changed before replacement: '$fullPath'."
            }

            $preReplaceAclOk = [bool](Protect-WibSensitiveFileAcl -Path $fullPath)
            if (-not $preReplaceAclOk) {
                throw "Protect-WibSensitiveFileAcl returned false when securing existing target file '$fullPath' prior to replacement."
            }

            Assert-WibSensitivePathSnapshot -Snapshot $pathSnapshot | Out-Null
            Assert-WibStagedFileStillMatches -Snapshot $stageSnapshot | Out-Null

            Invoke-WibSensitiveCommitTestHook `
                -Boundary 'AfterFinalValidationBeforeReplace' `
                -StagePath $stagePath `
                -DestinationPath $fullPath

            Invoke-WibFileReplace `
                -SourcePath $stagePath `
                -DestinationPath $fullPath `
                -BackupPath $bakPath `
                -ExpectedDestinationIdentity $origDestKernelId `
                -ExpectedDestinationSha256 $origDestSha256

            if (Test-Path -LiteralPath $bakPath -PathType Leaf) {
                $backupKernelId = Get-WibKernelNodeIdentity -LiteralPath $bakPath
                $backupSha = Get-WibSha256 -Path $bakPath

                if ([string]::IsNullOrWhiteSpace($backupKernelId) -or
                    $backupKernelId -like 'REPARSE:*') {
                    throw "CRITICAL: Invalid replacement backup identity: '$bakPath'."
                }

                if ($backupSha -ine $origDestSha256) {
                    throw "CRITICAL: Original answer-file backup integrity mismatch: '$bakPath'."
                }
            }
        } else {
            Assert-WibSensitivePathSnapshot -Snapshot $pathSnapshot | Out-Null
            Assert-WibStagedFileStillMatches -Snapshot $stageSnapshot | Out-Null

            Invoke-WibSensitiveCommitTestHook `
                -Boundary 'AfterFinalValidationBeforeNewTargetMove' `
                -StagePath $stagePath `
                -DestinationPath $fullPath

            Invoke-WibSensitiveCommitTestHook `
                -Boundary 'ImmediatelyBeforeNewTargetMove' `
                -StagePath $stagePath `
                -DestinationPath $fullPath

            [System.IO.File]::Move($stagePath, $fullPath)
            $newTargetMoveSucceeded = $true
        }

        $committedIdentity = Get-WibKernelNodeIdentity -LiteralPath $fullPath
        $committedSha = Get-WibSha256 -Path $fullPath

        if ($committedIdentity -cne $stageSnapshot.KernelIdentity) {
            throw "SECURITY ERROR: Answer-file destination identity differs from validated stage: '$fullPath'."
        }

        if ($committedSha -ine $stageSnapshot.Sha256) {
            throw "SECURITY ERROR: Answer-file destination differs from validated stage bytes: '$fullPath'."
        }

        $aclProtected = [bool](Protect-WibSensitiveFileAcl -Path $fullPath)
        if (-not $aclProtected) {
            throw "Protect-WibSensitiveFileAcl returned false for target file '$fullPath'."
        }

        $postXmlText = [System.IO.File]::ReadAllText($fullPath, [System.Text.Encoding]::UTF8)
        $null = [xml]$postXmlText

        # TRANSACTION COMMITTED: Target answer file is verified and committed
        $transactionCommitted = $true

        if (Test-Path -LiteralPath $bakPath -PathType Leaf) {
            $backupCleanup = Complete-WibBackupCleanup `
                -Path $bakPath `
                -ExpectedIdentity $backupKernelId `
                -ExpectedSha256 $origDestSha256 `
                -Sensitive `
                -Outcome Committed

            $script:WibLastFileTransactionStatus = $backupCleanup
            $global:WibLastFileTransactionStatus = $backupCleanup
        }
    } catch {
        $primaryErrMsg = $_.Exception.Message

        if (Test-Path -LiteralPath $stagePath) {
            try {
                if (-not [string]::IsNullOrWhiteSpace($stageCreatedKernelId)) {
                    Remove-WibOwnedFileIfMatches `
                        -Path $stagePath `
                        -ExpectedIdentity $stageCreatedKernelId
                }
                else {
                    Write-Warning "Unowned staging artifact preserved for manual review: '$stagePath'."
                }
            } catch {
                Write-Warning "Staging cleanup failed; artifact preserved: '$stagePath'. $($_.Exception.Message)"
            }
        }

        if ($transactionCommitted) {
            Write-Warning "Post-commit warning on '$fullPath': $primaryErrMsg"
        } elseif ($existedBefore) {
            $rollbackErr = $null
            try {
                $currentDestinationId = Get-WibKernelNodeIdentity -LiteralPath $fullPath
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
                    [System.IO.File]::Copy($bakPath, $fullPath, $true)
                } elseif (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
                    throw "CRITICAL ROLLBACK FAILURE: Target answer file is missing and original backup is missing at '$bakPath'."
                }
                Restore-WibFileDaclSnapshot -LiteralPath $fullPath -Snapshot $origDestAclSnapshot

                if ((Get-WibSha256 -Path $fullPath) -ine $origDestSha256) {
                    throw "CRITICAL ROLLBACK FAILURE: Restored answer-file content does not match the original."
                }

                if ((Get-WibAclFingerprint -Path $fullPath) -ine $origDestAclSnapshot.Fingerprint) {
                    throw "CRITICAL ROLLBACK FAILURE: Restored answer-file DACL does not match the original."
                }

                if (-not [string]::IsNullOrWhiteSpace($origDestAclSnapshot.OwnerSid)) {
                    $rollbackOwner = Get-WibPathOwnerSid -Path $fullPath
                    if ($rollbackOwner -ine $origDestAclSnapshot.OwnerSid) {
                        throw "CRITICAL ROLLBACK FAILURE: Restored answer-file owner '$rollbackOwner' does not match original '$($origDestAclSnapshot.OwnerSid)'."
                    }
                }
            } catch {
                $rollbackErr = $_.Exception.Message
            }

            if ($null -ne $rollbackErr) {
                throw "CRITICAL ROLLBACK FAILURE on '$fullPath' (backup preserved at '$bakPath'): primary error: [$primaryErrMsg]; rollback error: [$rollbackErr]"
            }

            if (Test-Path -LiteralPath $bakPath -PathType Leaf) {
                $backupCleanup = Complete-WibBackupCleanup `
                    -Path $bakPath `
                    -ExpectedIdentity $backupKernelId `
                    -ExpectedSha256 $origDestSha256 `
                    -Sensitive `
                    -Outcome RolledBack

                $script:WibLastFileTransactionStatus = $backupCleanup
                $global:WibLastFileTransactionStatus = $backupCleanup
            }

            throw "Failed unattended answer file write to '$fullPath' (prior file and permissions restored and verified): $primaryErrMsg"
        } else {
            if ($newTargetMoveSucceeded -and $null -ne $stageSnapshot) {
                try {
                    Remove-WibOwnedFileIfMatches `
                        -Path $fullPath `
                        -ExpectedIdentity $stageSnapshot.KernelIdentity `
                        -ExpectedSha256 $stageSnapshot.Sha256
                }
                catch {
                    throw "CRITICAL OWNERSHIP FAILURE on '$fullPath': primary error: [$primaryErrMsg]; cleanup error: [$($_.Exception.Message)]. The destination was preserved."
                }
            }

            throw "Failed unattended answer file write to '$fullPath': $primaryErrMsg"
        }
    }
} finally {
    if ($unmanagedUnicodePtr -ne [IntPtr]::Zero) {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeGlobalAllocUnicode($unmanagedUnicodePtr)
        $unmanagedUnicodePtr = [IntPtr]::Zero
    }
    if ($null -ne $obscuredBytes -and $obscuredBytes.Length -gt 0) {
        [Array]::Clear($obscuredBytes, 0, $obscuredBytes.Length)
    }
    $plainPassword = $null
    $xmlPasswordValue = $null
}

Write-Host "Generated offline autounattend answer file: $fullPath" -ForegroundColor Green
Write-Host "  Architecture   : $Arch" -ForegroundColor Gray
Write-Host "  Local Account  : $Username" -ForegroundColor Gray
Write-Host "  Password Mode  : $passwordMode" -ForegroundColor Gray
Write-Host "  AutoLogon      : $(if ($AutoLogon) { 'Enabled' } else { 'Disabled (Element Stripped)' })" -ForegroundColor Gray
Write-Host "  Hardware Bypass: $(if ($applyBypass) { 'Enabled (LabConfig)' } else { 'Disabled' })" -ForegroundColor Gray

return [PSCustomObject]@{
    OutputPath                   = $fullPath
    Username                     = $Username
    PasswordMode                 = $passwordMode
    ObscurePassword              = [bool]($passwordMode -eq 'obscured')
    AutoLogon                    = [bool]$AutoLogon
    AcceptCredentialExposureRisk = [bool]$AcceptCredentialExposureRisk
    TestOnly                     = [bool]$TestOnly
    AclProtected                 = [bool]$aclProtected
    HardwareBypass               = $applyBypass
    ForceOverwrite               = [bool]$Force
    Architecture                 = $Arch
}
