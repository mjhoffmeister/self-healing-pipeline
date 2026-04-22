<#
.SYNOPSIS
    Pre-flight check that the repo is in a clean demo state.

.DESCRIPTION
    Exits 0 only when:
      - working tree is clean
      - HEAD == origin/main == demo-baseline tag
      - no open self-heal issues
      - no copilot/* or self-heal/* branches on origin
      - metrics/self-heal-events.jsonl is empty
#>
[CmdletBinding()]
param(
    [string]$BaselineTag = 'demo-baseline'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $repoRoot

$problems = @()
function Fail($msg) { $script:problems += $msg; Write-Host "  FAIL: $msg" -ForegroundColor Red }
function Pass($msg) { Write-Host "  ok:   $msg" -ForegroundColor Green }

Write-Host "Verifying clean demo state..." -ForegroundColor Cyan

# Working tree
if (git status --porcelain) { Fail "working tree is dirty" } else { Pass "working tree clean" }

# Branch == main
$branch = (git rev-parse --abbrev-ref HEAD).Trim()
if ($branch -ne 'main') { Fail "current branch is '$branch', expected 'main'" } else { Pass "on main" }

# HEAD matches baseline tag
git fetch origin --tags --force | Out-Null
$head = (git rev-parse HEAD).Trim()
$tagSha = (git rev-list -n 1 $BaselineTag 2>$null).Trim()
if (-not $tagSha) { Fail "tag '$BaselineTag' not found" }
elseif ($head -ne $tagSha) { Fail "HEAD ($head) != $BaselineTag ($tagSha)" }
else { Pass "HEAD == $BaselineTag" }

# Origin/main matches
$originMain = (git rev-parse origin/main).Trim()
if ($originMain -ne $head) { Fail "origin/main ($originMain) != HEAD" } else { Pass "origin/main == HEAD" }

# Open self-heal issues
$open = gh issue list --label self-heal --state open --json number --jq '.[].number'
if ($open) { Fail "open self-heal issues: $($open -join ', ')" } else { Pass "no open self-heal issues" }

# Stray branches on origin
git fetch --prune origin | Out-Null
$stray = git branch -r | ForEach-Object { $_.Trim() } |
    Where-Object { $_ -match '^origin/(copilot/|self-heal/)' }
if ($stray) { Fail "stray branches on origin: $($stray -join ', ')" } else { Pass "no copilot/* or self-heal/* branches" }

# Metrics file empty
$m = Join-Path $repoRoot 'metrics/self-heal-events.jsonl'
if ((Test-Path $m) -and ((Get-Item $m).Length -gt 0)) {
    Fail "metrics/self-heal-events.jsonl is non-empty"
}
else { Pass "metrics file empty" }

if ($problems.Count -gt 0) {
    Write-Host ""
    Write-Host "verify-clean FAILED ($($problems.Count) problem(s)). Run scripts/reset-demo.ps1." -ForegroundColor Red
    exit 1
}
Write-Host ""
Write-Host "verify-clean OK — repo is at $BaselineTag and ready to demo." -ForegroundColor Green
exit 0
