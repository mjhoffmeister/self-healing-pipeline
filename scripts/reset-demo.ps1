<#
.SYNOPSIS
    Reset the demo repo to the demo-baseline tag, locally and remotely.

.DESCRIPTION
    Idempotent. Closes self-heal issues, deletes copilot/* and self-heal/* branches,
    deletes stale ghcr.io demo image tags (best-effort), resets main to the
    demo-baseline tag, and clears metrics/self-heal-events.jsonl.

    Requires:
      - gh (authenticated against the demo repo)
      - git (clean working tree)

.PARAMETER BaselineTag
    Git tag to reset main to. Defaults to 'demo-baseline'.

.PARAMETER SkipImageDelete
    Skip GHCR image cleanup (useful when running offline).
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$BaselineTag = 'demo-baseline',
    [switch]$SkipImageDelete
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $repoRoot

function Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Ok($msg)   { Write-Host "  ok: $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "  warn: $msg" -ForegroundColor Yellow }

# Sanity checks
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw "gh CLI not found on PATH." }
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw "git not found on PATH." }

$status = git status --porcelain
if ($status) { throw "Working tree is dirty. Commit or stash before resetting." }

$repoSlug = (gh repo view --json nameWithOwner --jq .nameWithOwner).Trim()
Step "Repo: $repoSlug"

# 1. Close open self-heal issues
Step "Closing open self-heal issues"
$issues = gh issue list --label self-heal --state open --json number --jq '.[].number'
foreach ($n in $issues) {
    if ($PSCmdlet.ShouldProcess("issue #$n", "close")) {
        gh issue close $n --comment "Closed by reset-demo." | Out-Null
        Ok "closed #$n"
    }
}
if (-not $issues) { Ok "no open self-heal issues" }

# 2. Delete remote copilot/* and self-heal/* branches
Step "Deleting remote copilot/* and self-heal/* branches"
git fetch --prune origin | Out-Null
$branches = git branch -r | ForEach-Object { $_.Trim() } |
    Where-Object { $_ -match '^origin/(copilot/|self-heal/)' } |
    ForEach-Object { $_ -replace '^origin/', '' }
foreach ($b in $branches) {
    if ($PSCmdlet.ShouldProcess("origin/$b", "delete")) {
        git push origin --delete $b 2>$null | Out-Null
        Ok "deleted $b"
    }
}
if (-not $branches) { Ok "no copilot/* or self-heal/* branches" }

# 3. Delete stale ghcr.io image tags (best-effort)
if (-not $SkipImageDelete) {
    Step "Pruning ghcr.io demo image tags (best-effort)"
    $owner = ($repoSlug -split '/')[0]
    $name  = ($repoSlug -split '/')[1]
    try {
        $versions = gh api -H "Accept: application/vnd.github+json" `
            "/users/$owner/packages/container/$name/versions" --jq '.[] | select(.metadata.container.tags | length > 0) | select((.metadata.container.tags | map(. == "latest") | any) | not) | .id' 2>$null
        foreach ($v in $versions) {
            gh api -X DELETE "/users/$owner/packages/container/$name/versions/$v" 2>$null | Out-Null
            Ok "deleted version $v"
        }
    }
    catch {
        Warn "could not enumerate package versions ($($_.Exception.Message)); continuing"
    }
}

# 4. Reset main to baseline tag
Step "Resetting main to tag $BaselineTag"
git fetch origin --tags --force | Out-Null
$tagExists = git tag --list $BaselineTag
if (-not $tagExists) { throw "Baseline tag '$BaselineTag' does not exist locally. Create it on the known-good commit first." }

git checkout main | Out-Null
if ($PSCmdlet.ShouldProcess("main", "reset --hard $BaselineTag")) {
    git reset --hard $BaselineTag
    git push origin main --force-with-lease
    Ok "main is now at $BaselineTag"
}

# 5. Clear metrics file
Step "Clearing metrics/self-heal-events.jsonl"
$metricsPath = Join-Path $repoRoot 'metrics/self-heal-events.jsonl'
if (Test-Path $metricsPath) {
    Set-Content -Path $metricsPath -Value '' -NoNewline
    if ((git status --porcelain $metricsPath)) {
        git add $metricsPath
        git commit -m "chore(reset): clear self-heal metrics" | Out-Null
        git push origin main
        Ok "metrics cleared and pushed"
    }
    else {
        Ok "metrics already empty"
    }
}

Step "Reset complete."
