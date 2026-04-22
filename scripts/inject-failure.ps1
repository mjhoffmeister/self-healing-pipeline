<#
.SYNOPSIS
    Inject one of the four documented failure scenarios.

.DESCRIPTION
    Each scenario produces a single-file diff that, when committed and pushed,
    causes CI to fail in a known way. Pair with reset-demo.ps1 for a clean undo.

.PARAMETER Scenario
    F1 — lint/format drift (auto-fixable)
    F2 — failing unit test from a code typo (Copilot-eligible)
    F3 — bad Dockerfile build arg (Copilot-eligible, infra-adjacent)
    F4 — broken CI workflow step (proves the agent can fix the pipeline itself)

.EXAMPLE
    ./scripts/inject-failure.ps1 -Scenario F2
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('F1', 'F2', 'F3', 'F4')]
    [string]$Scenario
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $repoRoot

function Edit-File {
    param([string]$Path, [scriptblock]$Transform)
    $full = Join-Path $repoRoot $Path
    if (-not (Test-Path $full)) { throw "Missing file: $Path" }
    $content = Get-Content $full -Raw
    $new = & $Transform $content
    if ($new -eq $content) { throw "Injection produced no change in $Path" }
    # Write bytes directly to preserve the original line-ending and trailing-newline
    # state of the source file. Set-Content (with or without -NoNewline) re-encodes
    # and may add or strip a final newline, producing spurious diff lines beyond
    # the intended injection.
    [System.IO.File]::WriteAllText($full, $new, [System.Text.UTF8Encoding]::new($false))
    Write-Host "  modified $Path" -ForegroundColor Yellow
}

Write-Host "Injecting scenario $Scenario..." -ForegroundColor Cyan

switch ($Scenario) {
    'F1' {
        # Lint/format drift: insert tabs and trailing whitespace in GreetingService.cs.
        Edit-File 'src/Api/GreetingService.cs' {
            param($c)
            $c -replace 'public static string Greet\(string\? name\)\s*\{',
                "public static string Greet(string? name)`r`n    {`r`n`t   var __unused = 0;   "
        }
    }
    'F2' {
        # Failing unit test from a code typo: change "Hello, " to "Helo, ".
        Edit-File 'src/Api/GreetingService.cs' {
            param($c) $c -replace '"Hello, \{trimmed\}!"', '"Helo, {trimmed}!"'
        }
    }
    'F3' {
        # Bad Dockerfile build arg: reference a non-existent SDK tag.
        Edit-File 'Dockerfile' {
            param($c) $c -replace 'ARG DOTNET_SDK_VERSION=10\.0', 'ARG DOTNET_SDK_VERSION=99.0-does-not-exist'
        }
    }
    'F4' {
        # Broken CI workflow step: invalid dotnet-version pin.
        Edit-File '.github/workflows/ci.yml' {
            param($c) $c -replace 'DOTNET_VERSION: "10\.0\.x"', 'DOTNET_VERSION: "99.0.x"'
        }
    }
}

Write-Host ""
Write-Host "Done. Recommended order is branch-FIRST, inject-SECOND, but the change is" -ForegroundColor Green
Write-Host "already in your working tree, so just commit it onto a fresh branch:" -ForegroundColor Green
Write-Host "  git stash                                    # if you weren't already on a fresh branch"
Write-Host "  git checkout main; git pull"
Write-Host "  git checkout -b inject/$Scenario-$(Get-Date -Format yyyyMMdd-HHmmss)"
Write-Host "  git stash pop                                # restore the injected change"
Write-Host "  git diff --stat                              # sanity: should be one file"
Write-Host "  git commit -am 'demo: inject $Scenario'"
Write-Host "  git push -u origin HEAD"
Write-Host "  gh pr create --fill                          # CI will fail; the responder takes over."
