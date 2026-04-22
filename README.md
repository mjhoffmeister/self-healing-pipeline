# self-healing-demo

A hand-rolled, governance-aligned reference implementation of an **agentic CI self-healing loop**:

```
CI failure → tracking issue → Copilot cloud agent → fix PR → human-gated merge → green build
```

Built for platform / security / governance leaders evaluating Agentic DevOps. Copy-paste-able into a regulated repo.

## Architecture

```
┌──────────────┐ workflow_run ┌───────────────────┐ gh issue ┌───────────────┐
│   ci.yml     │─── failure ─►│  self-heal.yml    │─────────►│ tracking issue│
│ build/test/  │              │  (responder)      │          │ (records the  │
│ docker push  │              │                   │          │  failure)     │
└──────────────┘              └─────────┬─────────┘          └───────────────┘
                                        │
                                        │ if transient & attempt<2
                                        ▼
                            ┌────────────────────────┐
                            │ reRunWorkflowFailedJobs│
                            └────────────────────────┘
                                        │
                                        │ otherwise: dispatch to agent
                                        ▼
                            ┌──────────────────────────────┐
                            │  source PR exists?           │
                            │   yes → assign @copilot to   │
                            │         the PR + post        │
                            │         "fix this" comment   │
                            │   no  → assign @copilot to   │
                            │         the tracking issue   │
                            │         (agent opens new PR) │
                            └──────────────┬───────────────┘
                                           │
                                           ▼
                                  Copilot pushes commits
                                  onto the PR's branch
                                  (or opens a fix PR in
                                  the fallback case)
                                           │
                  required-checks.yml ◄────┤
                  (separation of duties)   │
                                           ▼
                                    human reviewer
                                    clicks Squash & Merge
                                    — green main
```

Hero artifact: [.github/workflows/self-heal.yml](.github/workflows/self-heal.yml).

## Governance posture (the value proposition)

- **No PATs.** Copilot assignment uses a runtime-minted GitHub App installation token (signed JWT → ~1h installation token), backed by `vars.APP_ID` + `secrets.APP_PRIVATE_KEY`. No long-lived stored tokens.
- **All third-party actions pinned by full commit SHA**, with `# vX.Y.Z` comments for Dependabot.
- **First-party only** in `self-heal.yml` and `required-checks.yml` (`actions/*`, `gh` CLI, inline shell).
- **Minimum permissions** declared per job.
- **Loop prevention** via `actor != 'copilot-swe-agent[bot]'` guards.
- **Separation of duties** enforced by `required-checks.yml` (author ≠ merger).
- **Circuit breaker:** after 3 attempts on the same `(workflow, branch, failed_job)`, the issue is escalated to CODEOWNERS and Copilot is no longer reassigned.
- **Branch protection** on `main` (configure manually): 1 review, required status checks, no force-push, no self-approval. See `DEMO.md` for the single deliberate softening (admin-bypass on for solo presenter) and how a real regulated repo would tighten it.

## Quickstart (one command)

```powershell
pwsh ./scripts/Run-Scenario.ps1 -Scenario F2
```

Bash equivalent:

```bash
./scripts/run-scenario.sh F2
```

Pick `F1`, `F2`, `F3`, or `F4`. The wrapper does the entire local sequence: pre-flight `verify-clean` → branch off `origin/main` → inject the failure → assert exactly one file changed → commit + push → open the PR. After it exits, watch the GitHub UI: a tracking issue appears within ~2 min, Copilot is assigned, a fix PR follows. Squash-merge it when CI is green. Useful flags: `-DryRun`, `-SkipVerify`, `-NoPr`. See [DEMO.md](DEMO.md) for the per-scenario timeline, what to point at on stage, and the manual step-by-step alternative.

When you're done:

```powershell
pwsh ./scripts/reset-demo.ps1
# or trigger the reset-demo workflow from the GitHub UI on your phone.
```

## Repo layout

| Path | Purpose |
|------|---------|
| `src/Api/` | .NET 10 minimal API (the system under test) |
| `tests/Api.Tests/` | xUnit tests |
| `Dockerfile` | Multi-stage build, publishes to `ghcr.io` |
| `.github/workflows/ci.yml` | Primary build/test/publish pipeline |
| `.github/workflows/self-heal.yml` | **Hero file** — the responder |
| `.github/workflows/required-checks.yml` | Separation-of-duties status check |
| `.github/workflows/reset-demo.yml` | Server-side `workflow_dispatch` reset |
| `.github/CI_FAILURE_TEMPLATE.md` | Issue template (envsubst) |
| `.github/copilot-instructions.md` | Agent guidance (also at repo root if you prefer) |
| `.github/CODEOWNERS` | Stricter ownership for governance-sensitive paths |
| `scripts/inject-failure.{ps1,sh}` | Inject F1/F2/F3/F4 |
| `scripts/reset-demo.{ps1,sh}` | Local idempotent reset |
| `scripts/verify-clean.ps1` | Pre-flight check (exits non-zero if dirty) |
| `metrics/self-heal-events.jsonl` | Append-only metrics (one line per responder run) |
| `DEMO.md` | Narration script |
| `plan/PLAN.md` | The original design doc |

