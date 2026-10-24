package config_test

import (
	"log/slog"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/MagnunAVF/heimdall-actions/internal/platform/config"
	"github.com/MagnunAVF/heimdall-actions/internal/platform/errs"
)

// env builds a lookup over a fixed map, so tests never read the process environment.
func env(vars map[string]string) config.LookupFunc {
	return func(key string) (string, bool) {
		v, ok := vars[key]
		return v, ok
	}
}

func TestString(t *testing.T) {
	tests := []struct {
		name string
		vars map[string]string
		want string
	}{
		{"set", map[string]string{"K": "value"}, "value"},
		{"unset uses default", map[string]string{}, "def"},
		{"empty uses default", map[string]string{"K": ""}, "def"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			e := config.New(env(tt.vars))
			assert.Equal(t, tt.want, e.String("K", "def"))
			require.NoError(t, e.Err())
		})
	}
}

func TestRequired(t *testing.T) {
	tests := []struct {
		name    string
		vars    map[string]string
		want    string
		wantErr bool
	}{
		{"set", map[string]string{"DSN": "postgres://x"}, "postgres://x", false},
		{"unset", map[string]string{}, "", true},
		{"empty", map[string]string{"DSN": ""}, "", true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			e := config.New(env(tt.vars))
			assert.Equal(t, tt.want, e.Required("DSN"))
			if !tt.wantErr {
				require.NoError(t, e.Err())
				return
			}
			require.ErrorIs(t, e.Err(), errs.ErrInvalidInput)
			assert.Contains(t, e.Err().Error(), "DSN")
		})
	}
}

func TestInt(t *testing.T) {
	tests := []struct {
		name    string
		vars    map[string]string
		want    int
		wantErr bool
	}{
		{"set", map[string]string{"PORT": "8080"}, 8080, false},
		{"negative", map[string]string{"PORT": "-1"}, -1, false},
		{"unset uses default", map[string]string{}, 3000, false},
		{"empty uses default", map[string]string{"PORT": ""}, 3000, false},
		{"not a number", map[string]string{"PORT": "eighty"}, 3000, true},
		{"float", map[string]string{"PORT": "80.5"}, 3000, true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			e := config.New(env(tt.vars))
			assert.Equal(t, tt.want, e.Int("PORT", 3000))
			if !tt.wantErr {
				require.NoError(t, e.Err())
				return
			}
			require.ErrorIs(t, e.Err(), errs.ErrInvalidInput)
			assert.Contains(t, e.Err().Error(), "PORT")
			assert.Contains(t, e.Err().Error(), "integer")
		})
	}
}

func TestDuration(t *testing.T) {
	tests := []struct {
		name    string
		vars    map[string]string
		want    time.Duration
		wantErr bool
	}{
		{"set", map[string]string{"TIMEOUT": "30s"}, 30 * time.Second, false},
		{"zero", map[string]string{"TIMEOUT": "0s"}, 0, false},
		{"unset uses default", map[string]string{}, 5 * time.Second, false},
		{"invalid", map[string]string{"TIMEOUT": "soon"}, 5 * time.Second, true},
		{"missing unit", map[string]string{"TIMEOUT": "30"}, 5 * time.Second, true},
		{"negative", map[string]string{"TIMEOUT": "-1s"}, 5 * time.Second, true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			e := config.New(env(tt.vars))
			assert.Equal(t, tt.want, e.Duration("TIMEOUT", 5*time.Second))
			if !tt.wantErr {
				require.NoError(t, e.Err())
				return
			}
			require.ErrorIs(t, e.Err(), errs.ErrInvalidInput)
			assert.Contains(t, e.Err().Error(), "TIMEOUT")
		})
	}
}

