#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

Describe 'wib-dev Reference and Template Validation' -Tag 'smoke', 'unit' {
    Context 'Reference Files' {
        It 'Contains all 13 required reference documents' {
            $requiredDocs = @(
                'architecture.md',
                'dism.md',
                'wim-esd.md',
                'offline-registry.md',
                'powershell-5.1.md',
                'module-contract.md',
                'checkpoints.md',
                'rollback.md',
                'verification.md',
                'reproducibility.md',
                'testing.md',
                'ci-security.md',
                'hardware-adaptation.md'
            )

            $refDir = Join-Path $PSScriptRoot '../references'
            foreach ($doc in $requiredDocs) {
                Test-Path (Join-Path $refDir $doc) | Should -Be $true
            }
        }
    }

    Context 'Syntax checks' {
        It 'Examples parse cleanly in PowerShell 5.1 AST' {
            $example = Join-Path $PSScriptRoot '../examples/sample-module.ps1'
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile($example, [ref]$null, [ref]$errors)
            $errors.Count | Should -Be 0
        }
    }
}
