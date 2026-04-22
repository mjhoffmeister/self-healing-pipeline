# Copilot cloud agent instructions — `self-healing-demo`

These instructions are read by the Copilot cloud agent (formerly "Copilot coding agent") whenever it works in this repo.
Keep this file short, prescriptive, and verifiable in CI.

## Project shape

- **Stack:** .NET 10 minimal API (`src/Api`) + xUnit tests (`tests/Api.Tests`).
- **Solution file:** `SelfHealingDemo.sln`.
- **Container:** `Dockerfile` at repo root, multi-stage, publishes to `ghcr.io`.
- **Pipelines:**
  - `.github/workflows/ci.yml` — primary build/test/publish.
  - `.github/workflows/self-heal.yml` — responder. **Do not modify unless the assigned issue is explicitly about the responder.**
  - `.github/workflows/required-checks.yml` — separation-of-duties check.
  - `.github/workflows/reset-demo.yml` — server-side demo reset.

## Mandatory pre-PR checks

Run these locally before opening any PR. CI will fail the PR otherwise.

```bash
dotnet format SelfHealingDemo.sln
dotnet build  SelfHealingDemo.sln --configuration Release
dotnet test   SelfHealingDemo.sln --configuration Release
```

If you touched the `Dockerfile`:

```bash
docker build -t selfhealing-demo:local .
```

## Coding conventions

- C#: nullable enabled, implicit usings on, `TreatWarningsAsErrors=true`. Do not weaken these.
- Pure logic lives in dedicated classes (e.g. `GreetingService`) so it stays unit-testable without hosting.
- New endpoints: register in `Program.cs`, delegate to a service class, add an xUnit theory.
- Public types/members get XML doc comments only when behaviour is non-obvious.
- No new third-party NuGet packages without justification in the PR description.

## Workflow / supply-chain rules (non-negotiable)

- **Pin every third-party action by full commit SHA**, with a trailing `# vX.Y.Z` comment. Never pin by tag or branch.
- **First-party only** in `self-heal.yml` and `required-checks.yml` — use `actions/*`, `gh` CLI, and inline shell. No marketplace actions.
- **No PATs.** Use `secrets.GITHUB_TOKEN` for in-repo work and a runtime-minted GitHub App installation token (`actions/create-github-app-token` with `vars.APP_ID` + `secrets.APP_PRIVATE_KEY`) for cross-identity work. No long-lived stored installation tokens.
- **Minimum permissions.** Each job declares its own `permissions:` block.
- **Loop prevention.** Any new responder logic must guard `github.actor != 'copilot-swe-agent[bot]'`.

## When the assigned issue is a CI failure

1. Read the **Failed job** and **Last 50 log lines** in the issue body.
2. Reproduce locally with the commands above.
3. Make the smallest possible change to turn the failure green.
4. **Do not** modify `self-heal.yml`, `required-checks.yml`, or `CODEOWNERS` unless the issue explicitly names them.
5. Open a single PR. Reference the issue (`Fixes #N`). Keep the diff focused.

## When the assigned issue is about the CI workflow itself (scenario F4)

- Editing `.github/workflows/ci.yml` is allowed and expected.
- After your PR opens, a maintainer must click **"Approve and run workflows"** before CI runs on it. This is normal and called out in `DEMO.md`.

## Forbidden

- Disabling tests, formatters, or `TreatWarningsAsErrors`.
- Adding `continue-on-error: true` anywhere in CI.
- Removing or weakening branch-protection-related workflows.
- Auto-merging your own PRs.
