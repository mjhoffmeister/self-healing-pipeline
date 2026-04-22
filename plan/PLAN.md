# Plan: Production-Grade Self-Healing Pipeline Demo

Build a hand-rolled, governance-aligned reference implementation that demonstrates the full loop:
**CI failure → tracking issue → Copilot coding agent → fix PR → human-gated merge → green build**.
Target audience: platform/security/governance leaders evaluating Agentic DevOps; usable as a copy-paste starter for regulated repos.

---

## Phases

### Phase 1 — Scaffolding & app under test
1. Initialize repo `self-healing-demo` (public). Folder name on disk matches.
2. Build a deliberately-fragile sample app: small **.NET 10 minimal API** with xUnit tests + a Dockerfile. Four injectable failure modes:
   - **F1 — Lint/format drift** (auto-fixable trivially)
   - **F2 — Failing unit test from a code typo** (Copilot-eligible)
   - **F3 — Bad Dockerfile build arg** (Copilot-eligible, infra-adjacent)
   - **F4 — Broken CI workflow step** (e.g. wrong `dotnet` version pin or invalid action input in `ci.yml`) — proves the agent can fix the *pipeline definition itself*, not just app code. Strict scope: F4 mutates `ci.yml` only; the responder workflow `self-heal.yml` is never the target (a bug there can't self-heal by definition — called out in `DEMO.md`).
3. Standard CI workflow `.github/workflows/ci.yml`: build → test → docker build → publish artifact to **GitHub Container Registry (`ghcr.io`)** — free for public repos, authenticates with `GITHUB_TOKEN`, no external registry account required. SHA-pinned actions only.
4. Repo hardening: branch protection on `main` (1 review, required status checks, no force-push, no self-approval, **admins NOT included** so a solo presenter can still merge), CODEOWNERS, `copilot-instructions.md`. The governance story is told via the *rules*; the admin-bypass is called out explicitly in `DEMO.md` as the single deliberate demo concession (in a real regulated repo, admins would be included and a second human approver would exist).

### Phase 2 — Self-heal responder workflow (the hero artifact)
*Depends on Phase 1.*
1. New workflow `.github/workflows/self-heal.yml` triggered by `workflow_run` (`workflows: [CI]`, `types: [completed]`).
2. Job structure:
   - **classify** — fail-fast filter on `conclusion == 'failure'`; download upstream logs/artifacts via `actions/github-script` + `listWorkflowRunArtifacts`; parse for known transient signatures (network, timeout, runner-OOM).
   - **retry-once** — if transient *and* `run_attempt < 2`, call `reRunWorkflowFailedJobs`. Exit.
   - **open-or-update-issue** — use the pre-installed `gh` CLI (authenticated with `GITHUB_TOKEN`): `gh issue list --search` for dedupe, then `gh issue create` or `gh issue comment`. Dedupe by title hash `(workflow_name + head_branch + failed_job_name)`. The failed job name is the natural category — no separate triage/bucket step. Body is rendered from `.github/CI_FAILURE_TEMPLATE.md` via simple `envsubst` and includes failing job links, last 50 log lines, head SHA, run URL, suggested rollback command. First-party only — no third-party action in the supply chain.
   - **assign-copilot** — `gh issue edit <num> --add-assignee Copilot` using a dedicated `COPILOT_ASSIGN_TOKEN` (fine-scoped GitHub App installation token; *not* a PAT).
   - **circuit-breaker** — count `self-heal/attempt-N` labels on the issue (single dimension: `head_branch`); if N ≥ 3, replace label with `self-heal/escalated`, ping CODEOWNERS, do NOT reassign Copilot.
3. Permissions block: minimum viable per job (`contents: read`, `issues: write`, `actions: write` only where needed).
4. Loop-prevention guards: `if: github.actor != 'copilot-swe-agent[bot]'`, payload sanitization for any value used in shell.

### Phase 3 — Copilot agent enablement
*Parallel with Phase 2.*
1. `.github/copilot-instructions.md` — coding standards, test command, Dockerfile conventions, "always run `dotnet format` and `dotnet test` before opening PR."
2. Repo-level Copilot coding agent enabled; org policy verified.
3. GitHub App `selfheal-orchestrator` provisioned with **only** `issues:write`, `pull_requests:read`, `metadata:read`. Installation token minted at runtime via `actions/create-github-app-token@v2`. Documents *why* not a PAT.
4. Branch protection enforces: requester ≠ approver, all required checks must pass on agent's PR (the "no auto-run on agent PR" GitHub default actually helps here — first reviewer must approve workflows). **Demo caveat:** Copilot's first PR will require a one-click "Approve and run workflows" from a maintainer before CI executes; this click is part of the demo narration, not a bug.

### Phase 4 — Governance & observability overlays
*Depends on Phase 2.*
1. **Separation-of-duties status check** — wrapper workflow that asserts `pr.user.login != pr.merged_by.login` (author ≠ merger). For Copilot PRs this is trivially satisfied; the value is that the rule is *visible* in the checks list as a governance artifact, and it prevents a future human author from merging their own PR even if branch protection is misconfigured. Demo-safe: never blocks a solo presenter merging Copilot's PR.
2. **Metrics emitter** — every responder run posts a JSON summary line to a `metrics/self-heal-events.jsonl` file via PR.

### Phase 5 — Demo script & first-class reset
*Depends on Phases 1–4.*
1. `DEMO.md` with four reproducible scenarios mapped to F1/F2/F3/F4, each with: command to inject, expected timeline, screenshots, what to point at on stage, and the explicit "click Approve and run workflows on Copilot's PR" beat. Includes a short **Governance posture vs. demo posture** section explaining which rules are softened (admin-bypass on protections) and how a real regulated repo would tighten them (admins included, 2 reviewers, CODEOWNERS-required review). Also names the **chicken-and-egg limit**: bugs in `self-heal.yml` itself cannot self-heal — they require a human PR.
2. **Reset is a first-class repo feature**, not an afterthought:
   - `scripts/reset-demo.ps1` *and* `scripts/reset-demo.sh` (cross-platform parity).
   - `scripts/inject-failure.ps1 -Scenario F1|F2|F3|F4` paired with `reset-demo` so every injection has a guaranteed clean undo.
   - `.github/workflows/reset-demo.yml` — `workflow_dispatch` workflow that runs the reset server-side: closes self-heal issues, deletes `copilot/*` branches, deletes stale `ghcr.io` demo image tags, resets `main` to a known `demo-baseline` tag, clears `metrics/self-heal-events.jsonl`. Lets a presenter reset from the GitHub UI on a phone if their laptop dies.
   - A `demo-baseline` git tag pinned to the known-good commit; reset always returns the repo to this tag.
   - `scripts/verify-clean.ps1` — pre-flight check the runbook requires before going on stage; exits non-zero if any self-heal issue, Copilot branch, or injected failure is still present.
   - The reset path is itself covered by Phase 6 verification — if reset breaks, the demo is broken.
3. Recorded walkthrough (3–5 min) showing scenario F2 end-to-end as a backup if live demo fails.

### Phase 6 — Verification & hardening
*Depends on all prior.*
1. Run scenario F1 → expect: retry skipped, issue opened, Copilot PR within 10 min, format-only diff.
2. Run scenario F2 → expect: issue opened with failing test name, Copilot PR with code fix + green CI.
3. Run scenario F3 → expect: issue opened, Copilot PR fixing Dockerfile, full pipeline green.
4. Run scenario F4 → expect: issue opened, Copilot PR editing `.github/workflows/ci.yml`, full pipeline green. (Note: the agent's PR will need the standard "Approve and run workflows" click before its modified CI executes.)
5. Negative test: trigger the same failure 4 times in a row → expect circuit breaker fires, escalation label applied, no further Copilot assignment.
6. Negative test: bot opens a PR that itself fails CI → expect responder skips (actor guard).
7. Negative test: inject a bug into `self-heal.yml` itself → expect no self-heal loop occurs (responder is broken); confirms the documented chicken-and-egg limit and motivates keeping `self-heal.yml` under stricter CODEOWNERS review.
8. **Reset verification:** after each scenario, `reset-demo` + `verify-clean` must return the repo to the `demo-baseline` tag with zero open self-heal artifacts in under 2 min — tested both locally and via the `reset-demo.yml` workflow.
9. Security review checklist: SHA pins verified, no PATs, GitHub App token scoped minimally, payloads sanitized, branch protection cannot be bypassed by the bot.

---

## Relevant files (to be created)

- `.github/workflows/ci.yml` — primary build/test pipeline (publishes image to `ghcr.io`)
- `.github/workflows/self-heal.yml` — responder (hero file)
- `.github/workflows/required-checks.yml` — separation-of-duties enforcement
- `.github/workflows/reset-demo.yml` — server-side reset via `workflow_dispatch`
- `.github/CI_FAILURE_TEMPLATE.md` — issue body template (env-var substitution)
- `.github/copilot-instructions.md` — agent guidance
- `.github/CODEOWNERS`
- `src/Api/*` — sample .NET 10 minimal API
- `tests/Api.Tests/*` — xUnit tests
- `Dockerfile`
- `DEMO.md` — narration script
- `scripts/inject-failure.ps1`, `scripts/inject-failure.sh`
- `scripts/reset-demo.ps1`, `scripts/reset-demo.sh`
- `scripts/verify-clean.ps1`
- `metrics/self-heal-events.jsonl` (seeded empty)
- `README.md` — architecture diagram + governance posture + reset-first quickstart

## Reference implementations (to reuse, not copy wholesale)

- [yortch/self-healing-pipeline-demo](https://github.com/yortch/self-healing-pipeline-demo) — proves end-to-end loop runs; borrow demo-script structure
- [githubnext/agentics CI Doctor](https://github.com/githubnext/agentics/blob/main/docs/ci-doctor.md) — borrow log-analysis prompt patterns

## Verification

1. **Functional:** all four demo scenarios pass on first dry-run; circuit breaker test passes.
2. **Security:** threat-model checklist (sanitization, SHA pins, token scope, actor guards) reviewed line-by-line by an independent reviewer.
3. **Governance:** branch protection settings exported and matched against a documented baseline ruleset.
4. **Performance:** median time from CI failure → Copilot PR opened ≤ 10 min across F1–F4.
5. **Resilience:** demo can be reset and re-run in < 2 min via either `scripts/reset-demo.*` locally or the `reset-demo.yml` workflow remotely; `verify-clean` exits 0.
6. **Cost:** count Copilot premium requests per scenario, document in `DEMO.md`. Container artifact publishing uses `ghcr.io` (free for public repos) — no registry cost.

## Decisions & assumptions

- **Hand-built YAML, not `gh aw`** — production-grade signal for a regulated audience.
- **Single LLM engine: Copilot coding agent** — assumes audience already has Copilot Enterprise/Business.
- **Stack: .NET 10 minimal API** — current .NET version; xUnit + Docker are well-understood.
- **Container registry: `ghcr.io`** — free for public repos, authenticates with `GITHUB_TOKEN`, no extra account.
- **GitHub App, not PAT, for Copilot assignment** — non-negotiable for governance story.
- **Four failure scenarios** — F1/F2/F3 cover app/infra code; F4 covers the CI workflow itself. The responder workflow is intentionally NOT a target (chicken-and-egg).
- **Reset is a first-class feature** — local script, server-side workflow, baseline tag, and pre-flight verifier are all required, not optional.
- **In-scope:** the responder, the demo app, separation-of-duties enforcement, metrics emitter, demo runbook, reset tooling.
- **Out-of-scope:** post-deploy auto-remediation agents, change-management/ITSM integrations, security-scanner integrations, `gh aw` adaptation (mention only).

## Further considerations (open questions)

1. **Repo visibility:** public is required for free `ghcr.io` publishing and simplest Copilot coding agent enablement. Confirm OK to publish as public.
2. **Demo length target:** 5-min lightning vs. 20-min walkthrough vs. 60-min deep-dive? *Recommend: build for 20-min, with a 5-min cut.*
3. **Live or recorded for first showing?** *Recommend recorded backup + live attempt; Copilot agent latency is unpredictable.*
4. **Baseline tag strategy:** single `demo-baseline` tag moved on intentional updates, or dated `demo-baseline-YYYYMMDD` tags with the reset workflow taking the tag as input? *Recommend: single moving tag for simplicity; document the move procedure.*
