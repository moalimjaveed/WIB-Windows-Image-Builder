#Requires -Version 5.1
<#
.SYNOPSIS
    Validates PowerShell 5.1 AST syntax and bans PS 7+ only syntax.
#>
param(
    [string]$Path = '.'
)

$ErrorActionPreference = 'Stop'
Write-Host "[*] Checking PowerShell 5.1 syntax compatibility across: $Path" -ForegroundColor Cyan

$files = Get-ChildItem -Path $Path -Recurse -Filter '*.ps1' | Where-Object {
    $_.FullName -notmatch '\\\.agents\\' -and $_.FullName -notmatch '\\work\\'
}

$errors = 0

foreach ($file in $files) {
    $content = Get-Content -LiteralPath $file.FullName -Raw
    
    # 1. AST Parser test
    $parseErrors = $null
    $tokens = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
    
    if ($parseErrors.Count -gt 0) {
        Write-Host "[!] Parse Error in $($file.FullName):" -ForegroundColor Red
        foreach ($err in $parseErrors) {
            Write-Host "    Line $($err.Extent.StartLineNumber): $($err.Message)" -ForegroundColor Red
        }
        $errors++
    }

    # 2. Check for null-coalescing ?? or ??=
    if ($content -match '\?\?=?') {
        Write-Host "[!] Prohibited null-coalescing operator (?? or ??=) in $($file.FullName)" -ForegroundColor Red
        $errors++
    }

    # 3. Check for ternary ? :
    if ($content -match '\s\?\s[^:]+:\s') {
        Write-Host "[!] Prohibited ternary operator in $($file.FullName)" -ForegroundColor Red
        $errors++
    }

    # 4. Check for ConvertFrom-Json -AsHashtable
    if ($content -match 'ConvertFrom-Json\s+.*-AsHashtable') {
        Write-Host "[!] Prohibited ConvertFrom-Json -AsHashtable in $($file.FullName)" -ForegroundColor Red
        $errors++
    }
}

if ($errors -eq 0) {
    Write-Host "[OK] All checked PowerShell files passed PS 5.1 compatibility checks." -ForegroundColor Green
    exit 0
} else {
    Write-Host "[FAIL] Found $errors compatibility violations." -ForegroundColor Red
    exit 1
}
