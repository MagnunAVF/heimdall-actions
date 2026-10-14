# ENG-1: GitHub automation (plan 0.1a)

Status: approved 2026-10-14. Milestone M0, lane ci.

## Goal

Commit the GitHub automation that already exists locally (PR conventions, close-on-merge,
Claude workflows, PR template, `scripts/eng-issue.sh`). Move the inline workflow rules into
tested scripts. Pin actions to commit SHAs. Only repo collaborators can trigger `@claude`.

## Public API

- `scripts/eng-issue.sh ENG-<n> | <number>`: prints the GitHub number or ENG id. Exit 0
  resolved, 1 not found / ambiguous / gh failed, 2 usage. Unchanged.
- `scripts/pr-check.sh <base> <head> <title>`: the PR conventions. Exit 0 ok, 1 violation
  (reason on stderr), 2 usage. Rules:
  - into `main`: head must be `dev` or `hotfix/*`;
  - otherwise base must be `dev`;
  - exempt heads into dev: `main`, `release/*`, `docs/plan-M<k>`, `add-claude-github-actions-*`;
  - head must contain `ENG-<n>` that resolves to an issue, or be `claude/issue-<n>` whose issue
    has an ENG title;
  - title must end with `(ENG-<n>)` and must not contain `#<n>`.
- `scripts/close-eng-issue.sh <head> <pr-url>`: closes the issue named by the branch with
  the comment "ENG-<n> done in <pr-url> (merged into dev)." No ENG id: prints a note, exit 0.
  Resolution failure: exit 1, nothing closed. Usage: exit 2.
- `scripts/require-collaborator.sh <user>`: exit 0 if `<user>` is a collaborator of the repo
  (`gh api repos/{owner}/{repo}/collaborators/<user>`), 1 otherwise or if the check fails
  (fail closed), 2 usage.
- Workflows: `pr-conventions` calls `pr-check.sh`; `close-issue` calls `close-eng-issue.sh`;
  `claude` runs `require-collaborator.sh "$github.actor"` before the action;
  `claude-code-review` reviews every PR into dev on open and on every push.

## Tests

`scripts/eng-issue_test.sh` (exists, 19 cases): the spec for `eng-issue.sh`, unchanged.

New, all with a fake `gh` on PATH (no network):

| # | Script | Input | Expected |
|---|---|---|---|
| 1 | pr-check | `dev` `chore/ENG-1-x` `chore(ci): x (ENG-1)` | 0 |
| 2 | pr-check | same, title without `(ENG-1)` | 1, "must end with (ENG-1)" |
| 3 | pr-check | title containing `#4` | 1, "not #<n>" |
| 4 | pr-check | `dev` `docs/plan-M0`, no ENG title | 0 |
| 5 | pr-check | `feat/ENG-99-x`, no such issue | 1, "no issue title starts with \"ENG-99:\"" |
| 6 | pr-check | head `feature-x` | 1, "Branch must contain ENG-<n>" |
| 7 | pr-check | `claude/issue-2` (= ENG-3), title ends `(ENG-3)` | 0 |
| 8 | pr-check | `main` from `dev` / `hotfix/x` | 0 |
| 9 | pr-check | `main` from `feat/ENG-1-x` | 1, "must come from dev or hotfix/*" |
| 10 | pr-check | base `release` | 1, "must target dev" |
| 11 | close-eng-issue | `chore/ENG-3-x` (= issue 2) | `gh issue close 2`, comment has ENG-3 and the URL |
| 12 | close-eng-issue | `claude/issue-2` | closes 2 |
| 13 | close-eng-issue | `docs/plan-M0` | closes nothing, 0 |
| 14 | close-eng-issue | gh fails resolving | non-zero, nothing closed |
| 15 | require-collaborator | collaborator | 0 |
| 16 | require-collaborator | gh 404 (not a collaborator) | 1 |
| 17 | require-collaborator | gh fails (401) | 1 (fail closed) |
| 18 | require-collaborator | no args | 2 |

Checked on real PRs: `pr-conventions` on this PR (bad then good title), a
`claude-code-review` comment, ENG-2 closing on merge.

## Tasks (one commit each)

1. This plan.
2. `scripts/eng-issue.sh` and its test.
3. `scripts/pr-check.sh` + test; `pr-conventions.yml` calls it.
4. `scripts/close-eng-issue.sh` + test; `close-issue.yml` calls it.
5. `scripts/require-collaborator.sh` + test; `claude.yml`, `claude-code-review.yml` and the PR
   template; all actions pinned to SHAs.

## Approved decisions

- Workflow rules live in tested scripts (option B), not inline bash.
- Actions are pinned to commit SHAs (latest release of the major already in use), with the
  version in a trailing comment: checkout v4.4.0, setup-go v5.6.0, setup-node v4.4.0,
  claude-code-action v1.0.249.
- `claude-code-review` reviews on every push to a PR into dev.
- `@claude` is accepted only from repo collaborators, checked with the API before the action
  runs.
