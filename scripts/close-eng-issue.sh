#!/usr/bin/env bash
# Close the ENG issue named by a merged PR's head branch. Used by
# .github/workflows/close-issue.yml.
#
#   scripts/close-eng-issue.sh chore/ENG-3-mcp https://github.com/o/r/pull/9
#
# Exit codes: 0 closed, or no ENG id in the branch; 1 resolution or gh failed (nothing closed);
# 2 usage error. Needs gh (authenticated) and jq.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
[ $# -eq 2 ] || { echo "close-eng-issue: usage: $(basename "$0") <head-branch> <pr-url>" >&2; exit 2; }
head=$1 pr_url=$2

# ENG-<n> is the id in the issue title, not the GitHub number (e.g. ENG-3 can be issue 2),
# so resolve it. claude/issue-<n> branches carry the GitHub number itself.
if [[ "$head" =~ ENG-([0-9]+) ]]; then
  id="ENG-${BASH_REMATCH[1]}"
  number=$("$here/eng-issue.sh" "$id")
elif [[ "$head" =~ ^claude/issue-([0-9]+) ]]; then
  number="${BASH_REMATCH[1]}"
  id=$("$here/eng-issue.sh" "$number")
else
  echo "No ENG-<n> in branch name; nothing to close."
  exit 0
fi
gh issue close "$number" --comment "$id done in $pr_url (merged into dev)."
