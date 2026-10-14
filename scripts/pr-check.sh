#!/usr/bin/env bash
# Check a pull request's base branch, head branch and title against the conventions in
# CLAUDE.md. Used by .github/workflows/pr-conventions.yml.
#
#   scripts/pr-check.sh dev chore/ENG-1-ci "chore(ci): add workflows (ENG-1)"
#
# Exit codes: 0 ok, 1 violation (reason on stderr), 2 usage error.
# Needs gh (authenticated) and jq, through scripts/eng-issue.sh.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
fail() { echo "pr-check: $1" >&2; exit 1; }
[ $# -eq 3 ] || { echo "pr-check: usage: $(basename "$0") <base> <head> <title>" >&2; exit 2; }
base=$1 head=$2 title=$3

if [ "$base" = "main" ]; then
  [[ "$head" == "dev" || "$head" == hotfix/* ]] || fail "PRs into main must come from dev or hotfix/*"
  exit 0
fi
[ "$base" = "dev" ] || fail "PRs must target dev"

# Exceptions into dev: back-merge from main, release notes, milestone plans (docs/plan-M<k>,
# no ENG id so close-issue closes nothing), the Claude app's own setup PR
[[ "$head" == "main" || "$head" == release/* || "$head" =~ ^docs/plan-M[0-9]+$ || "$head" == add-claude-github-actions-* ]] && exit 0

# ENG-<n> is the id in the issue title, not the GitHub number (e.g. ENG-3 can be issue 2).
# claude/issue-<n> branches carry the GitHub number, so map it to its ENG id.
if [[ "$head" =~ ENG-([0-9]+) ]]; then
  id="ENG-${BASH_REMATCH[1]}"
  "$here/eng-issue.sh" "$id" >/dev/null || fail "Branch names $id, but no issue title starts with \"$id:\""
elif [[ "$head" =~ ^claude/issue-([0-9]+) ]]; then
  id=$("$here/eng-issue.sh" "${BASH_REMATCH[1]}") || fail "Issue ${BASH_REMATCH[1]} has no ENG-<n> title"
else
  fail "Branch must contain ENG-<n>, e.g. feat/ENG-12-sanitize"
fi
[[ "$title" =~ \(${id}\)$ ]] || fail "PR title must end with (${id})"
if [[ "$title" =~ \#[0-9]+ ]]; then fail "Write issues as ENG-<n>, not #<n>"; fi
exit 0
