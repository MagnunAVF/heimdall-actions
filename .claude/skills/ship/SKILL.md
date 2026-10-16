---
name: ship
description: Commit the current work, push the branch, and open a pull request into dev for an ENG issue.
argument-hint: "ENG-<n>"
disable-model-invocation: true
---

Ship the work for $ARGUMENTS. ENG-<n> is the id in the issue title, not the GitHub issue number:
resolve it first with `scripts/eng-issue.sh $ARGUMENTS` (prints <number>).

1. Run `make check`. If it fails, stop and report.
2. The current branch must contain "ENG-<n>" (the title id, same as $ARGUMENTS) and must not be
   dev or main. Otherwise stop.
3. Review `git status` and `git diff --stat origin/dev...HEAD`. No .env files, credentials,
   kubeconfigs or edits to committed migrations. List any file unrelated to the issue and ask
   before including it.
4. Commit any remaining task with a conventional message ending in "(ENG-<n>, task k/m)", one
   commit per task (CLAUDE.md "Commits"). The PR title ends in "(ENG-<n>)".
5. `git push -u origin HEAD`.
6. `gh pr create --base dev --milestone "<current milestone title>" --title "<type>(<scope>): <summary> (ENG-<n>)"`
   with a body following .github/pull_request_template.md, starting with "Issue: ENG-<n>".
   Never write "#<n>" for an issue and don't use closing keywords.
7. Print the PR URL.