## One-time setup checklist (do this once per repo)

1. **Make the repo public** (free `ghcr.io`, simplest Copilot enablement).
2. **Create the `demo-baseline` git tag** on the known-good initial commit:
   ```bash
   git tag -a demo-baseline -m "demo baseline" <SHA>
   git push origin demo-baseline
   ```
3. **Replace `@your-org/*` placeholders** in `.github/CODEOWNERS`.
4. **Configure repo Actions permissions.** The responder pushes a `metrics/` PR and the CI workflow pushes images to `ghcr.io`, so:
   ```powershell
   gh api -X PUT /repos/<owner>/<repo>/actions/permissions/workflow `
     -f default_workflow_permissions=write `
     -F can_approve_pull_request_reviews=true
   ```
   Or in the UI: **Settings → Actions → General → Workflow permissions** → "Read and write permissions" + "Allow GitHub Actions to create and approve pull requests". Without this, the metrics job fails with `GitHub Actions is not permitted to create or approve pull requests`.
5. **Configure branch protection on `main`:** require 1 PR review, require status checks `build & test`, `docker build & publish`, `separation of duties`. Disallow force-push and self-approval. (For demo: leave admin-bypass on.)
6. **Provision the `selfheal-orchestrator` GitHub App** with the irreducible-minimum permissions: **`issues:write`** + **`pull_requests:write`** + **`metadata:read`** (read-only metadata is mandatory for any App). No `contents` scope. Install the App on this repo only. Then:
   - Store the public **App ID** as a repo **variable** `APP_ID` (variable, not secret — it's not sensitive).
   - Store the App's **RSA private key** (the `.pem` contents downloaded from the App settings page) as a repo **secret** `APP_PRIVATE_KEY`. This is the only long-lived secret in the system; it's used to sign a JWT each run, which is exchanged for a ~1-hour installation token.

   `pull_requests:write` is required because the responder dispatches the cloud agent against the **source PR** when one exists (commits land on the PR's branch instead of opening a new PR off `main`). The `issues:write` scope still covers the fallback path (push direct to `main`) and the tracking-issue assignment + comments.

   **No PATs. No long-lived installation tokens** — those expire hourly so a stored one would inevitably become a PAT in disguise.
7. **Enable the Copilot cloud agent** (formerly "Copilot coding agent") at the org or repo level (org policy must allow it). On a personal-account public repo this is on by default for eligible plan tiers.

   Verify the agent is assignable on this repo with:
   ```powershell
   gh api graphql -f query='query { repository(owner:"<owner>", name:"<repo>") { suggestedActors(capabilities:[CAN_BE_ASSIGNED], first:25) { nodes { login __typename } } } }'
   ```
   You should see a `Bot` node with `login: "copilot-swe-agent"`. **Important quirk:** the agent's display name is `Copilot` but its actual assignment handle is `copilot-swe-agent` — the responder workflow already uses the correct handle, but if you ever assign by hand, use `gh issue edit <N> --add-assignee copilot-swe-agent`.
8. **Verify SHA pins.** Each `uses:` line in `ci.yml`, `reset-demo.yml`, and `required-checks.yml` is pinned by full commit SHA with a trailing `# vX.Y.Z` comment. Re-verify against the upstream release tag before going live; let Dependabot bump them thereafter.

## Verification

The plan calls for six functional + three negative tests. See [plan/PLAN.md](plan/PLAN.md) Phase 6. In summary:

- F1/F2/F3/F4 each produce: issue → directive comment + assignment on the source PR → Copilot pushes commits onto the PR → green CI within ~10 min median.
- 4 consecutive failures → circuit breaker fires, escalation label applied, no further Copilot assignment.
- Bot-authored failing PR → responder skips (actor guard).
- Bug in `self-heal.yml` itself → no self-heal occurs (the documented chicken-and-egg limit).
- `reset-demo` + `verify-clean` returns to baseline in < 2 min.

## Out of scope

Post-deploy auto-remediation, ITSM integrations, security-scanner integrations, `gh aw` adaptation. The point of this repo is the *governed loop*, not the breadth of integrations.
