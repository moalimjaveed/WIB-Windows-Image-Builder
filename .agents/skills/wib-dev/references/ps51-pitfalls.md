# PowerShell 5.1 vs 7 Pitfalls — WIB Reference

WIB targets Windows PowerShell 5.1. Every script must parse and behave correctly
under `powershell.exe` (5.1), not just `pwsh` (7+).

---

## Forbidden syntax (5.1 has no support)

| Pattern | PS7 | PS5.1 fix |
|---|---|---|
| Ternary `$x = $a ? $b : $c` | ✅ | `if ($a) { $x = $b } else { $x = $c }` |
| Null-coalescing `$x ?? $y` | ✅ | `if ($null -eq $x) { $y } else { $x }` |
| Null-coalescing assign `$x ??= $y` | ✅ | `if ($null -eq $x) { $x = $y }` |
| `ConvertFrom-Json -AsHashtable` | ✅ | `ConvertTo-WibHashtable` (Core.ps1) |
| `ForEach-Object -Parallel` | ✅ | Sequential `foreach` |
| `[System.IO.Path]::Join(...)` with 3+ args | ✅ | `Join-Path` |
| Pipeline chain operators `&&` / `\|\|` | ✅ | Separate statements + `$LASTEXITCODE` check |
| `Get-Error` | ✅ | `$Error[0]` |
| `$PSStyle` | ✅ | Not available in 5.1 |

## String interpolation traps

```powershell
# BAD — can hide a null-coalescing operator inside a string:
"$($hash['key'] ?? 'default')"

# GOOD
$val = if ($null -eq $hash['key']) { 'default' } else { $hash['key'] }
"$val"
```

## Hashtable iteration order

`@{}` is unordered in both versions, but output order differs. Use `[ordered]@{}` when
order matters (e.g. manifest.json top-level keys, plan display order).

## Out-Null vs $null =

Both work in 5.1 and 7. Prefer `| Out-Null` for cmdlets that return pipeline objects;
prefer `$null = ` for assignments that produce output (slightly faster).

## Exit codes and native commands

```powershell
& dism.exe /Export-Image ...
if ($LASTEXITCODE -ne 0) { throw "dism failed ($LASTEXITCODE)" }
```

Never rely on `$?` for native executables — use `$LASTEXITCODE`.

## reg.exe output

`reg.exe load` and `reg.exe unload` write to stdout AND stderr. Redirect both:
```powershell
& reg.exe load "HKLM\wib_SOFTWARE" $file 2>&1 | Out-Null
```

## Encoding

Write all source files as UTF-8 **without BOM** for 5.1 compatibility.
`Set-Content` and `Add-Content` default to system encoding in 5.1.
Always pass `-Encoding UTF8` when writing files that contain non-ASCII.

```powershell
Set-Content -LiteralPath $path -Value $text -Encoding UTF8
```

## Type acceleration differences

`[pscustomobject]` works in both. `[ordered]` works in both (PS3+).
Avoid `[psmoduleinfo]`, `[runspacefactory]`, and other advanced type accelerators.

## Approved verbs

PSScriptAnalyzer enforces approved verbs. Use `Get-Verb` to check.
Common WIB verbs that are approved: `Get`, `Set`, `New`, `Remove`, `Import`,
`Export`, `Test`, `Invoke`, `Write`, `Show`, `Save`, `Mount`, `Dismount`,
`Register`, `Resolve`, `Grant`.

Not approved: `Fetch`, `Download`, `Build` (use `Invoke-WibBuild`).