func TestURL(t *testing.T) {
	tests := []struct {
		name    string
		vars    map[string]string
		def     string
		want    string // "" means nil
		wantErr bool
	}{
		{"https", map[string]string{"ISSUER": "https://kc.example/realms/heimdall"}, "", "https://kc.example/realms/heimdall", false},
		{"http", map[string]string{"ISSUER": "http://localhost:8180/realms/heimdall"}, "", "http://localhost:8180/realms/heimdall", false},
		{"unset uses default", map[string]string{}, "http://localhost:8180", "http://localhost:8180", false},
		{"unset without default is nil", map[string]string{}, "", "", false},
		{"relative", map[string]string{"ISSUER": "/realms/heimdall"}, "", "", true},
		{"no host", map[string]string{"ISSUER": "https://"}, "", "", true},
		{"other scheme", map[string]string{"ISSUER": "ftp://kc.example"}, "", "", true},
		{"unparsable", map[string]string{"ISSUER": "http://[::1"}, "", "", true},
		{"invalid default", map[string]string{}, "not a url", "", true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			e := config.New(env(tt.vars))
			got := e.URL("ISSUER", tt.def)
			if tt.want == "" {
				assert.Nil(t, got)
			} else {
				require.NotNil(t, got)
				assert.Equal(t, tt.want, got.String())
			}
			if !tt.wantErr {
				require.NoError(t, e.Err())
				return
			}
			require.ErrorIs(t, e.Err(), errs.ErrInvalidInput)
			assert.Contains(t, e.Err().Error(), "ISSUER")
		})
	}
}

func TestLogLevel(t *testing.T) {
	tests := []struct {
		name    string
		vars    map[string]string
		want    slog.Level
		wantErr bool
	}{
		{"debug", map[string]string{"LOG_LEVEL": "debug"}, slog.LevelDebug, false},
		{"info", map[string]string{"LOG_LEVEL": "info"}, slog.LevelInfo, false},
		{"warn", map[string]string{"LOG_LEVEL": "warn"}, slog.LevelWarn, false},
		{"error", map[string]string{"LOG_LEVEL": "error"}, slog.LevelError, false},
		{"upper case", map[string]string{"LOG_LEVEL": "DEBUG"}, slog.LevelDebug, false},
		{"unset uses default", map[string]string{}, slog.LevelInfo, false},
		{"unknown", map[string]string{"LOG_LEVEL": "verbose"}, slog.LevelInfo, true},
		{"offset form rejected", map[string]string{"LOG_LEVEL": "info+2"}, slog.LevelInfo, true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			e := config.New(env(tt.vars))
			assert.Equal(t, tt.want, e.LogLevel("LOG_LEVEL", slog.LevelInfo))
			if !tt.wantErr {
				require.NoError(t, e.Err())
				return
			}
			require.ErrorIs(t, e.Err(), errs.ErrInvalidInput)
			assert.Contains(t, e.Err().Error(), "LOG_LEVEL")
		})
	}
}

func TestErrReportsEveryProblem(t *testing.T) {
	e := config.New(env(map[string]string{"PORT": "x", "TIMEOUT": "y"}))
	e.Required("DSN")
	e.Int("PORT", 0)
	e.Duration("TIMEOUT", 0)

	err := e.Err()
	require.ErrorIs(t, err, errs.ErrInvalidInput)
	for _, key := range []string{"DSN", "PORT", "TIMEOUT"} {
		assert.Contains(t, err.Error(), key)
	}
	unwrapped, ok := err.(interface{ Unwrap() []error })
	require.True(t, ok, "Err() must join the individual errors")
	require.Len(t, unwrapped.Unwrap(), 3)
	for _, one := range unwrapped.Unwrap() {
		assert.ErrorIs(t, one, errs.ErrInvalidInput)
	}
}

func TestErrNeverContainsTheValue(t *testing.T) {
	const secret = "s3cr3t-p4ss"
	e := config.New(env(map[string]string{
		"A": secret, "B": secret, "C": secret, "D": secret + "://x",
	}))
	e.Int("A", 0)
	e.Duration("B", 0)
	e.LogLevel("C", slog.LevelInfo)
	e.URL("D", "")

	require.Error(t, e.Err())
	assert.NotContains(t, e.Err().Error(), secret)
}

func TestErrNilWhenAllValid(t *testing.T) {
	e := config.New(env(map[string]string{
		"DSN": "postgres://x", "PORT": "8080", "TIMEOUT": "1s",
		"ISSUER": "https://kc.example", "LOG_LEVEL": "warn",
	}))
	e.Required("DSN")
	e.String("NAME", "api")
	e.Int("PORT", 0)
	e.Duration("TIMEOUT", 0)
	e.URL("ISSUER", "")
	e.LogLevel("LOG_LEVEL", slog.LevelInfo)

	require.NoError(t, e.Err())
}
