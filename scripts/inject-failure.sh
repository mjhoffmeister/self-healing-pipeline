#!/usr/bin/env bash
# Inject one of the four documented failure scenarios.
# Usage: ./scripts/inject-failure.sh F1|F2|F3|F4
set -euo pipefail

scenario="${1:-}"
case "$scenario" in
  F1|F2|F3|F4) ;;
  *) echo "usage: $0 F1|F2|F3|F4" >&2; exit 2 ;;
esac

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

require_change() {
  local path="$1"
  if git diff --quiet -- "$path"; then
    echo "ERROR: injection produced no change in $path" >&2
    exit 1
  fi
  echo "  modified $path"
}

echo "Injecting scenario $scenario..."

case "$scenario" in
  F1)
    # Lint/format drift: tab + trailing whitespace.
    python3 - <<'PY'
import io
p = "src/Api/GreetingService.cs"
s = open(p, "r", encoding="utf-8").read()
s = s.replace(
    "public static string Greet(string? name)\n    {\n",
    "public static string Greet(string? name)\n    {\n\t   var __unused = 0;   \n",
)
open(p, "w", encoding="utf-8", newline="").write(s)
PY
    require_change src/Api/GreetingService.cs
    ;;
  F2)
    sed -i.bak 's/"Hello, {trimmed}!"/"Helo, {trimmed}!"/' src/Api/GreetingService.cs
    rm -f src/Api/GreetingService.cs.bak
    require_change src/Api/GreetingService.cs
    ;;
  F3)
    sed -i.bak 's/ARG DOTNET_SDK_VERSION=10\.0/ARG DOTNET_SDK_VERSION=99.0-does-not-exist/' Dockerfile
    rm -f Dockerfile.bak
    require_change Dockerfile
    ;;
  F4)
    sed -i.bak 's/DOTNET_VERSION: "10\.0\.x"/DOTNET_VERSION: "99.0.x"/' .github/workflows/ci.yml
    rm -f .github/workflows/ci.yml.bak
    require_change .github/workflows/ci.yml
    ;;
esac

cat <<EOF

Done. Recommended order is branch-FIRST, inject-SECOND, but the change is
already in your working tree, so just commit it onto a fresh branch:
  git stash                                    # if you weren't already on a fresh branch
  git checkout main && git pull
  git checkout -b inject/${scenario}-\$(date +%Y%m%d-%H%M%S)
  git stash pop                                # restore the injected change
  git diff --stat                              # sanity: should be one file
  git commit -am "demo: inject ${scenario}"
  git push -u origin HEAD
  gh pr create --fill                          # CI will fail; the responder takes over.
EOF
