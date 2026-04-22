#!/usr/bin/env bash
# Reset the demo repo to the demo-baseline tag, locally and remotely.
# Idempotent. See scripts/reset-demo.ps1 for the canonical PowerShell version.
set -euo pipefail

baseline_tag="${BASELINE_TAG:-demo-baseline}"
skip_image_delete="${SKIP_IMAGE_DELETE:-0}"

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

step() { printf '\033[36m==> %s\033[0m\n' "$*"; }
ok()   { printf '  \033[32mok:\033[0m %s\n' "$*"; }
warn() { printf '  \033[33mwarn:\033[0m %s\n' "$*"; }

command -v gh  >/dev/null || { echo "gh CLI not found"; exit 1; }
command -v git >/dev/null || { echo "git not found"; exit 1; }

if [ -n "$(git status --porcelain)" ]; then
  echo "Working tree is dirty. Commit or stash before resetting." >&2
  exit 1
fi

repo_slug="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
step "Repo: $repo_slug"

step "Closing open self-heal issues"
mapfile -t issues < <(gh issue list --label self-heal --state open --json number --jq '.[].number')
if [ "${#issues[@]}" -eq 0 ]; then
  ok "no open self-heal issues"
else
  for n in "${issues[@]}"; do
    gh issue close "$n" --comment "Closed by reset-demo." >/dev/null
    ok "closed #$n"
  done
fi

step "Deleting remote copilot/* and self-heal/* branches"
git fetch --prune origin >/dev/null
mapfile -t branches < <(git branch -r | sed 's/^[[:space:]]*//' | awk '/^origin\/(copilot|self-heal)\// {sub(/^origin\//,""); print}')
if [ "${#branches[@]}" -eq 0 ]; then
  ok "no copilot/* or self-heal/* branches"
else
  for b in "${branches[@]}"; do
    git push origin --delete "$b" 2>/dev/null || true
    ok "deleted $b"
  done
fi

if [ "$skip_image_delete" != "1" ]; then
  step "Pruning ghcr.io demo image tags (best-effort)"
  owner="${repo_slug%%/*}"
  name="${repo_slug##*/}"
  if versions="$(gh api -H 'Accept: application/vnd.github+json' \
      "/users/$owner/packages/container/$name/versions" \
      --jq '.[] | select(.metadata.container.tags | length > 0) | select((.metadata.container.tags | map(. == "latest") | any) | not) | .id' 2>/dev/null)"; then
    while IFS= read -r v; do
      [ -z "$v" ] && continue
      gh api -X DELETE "/users/$owner/packages/container/$name/versions/$v" 2>/dev/null || true
      ok "deleted version $v"
    done <<<"$versions"
  else
    warn "could not enumerate package versions; continuing"
  fi
fi

step "Resetting main to tag $baseline_tag"
git fetch origin --tags --force >/dev/null
if ! git tag --list "$baseline_tag" | grep -qx "$baseline_tag"; then
  echo "Baseline tag '$baseline_tag' does not exist locally. Create it on the known-good commit first." >&2
  exit 1
fi

git checkout main >/dev/null
git reset --hard "$baseline_tag"
git push origin main --force-with-lease
ok "main is now at $baseline_tag"

step "Clearing metrics/self-heal-events.jsonl"
metrics="metrics/self-heal-events.jsonl"
if [ -f "$metrics" ]; then
  : > "$metrics"
  if [ -n "$(git status --porcelain "$metrics")" ]; then
    git add "$metrics"
    git commit -m "chore(reset): clear self-heal metrics" >/dev/null
    git push origin main
    ok "metrics cleared and pushed"
  else
    ok "metrics already empty"
  fi
fi

step "Reset complete."
