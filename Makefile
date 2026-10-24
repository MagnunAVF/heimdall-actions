# Every target that CI, the hooks and CLAUDE.md rely on. Targets whose inputs do not exist yet
# print "skip: <reason>" and succeed, so later issues never edit this file.
# Tests: scripts/makefile_test.sh

GO            ?= go
GOLANGCI_LINT ?= golangci-lint
SQLC          ?= $(GO) tool sqlc
NPM           ?= npm
COMPOSE       ?= docker compose -p heimdall -f infra/local/docker-compose.yml

# The hooks test is listed by name so that losing it fails the check instead of skipping it.
SCRIPT_TESTS := $(wildcard scripts/*_test.sh) .claude/hooks/hooks_test.sh

.PHONY: check lint test test-integration generate generate-check web-check script-tests up down

## check: everything CI runs. Needs no running services.
check: lint test generate-check web-check script-tests

lint:
	$(GOLANGCI_LINT) run ./...

test:
	$(GO) test -race ./...

## test-integration: tests behind //go:build integration. Needs `make up`.
test-integration:
	$(GO) test -race -tags integration -count=1 ./...

generate:
ifeq ($(wildcard sqlc.yaml),)
	@echo "skip: generate (no sqlc.yaml yet)"
else
	$(SQLC) generate
endif

## generate-check: fails when the committed sqlc output differs from a fresh generate.
generate-check:
ifeq ($(wildcard sqlc.yaml),)
	@echo "skip: generate-check (no sqlc.yaml yet)"
else
	$(SQLC) generate
	@if [ -n "$$(git status --porcelain -- internal/store/db)" ]; then \
		echo "internal/store/db is out of date: run make generate and commit the result" >&2; \
		git status --porcelain -- internal/store/db >&2; \
		exit 1; \
	fi
endif

## web-check: lint, typecheck and tests for web/. Expects `npm ci` to have run.
web-check:
ifeq ($(wildcard web/package.json),)
	@echo "skip: web-check (no web/package.json yet)"
else
	cd web && $(NPM) run lint && $(NPM) run typecheck && $(NPM) run test
endif

## script-tests: every scripts/*_test.sh and the Claude Code hooks test.
script-tests:
	@failed=; \
	for t in $(SCRIPT_TESTS); do bash "$$t" || failed="$$failed $$t"; done; \
	if [ -n "$$failed" ]; then echo "failed:$$failed" >&2; exit 1; fi

up:
ifeq ($(wildcard infra/local/docker-compose.yml),)
	@echo "skip: up (no infra/local/docker-compose.yml yet)"
else
	$(COMPOSE) up -d --wait
endif

## down: stops the stack and deletes its volumes, so the next `make up` starts empty.
down:
ifeq ($(wildcard infra/local/docker-compose.yml),)
	@echo "skip: down (no infra/local/docker-compose.yml yet)"
else
	$(COMPOSE) down -v
endif
