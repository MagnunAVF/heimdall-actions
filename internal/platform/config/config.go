// Package config reads configuration from environment variables. Each binary defines its own
// Config struct and fills it through an Env, then checks Env.Err once:
//
//	e := config.New(os.LookupEnv)
//	cfg := Config{Addr: e.String("HEIMDALL_ADDR", ":8080"), DSN: e.Required("HEIMDALL_DSN")}
//	if err := e.Err(); err != nil { ... }
//
// Empty values count as unset. Error messages name the variable and what was expected but
// never repeat the value, so a misconfigured secret does not end up in logs.
package config

import (
	"errors"
	"fmt"
	"log/slog"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/MagnunAVF/heimdall-actions/internal/platform/errs"
)

// LookupFunc returns the value of an environment variable and whether it is set.
// os.LookupEnv satisfies it.
type LookupFunc func(key string) (string, bool)

// Env reads typed values through a LookupFunc and collects every problem it finds.
type Env struct {
	lookup LookupFunc
	errs   []error
}

// New returns an Env that reads variables through lookup.
func New(lookup LookupFunc) *Env {
	return &Env{lookup: lookup}
}

// String returns the value of key, or def when it is unset.
func (e *Env) String(key, def string) string {
	if v, ok := e.get(key); ok {
		return v
	}
	return def
}

// Required returns the value of key and records an error when it is unset.
func (e *Env) Required(key string) string {
	v, ok := e.get(key)
	if !ok {
		e.fail(key, "is required")
	}
	return v
}

// Int returns key parsed as a base-10 integer, or def when it is unset or invalid.
func (e *Env) Int(key string, def int) int {
	v, ok := e.get(key)
	if !ok {
		return def
	}
	n, err := strconv.Atoi(v)
	if err != nil {
		e.fail(key, "must be an integer")
		return def
	}
	return n
}

// Duration returns key parsed by time.ParseDuration (e.g. "30s"), or def when it is unset or
// invalid. Negative durations are invalid.
func (e *Env) Duration(key string, def time.Duration) time.Duration {
	v, ok := e.get(key)
	if !ok {
		return def
	}
	d, err := time.ParseDuration(v)
	if err != nil || d < 0 {
		e.fail(key, `must be a non-negative duration such as "30s"`)
		return def
	}
	return d
}

// URL returns key, or def when it is unset, parsed as an absolute http or https URL. It
// returns nil when both are empty, and nil with an error when the URL is invalid.
func (e *Env) URL(key, def string) *url.URL {
	raw := e.String(key, def)
	if raw == "" {
		return nil
	}
	u, err := url.Parse(raw)
	if err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Host == "" {
		e.fail(key, "must be an absolute http or https URL")
		return nil
	}
	return u
}

// LogLevel returns key as one of debug, info, warn or error (any case), or def when it is
// unset or invalid.
func (e *Env) LogLevel(key string, def slog.Level) slog.Level {
	v, ok := e.get(key)
	if !ok {
		return def
	}
	switch strings.ToLower(v) {
	case "debug":
		return slog.LevelDebug
	case "info":
		return slog.LevelInfo
	case "warn":
		return slog.LevelWarn
	case "error":
		return slog.LevelError
	}
	e.fail(key, "must be one of debug, info, warn, error")
	return def
}

// Err returns every problem found so far, joined, or nil. Each one wraps errs.ErrInvalidInput.
func (e *Env) Err() error {
	return errors.Join(e.errs...)
}

func (e *Env) get(key string) (string, bool) {
	v, ok := e.lookup(key)
	return v, ok && v != ""
}

func (e *Env) fail(key, problem string) {
	e.errs = append(e.errs, fmt.Errorf("%w: %s %s", errs.ErrInvalidInput, key, problem))
}
