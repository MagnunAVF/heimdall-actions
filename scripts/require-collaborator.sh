#!/usr/bin/env bash
# Fail unless a GitHub user is a collaborator of this repository. Used by
# .github/workflows/claude.yml so only collaborators can trigger @claude.
#
#   scripts/require-collaborator.sh "$GITHUB_ACTOR"
#
# Exit codes: 0 collaborator; 1 not a collaborator, or the check failed (fails closed);
# 2 usage error. Needs gh (authenticated). Set GH_REPO to target a repo other than the current one.
set -euo pipefail

usage() { echo "require-collaborator: usage: $(basename "$0") <github-login>" >&2; exit 2; }
[ $# -eq 1 ] || usage
user=$1
# GitHub logins are letters, digits and hyphens; apps act as "<name>[bot]".
[[ "$user" =~ ^[A-Za-z0-9-]+(\[bot\])?$ ]] || usage

if ! gh api "repos/{owner}/{repo}/collaborators/$user" --silent; then
  echo "require-collaborator: $user is not a collaborator of this repository (or the check failed)" >&2
  exit 1
fi
