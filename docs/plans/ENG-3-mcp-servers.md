# ENG-3: MCP servers for AI-assisted development (plan 0.1c)

Status: approved 2026-10-15. Milestone M0, lane tooling.

## Goal

Decide which MCP servers this repo uses. Outcome: none in M0. GitHub access stays on the `gh`
CLI, and every `gh` write action asks for approval. Exit criterion 7 is met by dropping the
servers with a dated line in the M0 Decisions.

## Candidates reviewed (2026-10-15)

- GitHub: hosted read-only server (`https://api.githubcopilot.com/mcp/readonly`) or the Docker
  image `ghcr.io/github/github-mcp-server:v1.14.0`. Dropped: `gh` already covers it, and the
  existing permission rules for `gh` keep writes behind a prompt.
- PostgreSQL: `@modelcontextprotocol/server-postgres` is deprecated on npm and its read-only
  mode can be bypassed; `crystaldba/postgres-mcp` has had no release since v0.3.0 (2025-05).
  Dropped: no local Postgres exists before M1's `make up`.
- Kubernetes: `kubernetes-mcp-server@0.0.67` supports `read_only`, but it can't be pinned to
  one context except through a dedicated kubeconfig. Dropped: no `kind-heimdall` cluster exists
  before M1's `make kind-up`.

Postgres and Kubernetes can be proposed again once M1 lands compose and kind.

## Public API

No code. `.claude/settings.json` permissions:

- `Bash(gh issue *)` and `Bash(gh label *)` (which allowed writes without a prompt) are replaced
  by `Bash(gh issue view:*)`, `Bash(gh issue list:*)` and `Bash(gh label list:*)`.
- Every other `gh` write (`issue create/edit/close/comment/reopen`, `label create/edit/delete`,
  `pr create/merge/edit/comment`, `api`) asks, through an explicit `ask` entry or the default.
- No `.mcp.json`; no CLAUDE.md change.

## Tests

Appended to `.claude/hooks/hooks_test.sh` (existing checks unchanged):

| # | Case | Expect |
|---|---|---|
| 17 | No allow entry covers a `gh` write: no `gh issue`/`gh label`/`gh pr` wildcard, no `gh api`, nothing with `create`, `edit`, `close`, `comment`, `delete`, `merge` or `reopen` | pass |
| 18 | `gh issue view`, `gh issue list` and `gh label list` are allowed | pass |

Row 17 fails against the settings on dev before this change.

## Tasks

1. Docs: this plan and the M0 Decisions lines (closes Open question 1).
2. Settings tests 17–18 (red), then the permission change (green).

## Approved decisions

- 2026-10-15: No MCP servers in M0; GitHub stays on `gh`; Postgres and Kubernetes revisit in M1.
- 2026-10-15: `gh` read commands are allowed; `gh` writes always ask.
- 2026-10-15: No `.mcp.json` checker script.
