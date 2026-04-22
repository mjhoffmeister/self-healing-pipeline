#!/usr/bin/env bash
# Fire off a single self-healing demo scenario in one command.
# See scripts/Run-Scenario.ps1 for the canonical PowerShell version + full --help.
#
# Usage:
#   ./scripts/run-scenario.sh F1|F2|F3|F4 [--dry-run] [--skip-verify] [--no-pr]
set -euo pipefail

scenario=""
dry_run=0
skip_verify=0
no_pr=0

for arg in "$@"; do
  case "$arg" in
    F1|F2|F3|F4) scenario="$arg" ;;
    --dry-run)     dry_run=1 ;;
    --skip-verify) skip_verify=1 ;;
    --no-pr)       no_pr=1 ;;
    -h|--help)
      sed -n '1,15p' "$0"
      exit 0
      ;;
    *) echo "unknown arg: $arg" >&2; exit 2 ;;
  esac
done

if [ -z "$scenario" ]; then
  echo "usage: $0 F1|F2|F3|F4 [--dry-run] [--skip-verify] [--no-pr]" >&2
  exit 2
fi

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

step() { printf '\033[36m==> %s\033[0m\n' "$*"; }
run()  {
  printf '    \033[90m%s\033[0m\n' "$*"
  if [ "$dry_run" -ne 1 ]; then
    eval "$@"
  fi
}

command -v git >/dev/null || { echo "git not found"; exit 1; }
command -v gh  >/dev/null || { echo "gh not found"; exit 1; }

if [ "$skip_verify" -ne 1 ]; then
  step "Pre-flight: verify-clean"
  if [ "$dry_run" -eq 1 ]; then
    printf '    \033[90mpwsh ./scripts/verify-clean.ps1 (skipped in dry-run)\033[0m\n'
  else
    if command -v pwsh >/dev/null; then
      pwsh -NoProfile -File ./scripts/verify-clean.ps1
    else
      echo "WARNING: pwsh not installed; skipping verify-clean. Use --skip-verify to silence." >&2
    fi
  fi
else
  step "Pre-flight: skipped (--skip-verify)"
fi

timestamp="$(date +%Y%m%d-%H%M%S)"
branch="inject/${scenario}-${timestamp}"

step "Creating branch ${branch} from origin/main"
run "git fetch origin main --quiet"
run "git checkout -B \"${branch}\" origin/main"

step "Injecting scenario ${scenario}"
if [ "$dry_run" -eq 1 ]; then
  printf '    \033[90m./scripts/inject-failure.sh %s (skipped in dry-run)\033[0m\n' "$scenario"
else
  ./scripts/inject-failure.sh "$scenario"
fi

if [ "$dry_run" -ne 1 ]; then
  changed_count="$(git diff --name-only | wc -l | tr -d ' ')"
  if [ "$changed_count" != "1" ]; then
    echo "Expected exactly one changed file, got ${changed_count}:" >&2
    git diff --name-only >&2
    exit 1
  fi
  step "Modified: $(git diff --name-only)"
fi

step "Committing and pushing"
run "git commit -am \"demo: inject ${scenario}\""
run "git push -u origin \"${branch}\""

if [ "$no_pr" -eq 1 ]; then
  step "Skipping PR creation (--no-pr). Branch pushed: ${branch}"
  exit 0
fi

step "Opening PR"
body_file="$(mktemp)"
trap 'rm -f "$body_file"' EXIT
cat >"$body_file" <<EOF
Automated demo injection of scenario **${scenario}**.

CI is expected to fail. Within ~2 min, the self-heal responder will:
1. Open a tracking issue labelled \`self-heal\` (with this PR linked as **Source PR**).
2. Append \`Fixes #N\` to this PR's body so the issue auto-closes on merge.
3. Assign **@Copilot** to this PR and post an \`@copilot\` directive comment asking it to commit a fix to this branch.
4. Copilot pushes commits onto this branch (no new PR). Watch the **Commits** tab.

When CI on this PR turns green, squash-merge it (the separation-of-duties check confirms author ≠ merger; the tracking issue closes automatically).

See DEMO.md for the full timeline.
EOF

if [ "$dry_run" -eq 1 ]; then
  printf '    \033[90mgh label create demo|self-heal-injection --force (cosmetic, idempotent)\033[0m\n'
  printf '    \033[90mgh pr create --title "demo: %s injection" --body-file <tmp> --label demo --label self-heal-injection\033[0m\n' "$scenario"
else
  # Ensure cosmetic labels exist (idempotent). They are not required by any
  # workflow; they only help filter demo PRs in the GitHub UI.
  gh label create demo --color BFD4F2 --description "Demo / presentation artefact" --force >/dev/null
  gh label create self-heal-injection --color D73A4A --description "Deliberately broken to exercise the self-heal loop" --force >/dev/null

  gh pr create \
    --title "demo: ${scenario} injection" \
    --body-file "$body_file" \
    --label demo \
    --label "self-heal-injection"
fi

echo ""
step "Done. Watch for the tracking issue, then Copilot's commits on this PR."
echo "  gh issue list --label self-heal --state open"
echo "  gh pr view --web"
