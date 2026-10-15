# ENG-2: Claude Code core config (plan 0.1b)

Status: approved 2026-10-15. Milestone M0, lane tooling.

## Goal

Commit the Claude Code configuration that already exists locally: `CLAUDE.md`,
`.claude/settings.json`, the four hooks, the reviewer agent, the six skills,
`.vscode/extensions.json` and the `.gitignore` changes. Clean up `settings.json` (no one-off,
duplicate or machine-specific entries), cover the hooks with a test script, and stop CLAUDE.md
from claiming M0 is done before it closes.

## Public API

No new code API. The hook contract (hooks read the tool payload as JSON on stdin; exit 2 blocks
the tool call and shows stderr to Claude):

- `.claude/hooks/before-bash.sh` (PreToolUse, Bash): reads `.tool_input.command`. Exit 2 for
  kubectl commands that change state (`apply`, `create`, `delete`, `edit`, `patch`, `replace`,
  `scale`, `exec`, `drain`, `cordon`, `label`, `annotate`, `rollout`, `set`) without
  `--context kind-heimdall`, and for `helm install|upgrade|uninstall|rollback|delete` without
  `--kube-context kind-heimdall`. Otherwise 0.
- `.claude/hooks/before-edit.sh` (PreToolUse, Edit|Write): reads `.tool_input.file_path`.
  Exit 2 for `.env` / `.env.*` at any depth, `internal/store/db/*` (sqlc output) and
  migrations in `internal/store/migrations/` that are already committed. Otherwise 0.
- `.claude/hooks/after-edit.sh` (PostToolUse, Edit|Write): `sqlc generate` after SQL edits,
  golangci-lint fmt/run after Go edits, prettier/eslint after web/ edits. Each step is skipped
  while its prerequisite (`sqlc.yaml`, `go.mod`, `web/node_modules`) is missing. Exit 2 on
  failure.
- `.claude/hooks/stop-check.sh` (Stop): when the tree has changes and the Makefile has a
  `check:` target, runs `make check`; exit 2 with the tail of the output if it fails. Exit 0
  when `stop_hook_active` is true.

`.claude/settings.json` permissions:
- `Bash(git status)` and `Bash(git status *)` are replaced by a single `Bash(git status:*)`.
- The one-off `sed -i ''` entry and `additionalDirectories` are removed.
- `bash scripts/*_test.sh` and `bash .claude/hooks/hooks_test.sh` are allowed. These replace
  the single eng-issue test entry.

## Tests

`.claude/hooks/hooks_test.sh` (run: `bash .claude/hooks/hooks_test.sh`). Each case runs
against a temporary git repo with no go.mod, Makefile or sqlc.yaml (no network, no cluster).

| # | Hook / file | Input | Expected |
|---|---|---|---|
| 1 | all 4 hooks | file is executable | yes |
| 2 | all 4 hooks | `{}` in a bare repo | 0 |
| 3 | before-bash | `kubectl apply -f x.yaml` | 2, stderr names `--context kind-heimdall` |
| 4 | before-bash | `kubectl --context kind-heimdall apply -f x.yaml` | 0 |
| 5 | before-bash | `kubectl --context=kind-heimdall delete pod x` | 0 |
| 6 | before-bash | `kubectl --context kind-other apply -f x` | 2 |
| 7 | before-bash | `kubectl get pods` | 0 |
| 8 | before-bash | `helm install x y` / with `--kube-context kind-heimdall` | 2 / 0 |
| 9 | before-edit | `.env`, `web/.env.local` | 2 |
| 10 | before-edit | `internal/store/db/x.go` | 2 |
| 11 | before-edit | committed migration / untracked new migration | 2 / 0 |
| 12 | before-edit | `internal/api/x.go`, `.env.example` | 0 |
| 13 | after-edit | `x.go` without go.mod; query `.sql` without sqlc.yaml | 0 |
| 14 | stop-check | `stop_hook_active: true`; dirty tree without Makefile | 0 |
| 15 | settings.json | valid JSON | ok |
| 16 | settings.json | no duplicate or overlapping allow entries, no `sed -i`, no `/Users/`, no `additionalDirectories` | ok |

Rows 1–14 describe hooks that already exist. Row 16 fails until task 3.

## Tasks

1. docs: this plan and the M0 Decisions lines.
2. hooks: commit `.claude/hooks/*.sh` with `hooks_test.sh`.
3. settings: clean up `.claude/settings.json` (row 16 goes green); commit `.gitignore` and
   `.vscode/extensions.json`.
4. agent, skills, CLAUDE.md: commit `.claude/agents/reviewer.md`, the six skills and
   `CLAUDE.md` with "Current focus" saying M0 is in progress.

## Decisions

- 2026-10-15: A single `Bash(git status:*)` replaces the `git status` / `git status *` pair.
- 2026-10-15: All repo test scripts (`scripts/*_test.sh`, `.claude/hooks/hooks_test.sh`) are
  allowed without a prompt.
- 2026-10-15: `hooks_test.sh` is not wired into CI here (that is the ci lane). M1's
  `make check` runs it.

## Risks

- `before-bash.sh` checks `--context` against the whole command string, not each kubectl
  call. As a result, `kubectl --context kind-heimdall get x && kubectl apply -f y` is not
  blocked. Accepted for now; the `ask` rule on `kubectl apply/delete/exec` still prompts.
