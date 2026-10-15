Issue: ENG-

## What

<one paragraph: what changed and why>

## How

- <key decisions; link docs/plans/ENG-<n>-\*.md if there is one>

## Tests

- <new or changed tests / table rows>

## Checklist

- [ ] Base branch is `dev` (or `main` only for a release/hotfix)
- [ ] Title ends with `(ENG-<n>)`; issues are written ENG-<n>, never #<n>
- [ ] `make check` passes
- [ ] No existing tests modified; no committed migrations edited
- [ ] sqlc code regenerated if queries or migrations changed
- [ ] No secrets, .env files or kubeconfigs committed
- [ ] Decisions recorded in docs/milestones/M<k>.md (and an ADR if significant)
