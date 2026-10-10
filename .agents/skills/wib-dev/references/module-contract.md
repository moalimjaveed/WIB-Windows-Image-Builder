# WIB Module Contract Reference

Every tweak, feature toggle, removal, or optimization in WIB must be encapsulated in a discrete, self-registering module registered with `Register-WibModule`. Modules reside in `modules/*.ps1`.

## Module Registration Contract

```powershell
Register-WibModule `
    -Id          'copilot-removal' `
    -Description 'Removes Windows Copilot integration, policies, and taskbar shortcuts' `
    -Risk        'low' `
    -Reversibility 'journal' `
    -Tradeoff    'Removes AI assistant pane and shortcuts; frees background resources' `
    -Scope       @('install') `
    -Order       30 `
    -AppliesWhen @{
        Builds   = '>=22621'
        Arch     = @('x64', 'arm64')
        Editions = @('Pro', 'Enterprise', 'Home')
    } `
    -OnError     'log' `
    -Plan        {
        param($Ctx, $Settings)
        # Inspect $Ctx.Scan and return New-WibPlanItem objects
        @(
            New-WibPlanItem -Module 'copilot-removal' -Action 'Policy' `
                -Target 'DisableWindowsCopilot' -Reason 'Disable Copilot UI and features' `
                -Reversibility 'journal' -EstimatedBytes 0
        )
    } `
    -Apply       {
        param($Ctx, $Settings)
        # Execute file-level operations before hive mount if needed
    } `
    -Verify      {
        param($Ctx, $Settings)
        # Run verification checks with hives loaded
        $val = Get-ItemProperty -Path "Registry::HKLM\wib_SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" `
            -Name "TurnOffWindowsCopilot" -ErrorAction SilentlyContinue
        if ($null -ne $val -and $val.TurnOffWindowsCopilot -eq 1) {
            New-WibResult -Module 'copilot-removal' -Item 'Policies\Microsoft\Windows\WindowsCopilot' -Status 'pass' -Detail 'TurnOffWindowsCopilot policy verified'
        } else {
            New-WibResult -Module 'copilot-removal' -Item 'Policies\Microsoft\Windows\WindowsCopilot' -Status 'fail' -Detail 'TurnOffWindowsCopilot policy not set'
        }
    } `
    -Tweaks      @(
        New-WibTweak -Hive SOFTWARE `
            -Path 'Policies\Microsoft\Windows\WindowsCopilot' `
            -Name 'TurnOffWindowsCopilot' `
            -Value 1 `
            -Type DWord
    )
```

## Mandatory Fields and Parameters

| Field | Type | Allowed Values | Description |
|---|---|---|---|
| `Id` | `[string]` | Kebab-case string | Unique module identifier across the catalog |
| `Description` | `[string]` | Text | Clear summary of the module's actions |
| `Risk` | `[string]` | `low`, `medium`, `high` | Operational risk level |
| `Reversibility` | `[string]` | `journal`, `reinstallable`, `permanent` | Three-tier reversibility classification |
| `Tradeoff` | `[string]` | Text | Clear statement of what is gained vs what is lost |
| `Scope` | `[string[]]` | `install`, `boot` | Target image to service (`install.wim`, `boot.wim`) |
| `Order` | `[int]` | `1` to `100` | Sequence priority in pipeline execution |
| `AppliesWhen` | `[hashtable]` | Optional filters | Conditions for image architecture, build, and edition |
| `OnError` | `[string]` | `ignore`, `log`, `halt` | Failure policy if module application fails |

## Reversibility Tiers

1. **`journal`**:
   - The operation modifies registry settings or policy configurations.
   - The previous value is recorded in `journal.json`.
   - Reversible post-install by the WIB Panel restoring previous state.

2. **`reinstallable`**:
   - Component or package removed from the offline image, but restorable on live system.
   - Example: Provisioned AppX packages can be re-acquired from Microsoft Store or DISM online.

3. **`permanent`**:
   - Irreversible file deletion or irreversible component cleanup.
   - Example: `/ResetBase` cleanup, deleting servicing binaries. Requires rebuild to restore.

## Risk Levels

- **`low`**: Stable optimizations with zero negative impact on system stability or Windows Update. Can be enabled in `balanced` profile.
- **`medium`**: Tweaks that disable optional features (e.g. search indexing, Cortana) or background apps. Included in `lean` profile.
- **`high`**: Operations that disable core security components (Windows Defender, SmartScreen, UAC, mitigations). **Never allowed in balanced or lean profiles.** Requires explicit user opt-in via `-AcceptRisk`.
