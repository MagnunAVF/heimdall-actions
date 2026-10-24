# ENG-4: Go module, Makefile, CI check and platform package (plan 1.0)

Status: approved 2026-10-24. Milestone M1, lane ci.

## Goal

Create the Go module and the shared tooling every M1 issue builds on: `go.mod`, `.golangci.yml`,
a `Makefile` with every M1 target, `.github/workflows/ci.yml` running `make check` on every PR
into dev, and `internal/platform/{errs,config,obs}`. Targets whose inputs do not exist yet skip
with a message, so later issues never edit the Makefile. Acceptance: M1 exit criteria 1–2.

## Public API

`internal/platform/errs`: sentinel errors only.

```go
var (
    ErrNotFound     = errors.New("not found")
    ErrConflict     = errors.New("conflict")
    ErrInvalidInput = errors.New("invalid input")
    ErrUnauthorized = errors.New("unauthorized")
    ErrForbidden    = errors.New("forbidden")
    ErrUnavailable  = errors.New("unavailable")
)
```

`internal/platform/config`: env loader that collects every error. No global state; `main`
passes `os.LookupEnv`. Each binary defines its own `Config` struct and `Load(lookup)` on top.

```go
type LookupFunc func(key string) (string, bool)

type Env struct{ /* lookup + collected errors */ }
func New(lookup LookupFunc) *Env
func (e *Env) String(key, def string) string
func (e *Env) Required(key string) string                 // error if unset or empty
func (e *Env) Int(key string, def int) int
func (e *Env) Duration(key string, def time.Duration) time.Duration
func (e *Env) URL(key string, def string) *url.URL         // absolute http(s) only
func (e *Env) LogLevel(key string, def slog.Level) slog.Level
func (e *Env) Err() error // errors.Join of all problems, each wrapping errs.ErrInvalidInput
```

Empty values count as unset. Error messages name the key and the expected type, never the
value.

`internal/platform/obs`:

```go
func NewLogger(w io.Writer, level slog.Level) *slog.Logger // JSON handler
```

`Makefile`: `check` (= `lint test generate-check web-check script-tests`), `lint`, `test`
(`go test -race ./...`), `test-integration` (`-tags integration`), `generate`, `up`, `down`.
Tools are overridable variables (`GOLANGCI_LINT`, `SQLC ?= go tool sqlc`, `NPM`,
`COMPOSE ?= docker compose -p heimdall -f deploy/docker-compose.yml`). Skips with
`skip: <reason>` and exit 0: `generate`/`generate-check` without `sqlc.yaml`, `web-check`
without `web/package.json`, `up`/`down` without `deploy/docker-compose.yml`. `generate-check`
fails when `git status --porcelain internal/store/db` is not empty after `generate`. `up` is
`up -d --wait`; `down` is `down -v`. `make check` never installs npm packages.

`.github/workflows/ci.yml`: job `ci` on `pull_request` into dev and `push` to dev,
`contents: read`. Checkout, setup-go from `go.mod`, golangci-lint v2 via its pinned action,
setup-node and `npm ci` only if `web/package.json` exists, then `make check`. Every action is
pinned to a commit SHA with a `# vX.Y.Z` comment.

`.golangci.yml` (v2): standard linters plus `errorlint`, `gosec`, `bodyclose`, `noctx`,
`sloglint`, `testifylint`, `misspell`, `gochecknoglobals`, `gochecknoinits`; formatters `gofmt`
and `goimports` (local prefix = module path).

`go.mod`: `github.com/MagnunAVF/heimdall-actions`, `go 1.27.0`; tool deps
`github.com/sqlc-dev/sqlc/cmd/sqlc` and `github.com/pressly/goose/v3/cmd/goose`; `testify`.

## Tests

| # | Package / file | Case | Expect |
|---|---|---|---|
| 1 | errs | each sentinel wrapped with `fmt.Errorf("x: %w")` | `errors.Is` true |
| 2 | errs | sentinels are distinct | `errors.Is(a, b)` false for a ≠ b |
| 3 | config | value set | returned |
| 4 | config | unset or empty | default |
| 5 | config | `Required` unset or empty | error names the key |
| 6 | config | `Int` non-numeric | error names key and type |
| 7 | config | `Duration` invalid or negative | error |
| 8 | config | `URL` relative, non-http scheme, unparsable | error |
| 9 | config | `LogLevel` debug/info/warn/error, any case | parsed; unknown → error |
| 10 | config | several bad keys | `Err()` reports all, each `errors.Is(ErrInvalidInput)` |
| 11 | config | invalid value | error text never contains the value |
| 12 | config | all valid | `Err()` nil |
| 13 | obs | one line | valid JSON with `time`, `level`, `msg`, attrs |
| 14 | obs | level info | debug lines dropped |
| 15 | scripts/makefile_test.sh | `generate`, `web-check`, `up`, `down` without inputs | exit 0, `skip:` |
| 16 | 〃 | `generate-check` with a stub that dirties `internal/store/db` | fails |
| 17 | 〃 | `web-check` with `web/package.json` | runs npm `lint`, `typecheck`, `test` |
| 18 | 〃 | `up` / `down` with the compose file | `up -d --wait` / `down -v` |
| 19 | 〃 | a failing step (lint stub, `scripts/x_test.sh`) | `make check` non-zero |
| 20 | scripts/actions-pinned_test.sh | every `uses:` in `.github/workflows/*.yml` | 40-hex SHA + `# v` comment |

## Tasks (one commit each)

1. docs: this plan and the M1 Decisions lines.
2. `go.mod`, tool deps, `.golangci.yml`, `internal/platform/errs` (tests 1–2).
3. `internal/platform/config` (tests 3–12).
4. `internal/platform/obs` (tests 13–14).
5. `Makefile` and `scripts/makefile_test.sh` (tests 15–19).
6. `.github/workflows/ci.yml` and `scripts/actions-pinned_test.sh` (test 20).

After merge: make `ci` and `pr-conventions` required status checks on dev.

## Approved decisions

- Config is a generic env loader; each binary defines its own struct.
- Six sentinel errors: NotFound, Conflict, InvalidInput, Unauthorized, Forbidden, Unavailable.
- `make test` runs with `-race`.
- CI runs `npm ci`; `make check` never installs packages.
- Workflows are checked for SHA-pinned actions by `scripts/actions-pinned_test.sh`.
