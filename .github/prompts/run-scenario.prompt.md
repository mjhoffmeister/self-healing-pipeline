---
mode: agent
description: Fire off a self-healing demo scenario (F1, F2, F3, or F4) end-to-end from chat.
---

# Run a self-healing demo scenario

You are wrapping [scripts/Run-Scenario.ps1](../../scripts/Run-Scenario.ps1) so the user can launch a demo scenario without leaving chat.

## Inputs

The user message should contain a scenario id. Accept any of: `F1`, `F2`, `F3`, `F4` (case-insensitive).

If the message also contains any of these tokens, forward them as flags:

| User says            | Script flag       |
|----------------------|-------------------|
| `dry`, `dry-run`, `dry run` | `-DryRun`         |
| `skip-verify`, `no verify`  | `-SkipVerify`     |
| `no-pr`, `no pr`            | `-NoPr`           |

## What to do

1. If no scenario id is present, ask the user to pick one (`F1`, `F2`, `F3`, or `F4`) and stop. Do not invent one.
2. Otherwise, run the wrapper in the integrated terminal exactly once:

   ```powershell
   pwsh -NoProfile -File ./scripts/Run-Scenario.ps1 -Scenario <ID> [flags]
   ```

   Use `mode=sync` and a generous timeout (the script pushes to GitHub and calls `gh pr create`).
3. After it returns:
   - On success, print the PR URL from the script's output and remind the user to watch the **Issues** tab for the `[self-heal] CI failed:` issue (~2 min).
   - On failure, show the last ~20 lines of stderr and stop. Do not attempt fixes — `Run-Scenario.ps1` is intentionally fail-fast.
4. Do not modify any files. Do not call any other tools beyond running the terminal command and reading its output.

## Hard rules

- Never run more than one scenario per invocation.
- Never push to `main` directly. The script always branches first; if it doesn't, treat that as a bug and stop.
- Do not pass `-SkipVerify` unless the user explicitly asked for it.
- Do not edit `Run-Scenario.ps1` from this prompt — if behaviour needs to change, tell the user to edit the script and re-run.
