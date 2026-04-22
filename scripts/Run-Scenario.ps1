<#
.SYNOPSIS
    Fire off a single self-healing demo scenario in one command.

.DESCRIPTION
    Wraps the full local sequence:
      1. verify-clean       (refuses to run if the repo isn't at demo-baseline)
      2. branch off main    (inject/<Scenario>-<timestamp>)
      3. inject the failure
      4. commit + push
      5. gh pr create

    After this exits, the responder workflow takes over server-side: a tracking
    issue appears within ~2 min, Copilot is assigned, and a fix PR follows.

    Use -DryRun to see what would happen without touching the remote.
    Use -SkipVerify to skip the pre-flight (e.g. for re-runs while iterating).

.PARAMETER Scenario
    F1 | F2 | F3 | F4 — see DEMO.md for what each one breaks.

.PARAMETER DryRun
    Print every command but do not push or open a PR.

.PARAMETER SkipVerify
    Skip the verify-clean pre-flight.

.PARAMETER NoPr
    Push the branch but do not open a PR (useful when you want to inspect first).

.EXAMPLE
    pwsh ./scripts/Run-Scenario.ps1 -Scenario F2

.EXAMPLE
    pwsh ./scripts/Run-Scenario.ps1 -Scenario F4 -DryRun
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('F1', 'F2', 'F3', 'F4')]
    [string]$Scenario,

    [switch]$DryRun,
    [switch]$SkipVerify,
    [switch]$NoPr
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $repoRoot

function Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Run([string]$Cmd) {
    Write-Host "    $Cmd" -ForegroundColor DarkGray
    if ($DryRun) { return }
    Invoke-Expression $Cmd
    if ($LASTEXITCODE -ne 0) { throw "Command failed (exit $LASTEXITCODE): $Cmd" }
}

# Sanity checks
foreach ($tool in 'git', 'gh') {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "$tool not found on PATH."
    }
}

# 1. Pre-flight
if (-not $SkipVerify) {
    Step "Pre-flight: verify-clean"
    if ($DryRun) {
        Write-Host "    pwsh ./scripts/verify-clean.ps1 (skipped in dry-run)" -ForegroundColor DarkGray
    }
    else {
        & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'verify-clean.ps1')
        if ($LASTEXITCODE -ne 0) {
            throw "verify-clean failed. Run scripts/reset-demo.ps1 (or rerun with -SkipVerify if you really mean it)."
        }
    }
}
else {
    Step "Pre-flight: skipped (-SkipVerify)"
}

# 2. Branch off main
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$branch = "inject/$Scenario-$timestamp"
Step "Creating branch $branch from origin/main"
Run "git fetch origin main --quiet"
Run "git checkout -B `"$branch`" origin/main"

# 3. Inject
Step "Injecting scenario $Scenario"
if ($DryRun) {
    Write-Host "    pwsh ./scripts/inject-failure.ps1 -Scenario $Scenario (skipped in dry-run)" -ForegroundColor DarkGray
}
else {
    & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'inject-failure.ps1') -Scenario $Scenario
    if ($LASTEXITCODE -ne 0) { throw "inject-failure.ps1 failed (exit $LASTEXITCODE)" }
}

# Confirm exactly one file changed
if (-not $DryRun) {
    $changed = @((git diff --name-only) -split "`n" | Where-Object { $_ })
    if ($changed.Count -ne 1) {
        throw "Expected exactly one changed file after injection, got $($changed.Count): $($changed -join ', ')"
    }
    Step "Modified: $($changed[0])"
}

# 4. Commit + push
$msg = "demo: inject $Scenario"
Step "Committing and pushing"
Run "git commit -am `"$msg`""
Run "git push -u origin `"$branch`""

# 5. PR
if ($NoPr) {
    Step "Skipping PR creation (-NoPr). Branch pushed: $branch"
    return
}

Step "Opening PR"
$prTitle = "demo: $Scenario injection"
$prBody = @"
Automated demo injection of scenario **$Scenario**.

CI is expected to fail. Within ~2 min, the self-heal responder will:
1. Open a tracking issue labelled ``self-heal``.
2. Assign it to **@Copilot**.
3. Copilot opens a fix PR titled ``Fixes #N``.

When the fix PR's CI is green, squash-merge it (the separation-of-duties check confirms author ≠ merger). Then close this PR.

See DEMO.md for the full timeline.
"@

if ($DryRun) {
    Write-Host "    gh pr create --title `"$prTitle`" --body <...> --label demo,self-heal-injection" -ForegroundColor DarkGray
}
else {
    $tmp = New-TemporaryFile
    Set-Content -Path $tmp -Value $prBody -NoNewline
    try {
        & gh pr create --title $prTitle --body-file $tmp --label demo --label "self-heal-injection"
        if ($LASTEXITCODE -ne 0) { throw "gh pr create failed (exit $LASTEXITCODE)" }
    }
    finally {
        Remove-Item $tmp -ErrorAction SilentlyContinue
    }
}

Write-Host ""
Step "Done. Watch for the tracking issue and Copilot's fix PR."
Write-Host "  gh issue list --label self-heal --state open"
Write-Host "  gh pr list --state open"
