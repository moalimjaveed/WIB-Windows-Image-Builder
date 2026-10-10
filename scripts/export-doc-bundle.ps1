# Export documentation and launch files into a single bundle for review
$files = @(
    'README.md',
    'docs\GETTING_STARTED.md',
    'docs\GITHUB_AND_SEO_LAUNCH_CHECKLIST.md',
    'docs\index.html',
    'docs\robots.txt',
    'docs\sitemap.xml',
    'CONTRIBUTING.md',
    'SECURITY.md',
    'CODE_OF_CONDUCT.md',
    'CITATION.cff',
    '.gitignore',
    '.github\ISSUE_TEMPLATE\bug_report.yml',
    '.github\ISSUE_TEMPLATE\feature_request.yml',
    '.github\pull_request_template.md'
)

$root = $PSScriptRoot
if (-not (Test-Path -LiteralPath (Join-Path $root 'README.md'))) {
    $root = (Get-Item -LiteralPath $PSScriptRoot).Parent.FullName
}

$outPath = Join-Path $root 'WIB_DOCUMENTATION_BUNDLE.txt'
$divider = ('=' * 80)
$lines = New-Object System.Collections.Generic.List[string]

$lines.Add($divider)
$lines.Add("WIB DOCUMENTATION & REPOSITORY LAUNCH BUNDLE (v0.2.29)")
$lines.Add("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$lines.Add("Files included: $($files.Count)")
$lines.Add($divider)
$lines.Add("")

foreach ($rel in $files) {
    $full = Join-Path $root $rel
    if (Test-Path -LiteralPath $full) {
        $lines.Add($divider)
        $lines.Add("FILE: $rel")
        $lines.Add("LOCATION: $rel")
        $lines.Add("FULL PATH: $full")
        $lines.Add($divider)
        $content = [System.IO.File]::ReadAllText($full, [System.Text.Encoding]::UTF8)
        $lines.Add($content)
        $lines.Add("")
    } else {
        Write-Warning "File not found: $full"
    }
}

[System.IO.File]::WriteAllLines($outPath, $lines.ToArray(), [System.Text.Encoding]::UTF8)
Write-Output "Successfully generated $outPath with $($files.Count) files."
