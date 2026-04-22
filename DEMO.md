# DEMO.md — narration script

A 20-minute walkthrough of the self-healing pipeline, with a 5-minute lightning cut and four reproducible failure scenarios. Always run `scripts/verify-clean.ps1` first.

> **Recorded backup:** keep a 3-5 minute screen recording of scenario F2 on hand. Cloud-agent latency is unpredictable; a recording is your safety net.

---

## Pre-flight (every time, no exceptions)

```powershell
pwsh ./scripts/verify-clean.ps1
```

Must exit `0`. If not, run `pwsh ./scripts/reset-demo.ps1` (or trigger the `reset-demo` workflow from the GitHub UI on your phone).

## The four scenarios

| ID | What breaks | Fix complexity | Who fixes |
|----|-------------|----------------|-----------|
| F1 | Lint/format drift | Trivial (`dotnet format`) | Copilot, in seconds |
| F2 | Failing unit test from a code typo | Small code change | Copilot |
| F3 | Bad Dockerfile build arg | Edit `Dockerfile` | Copilot |
| F4 | Broken step in `ci.yml` itself | Edit the pipeline definition | Copilot — proves the agent can fix the pipeline, not just app code |

The responder workflow (`self-heal.yml`) is **never** a target — bugs in it cannot self-heal by definition. See "Chicken-and-egg limit" below.

## How to run a scenario (one command)

```powershell
pwsh ./scripts/Run-Scenario.ps1 -Scenario F2
```

Bash equivalent:

```bash
./scripts/run-scenario.sh F2
```

That's it. The wrapper does all five steps in order:

