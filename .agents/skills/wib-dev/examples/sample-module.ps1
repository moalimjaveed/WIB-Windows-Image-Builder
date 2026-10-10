#Requires -Version 5.1
<#
.SYNOPSIS
    Sample reference module demonstrating the WIB module contract.
#>

Register-WibModule `
    -Id          'sample-telemetry-disable' `
    -Description 'Demonstrates standard declarative registry tweaks and verification.' `
    -Risk        'low' `
    -Reversibility 'journal' `
    -Tradeoff    'Disables diagnostic data collection; reduces background telemetry network traffic.' `
    -Scope       @('install') `
    -Order       20 `
    -AppliesWhen @{
        Builds   = '>=22000'
        Arch     = @('x64', 'arm64')
        Editions = @('Pro', 'Enterprise', 'Home')
    } `
    -OnError     'log' `
    -Plan        {
        param($Ctx, $Settings)
        @(
            New-WibPlanItem -Module 'sample-telemetry-disable' -Action 'Policy' `
                -Target 'AllowTelemetry = 0' -Reason 'Disable diagnostic data collection' `
                -Reversibility 'journal' -EstimatedBytes 0
        )
    } `
    -Apply       {
        param($Ctx, $Settings)
        # Any file or package-level actions performed here
    } `
    -Verify      {
        param($Ctx, $Settings)
        $key = 'Registry::HKLM\wib_SOFTWARE\Policies\Microsoft\Windows\DataCollection'
        $val = Get-ItemProperty -Path $key -Name 'AllowTelemetry' -ErrorAction SilentlyContinue
        if ($null -ne $val -and $val.AllowTelemetry -eq 0) {
            New-WibResult -Module 'sample-telemetry-disable' -Item 'AllowTelemetry' -Status 'pass' -Detail 'AllowTelemetry is set to 0'
        } else {
            New-WibResult -Module 'sample-telemetry-disable' -Item 'AllowTelemetry' -Status 'fail' -Detail 'AllowTelemetry is not 0'
        }
    } `
    -Tweaks      @(
        New-WibTweak -Hive SOFTWARE `
            -Path 'Policies\Microsoft\Windows\DataCollection' `
            -Name 'AllowTelemetry' `
            -Value 0 `
            -Type DWord
    )
