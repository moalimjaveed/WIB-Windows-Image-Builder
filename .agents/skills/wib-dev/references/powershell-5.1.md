# Windows PowerShell 5.1 Compatibility Reference

## Target Runtime

The primary deployment and development target for WIB is **Windows PowerShell 5.1** (the default built-in runtime on Windows 10/11 and Windows Server). While code should be clean enough to also run under PowerShell 7+ (`pwsh`), scripts must never rely on PowerShell 7 features or syntax.

## Prohibited Syntax and Required 5.1 Replacements

| Prohibited PS 7+ Syntax | Why Forbidden | Required 5.1 Equivalent |
|---|---|---|
| **Ternary Operator**<br>`$x = $a ? $b : $c` | Parser syntax error in 5.1 | `if ($a) { $x = $b } else { $x = $c }` |
| **Null-Coalescing Operator**<br>`$x = $a ?? $b` | Parser syntax error in 5.1 | `if ($null -ne $a) { $x = $a } else { $x = $b }` |
| **Null-Coalescing Assignment**<br>`$x ??= $y` | Parser syntax error in 5.1 | `if ($null -eq $x) { $x = $y }` |
| **Chain Operators**<br>`cmd1 && cmd2 \|\| cmd3` | Parser syntax error in 5.1 | Run sequentially; inspect `$LASTEXITCODE` or `$?` |
| **`ConvertFrom-Json -AsHashtable`** | Parameter `-AsHashtable` does not exist in 5.1 | Use custom `ConvertTo-WibHashtable` recursive converter |
| **`ForEach-Object -Parallel`** | Parallel switch does not exist in 5.1 | Use standard sequential `foreach` or runspace pools if strictly required |
| **`[System.IO.Path]::Join(...)`** | Method overload does not exist in .NET Framework 4.8 | Use `Join-Path -Path $a -ChildPath $b` |
| **`Get-Error`** | Cmdlet not present in 5.1 | Inspect `$Error[0]` or `$_.Exception` |
| **`$PSStyle`** | ANSI escape object not present in 5.1 | Use `Write-Host -ForegroundColor` or standard strings |
| **Complex interpolation with `??`**<br>`"$($obj.Val ?? 'default')"` | Crashes parser in 5.1 | Extract logic into explicit variable before string interpolation |

## Operator Parenthesization Rules

In Windows PowerShell 5.1, logical operators `-and` / `-or` combined with cmdlets without parentheses cause argument parsing ambiguities:

```powershell
# BAD — causes syntax or argument evaluation errors
if (Test-Path $file -or Test-Path $alt) { ... }

# GOOD — explicitly parenthesize each expression
if ((Test-Path -LiteralPath $file) -or (Test-Path -LiteralPath $alt)) { ... }
```

## JSON Operations and Depth

PowerShell 5.1 `ConvertTo-Json` defaults to a `-Depth` of 2, which truncates complex objects into string placeholders without warning:

```powershell
# BAD — silently truncates nested data structures
$json = $data | ConvertTo-Json

# GOOD — always supply explicit -Depth
$json = $data | ConvertTo-Json -Depth 10
```

## UTF-8 and Character Encoding

- **No Unicode Emojis in Source Files**: Emojis cause encoding corruptions when scripts are executed in consoles using legacy OEM codepages (e.g. CP437). Use ASCII indicators: `[OK]`, `[!]`, `[WARN]`, `[INFO]`.
- **Files Saved as UTF-8 without BOM**: PowerShell 5.1 `Set-Content` defaults to ASCII/ANSI. When writing UTF-8 output, always pass `-Encoding UTF8`.

## Native Process Invocation

In PowerShell 5.1, `$?` does not accurately reflect non-zero exit codes of native console executables:

```powershell
# BAD
& dism.exe /Image:$mount /Cleanup-Image /StartComponentCleanup
if (-not $?) { throw "DISM failed" }

# GOOD
& dism.exe /Image:$mount /Cleanup-Image /StartComponentCleanup
if ($LASTEXITCODE -ne 0) {
    throw "DISM execution failed with exit code $LASTEXITCODE"
}
```

## Script Boilerplate for WIB Files

Every `.ps1` file in WIB should begin with:

```powershell
#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
```