1. `verify-clean` (pre-flight; refuses if the repo isn't at `demo-baseline`).
2. Branch off `origin/main` as `inject/<Scenario>-<timestamp>`.
3. Run [scripts/inject-failure.ps1](scripts/inject-failure.ps1) for the chosen scenario, then assert exactly one file changed.
4. Commit + push.
5. `gh pr create` with a templated body that explains what's about to happen.

Useful flags:

| Flag | Purpose |
|------|---------|
| `-DryRun` (`--dry-run`) | Print every command but don't push or open a PR. |
| `-SkipVerify` (`--skip-verify`) | Skip the `verify-clean` pre-flight (use sparingly). |
| `-NoPr` (`--no-pr`) | Push the branch but don't open the PR — useful for inspection. |

After the wrapper exits, the responder workflow takes over server-side. Skip ahead to ["What you should see after pushing"](#what-you-should-see-after-pushing).

### What each scenario actually changes

Use this to confirm the injection did what you expected (`git diff --stat` should match):

| Scenario | File touched | Effective change | First CI step that fails |
|----------|--------------|------------------|--------------------------|
| **F1** | `src/Api/GreetingService.cs` | Inserts a tab + trailing whitespace inside `Greet()` | `Verify formatting` (`dotnet format --verify-no-changes`) |
| **F2** | `src/Api/GreetingService.cs` | Adds a new `GreetFormal()` method **and** introduces a typo regression (`"Hello, ..."` → `"Helo, ..."`) in existing `Greet()`. The agent must keep the new method while fixing only the regression — it can't just `git revert`. | `Test` (xUnit theories on `Greet` fail) |
| **F3** | `Dockerfile` | `ARG DOTNET_SDK_VERSION=10.0` → `99.0-does-not-exist` | `docker build & publish` (image pull fails) |
| **F4** | `.github/workflows/ci.yml` | `DOTNET_VERSION: "10.0.x"` → `"99.0.x"` | `Setup .NET` (no matching SDK) |

### What you should see after pushing

For all four scenarios, the timeline is the same. F4 has one extra click:

| When | What appears | Where to look |
|------|--------------|---------------|
| t+0 | Your PR opens, CI starts and fails | The PR's **Checks** tab |
| t+1-2 min | `Self-heal` workflow runs against the failed CI run | **Actions** tab → "Self-heal" |
| t+2-3 min | A new issue `[self-heal] CI failed: ...` appears, labelled `self-heal · self-heal/attempt-1`, **assigned to @Copilot** | **Issues** tab |
| t+5-10 min | Copilot opens a PR titled `Fixes #N` against `main` | **Pull requests** tab |
| **F4 only:** t+~5 min | Copilot's PR shows "Workflows awaiting approval". **Click "Approve and run workflows"**. This is GitHub's first-time-bot-contributor default, not a bug. | Copilot's PR page |
| t+~12 min | CI on Copilot's PR turns green | Copilot's PR Checks tab |
| You decide | **Squash and merge** Copilot's PR. The `separation of duties` check confirms author ≠ merger. | Copilot's PR |
| Cleanup | Close your original `inject/...` PR; it's no longer needed. The fix went to `main` via Copilot's PR. | Your original PR |

### What to point at on stage

- The **issue body** — note the failed job name, the last 50 log lines (rendered inside a `~~~~` fence so log content can't break it), and the `sh-<dedupe-key>` token at the bottom that drives dedupe.
- The **`required-checks / separation of duties` status** on Copilot's PR — visible in the checks list as a governance artifact.
- The **labels on the tracking issue** — `self-heal/attempt-N` increments on every retry; at `attempt-3` it flips to `self-heal/escalated`, the issue gets a 🚨 comment, and Copilot is **no longer reassigned**.
- The **metrics PR** — every responder run appends a JSON line to `metrics/self-heal-events.jsonl` via a separate, squash-mergeable PR.

### Manual / step-by-step alternative

If you want to drive the steps by hand (e.g. to pause and explain each one on stage), do exactly what the wrapper does:

```powershell
$scenario = 'F2'
pwsh ./scripts/verify-clean.ps1
git checkout main; git pull
git checkout -b "inject/$scenario-$(Get-Date -Format yyyyMMdd-HHmmss)"
pwsh ./scripts/inject-failure.ps1 -Scenario $scenario
git diff --stat            # sanity: should be one file
git commit -am "demo: inject $scenario"
git push -u origin HEAD
gh pr create --fill
```

### If you want to recover and re-run

```powershell
pwsh ./scripts/reset-demo.ps1            # local
# or trigger the reset-demo workflow from the GitHub UI (works from a phone).
pwsh ./scripts/verify-clean.ps1          # must exit 0 before the next scenario
```

## Lightning cut (5 min)

Use F2 only. Skip F1/F3/F4. Show: injection → issue with assignee → Copilot PR → green CI → merge.

## Governance posture vs. demo posture

| Rule | Production posture | Demo posture | Why softened |
|------|--------------------|--------------|--------------|
| Branch protection on `main` | Required reviews ≥ 1, required checks, no force-push, no self-approval, **admins included** | Same, but **admins NOT included** | Lets a solo presenter merge Copilot's PR without a second human |
| Required reviewers on `self-heal.yml` | CODEOWNERS-required, two reviewers | CODEOWNERS-required, one reviewer | Solo presenter |
| Copilot assignment token | Runtime-minted App installation token (`vars.APP_ID` + `secrets.APP_PRIVATE_KEY`) | Same | No softening — never use a PAT, never store an installation token |
| Action pinning | Full SHA pin, Dependabot bumps | Same | No softening |
| Separation-of-duties check | Required status | Required status | No softening |

## Chicken-and-egg limit (call this out explicitly)

`self-heal.yml` cannot self-heal a bug in itself. If it stops responding, a human must open a PR. This is why:

- The responder file is under stricter `CODEOWNERS` review.
- Negative test #6 in `verification.md` confirms a broken responder produces silence, not a loop.
- The `reset-demo` workflow runs server-side so a presenter can recover even if the responder is dead.

## Cost note

Each scenario consumes ~1 Copilot premium request (the agent's coding session). Container artifacts go to `ghcr.io`, which is free for public repos. There are no third-party SaaS costs in the demo.

## Operational caveats

- **Metrics PRs do not auto-trigger CI.** The responder opens a metrics PR using `GITHUB_TOKEN`. Per GitHub's loop-prevention default, branches pushed by `GITHUB_TOKEN` do **not** trigger downstream workflows — so the required CI checks won't run automatically on the metrics PR. Either click **"Run workflow"** on it manually, or add a branch filter that exempts `self-heal/metrics-*` from required checks. Treat metrics PRs as squash-merge-on-sight by a maintainer.
- **First-time Copilot PR.** Same default: a maintainer must click **"Approve and run workflows"** the first time the agent opens a PR. Already called out in the F4 narration.
