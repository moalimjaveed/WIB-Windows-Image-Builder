# Reproducibility Reference

## The Core Principle

```
Input ISO (SHA-256) + Resolved Profile (SHA-256) + Tool Version + Pinned Dependencies = Deterministic Build
```

A core goal of WIB is reproducible builds. Given the same inputs, repeated builds should produce the exact same outcome wherever deterministic reproduction is technically possible on Windows.

## Eliminating Non-Deterministic Sources

| Leak Source | How It Breaks Determinism | WIB Remediation |
|---|---|---|
| **Timestamps** | Every file write updates `LastWriteTime`, changing WIM hash | Set static timestamps or normalize file times before WIM export |
| **Random GUIDs / Temp Paths** | Machine-specific paths leaked into unattend or registry | Use normalized relative paths (`work\mount`) and predictable keys |
| **Unordered Enumeration** | `Get-ChildItem` returns files in filesystem order (non-deterministic) | Always pipe file enumeration through `Sort-Object FullName` |
| **Profile Inheritance** | Hashing only child profile ignores parent profile changes | Hash the fully resolved (merged) profile using canonical JSON |
| **Tool Versions** | Varying DISM / oscdimg versions generate different headers | Record DISM version and oscdimg SHA-256 in `manifest.json` |

## Canonical Profile Hashing

When profiles use `extends` (e.g. `lean` extending `balanced`), hashing `lean.json` misses modifications to `balanced.json`.

WIB merges the entire profile inheritance chain, converts the resulting hashtable to sorted canonical JSON, and hashes that:

```powershell
function Get-WibCanonicalProfileHash {
    param([hashtable]$ResolvedProfile)

    # Convert hashtable to ordered representation with sorted keys
    $canonicalJson = ConvertTo-WibCanonicalJson -Data $ResolvedProfile
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($canonicalJson)
    $hasher = [System.Security.Cryptography.SHA256]::Create()
    $hash = [System.BitConverter]::ToString($hasher.ComputeHash($bytes)) -replace '-'
    return $hash.ToLowerInvariant()
}
```

## oscdimg Deterministic ISO Mastering

When calling `oscdimg.exe`, supply the `-t` parameter to fix timestamps across all mastered filesystem entries:

```
oscdimg -m -o -u2 -udfver102 -t01/01/2026,00:00:00 -lWIB_WIN11 ...
```

- `-t<mm/dd/yyyy,hh:mm:ss>`: Forces uniform timestamps on all files and directories in the ISO image.
- `-o`: Encodes duplicate files once to optimize storage deterministically.

## Documenting Unavoidable Non-Determinism

Windows and DISM incorporate certain host-specific non-determinisms (such as internal filesystem cluster allocation order or servicing stack transaction logs). 

**Rule:** Never falsely claim bit-for-bit ISO hash matching if Windows/DISM internals introduce variance. Document the exact scope of determinism:
- The package list, registry state, manifest, and installed features are 100% deterministic and verifiable.
- File system timestamps and directory structures are normalized.
- Any residual hash drift is attributed and documented in the build report.
