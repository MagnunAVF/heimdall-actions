#!/usr/bin/env bash
cd "$CLAUDE_PROJECT_DIR" || exit 0
file=$(jq -r '.tool_input.file_path // empty')

case "$file" in
  */internal/store/queries/*.sql|*/internal/store/migrations/*.sql)
    [ -f sqlc.yaml ] || exit 0 # until M1 sets up sqlc
    if ! out=$(go tool sqlc generate 2>&1); then
      echo "sqlc generate failed:" >&2; echo "$out" >&2; exit 2
    fi ;;
  *.go)
    [ -f go.mod ] || exit 0 # until M1 creates the Go module
    golangci-lint fmt "$file" >/dev/null 2>&1
    if ! out=$(golangci-lint run "$(dirname "$file")" 2>&1); then
      echo "golangci-lint errors in $(dirname "$file"):" >&2; echo "$out" >&2; exit 2
    fi ;;
  */web/*.ts|*/web/*.tsx|*/web/*.js|*/web/*.jsx)
    [ -d web/node_modules ] || exit 0 # until M1 scaffolds web/ and runs npm ci
    (cd web && npx --no-install prettier --write "$file" >/dev/null 2>&1)
    if ! out=$(cd web && npx --no-install eslint "$file" 2>&1); then
      echo "eslint errors in $file:" >&2; echo "$out" >&2; exit 2
    fi ;;
  */web/*.css|*/web/*.json|*/web/*.md)
    [ -d web/node_modules ] || exit 0
    (cd web && npx --no-install prettier --write "$file" >/dev/null 2>&1) ;;
esac
exit 0
