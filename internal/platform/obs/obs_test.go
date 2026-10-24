package obs_test

import (
	"bytes"
	"encoding/json"
	"log/slog"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/MagnunAVF/heimdall-actions/internal/platform/obs"
)

func TestNewLoggerWritesJSON(t *testing.T) {
	var buf bytes.Buffer
	log := obs.NewLogger(&buf, slog.LevelInfo)
	require.NotNil(t, log)

	log.Info("job created", "execution_id", "0b7c2f4e-1d0c-4c43-9a44-9f0e3c1a2b3d", "attempt", 2)

	var line map[string]any
	require.NoError(t, json.Unmarshal(buf.Bytes(), &line), "output: %q", buf.String())
	assert.Contains(t, line, "time")
	assert.Equal(t, "INFO", line["level"])
	assert.Equal(t, "job created", line["msg"])
	assert.Equal(t, "0b7c2f4e-1d0c-4c43-9a44-9f0e3c1a2b3d", line["execution_id"])
	assert.InDelta(t, 2, line["attempt"], 0)
}

func TestNewLoggerFiltersByLevel(t *testing.T) {
	tests := []struct {
		name  string
		level slog.Level
		want  []string
	}{
		{"debug keeps everything", slog.LevelDebug, []string{"d", "i", "w", "e"}},
		{"info drops debug", slog.LevelInfo, []string{"i", "w", "e"}},
		{"error keeps only errors", slog.LevelError, []string{"e"}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var buf bytes.Buffer
			log := obs.NewLogger(&buf, tt.level)
			require.NotNil(t, log)
			log.Debug("d")
			log.Info("i")
			log.Warn("w")
			log.Error("e")

			var got []string
			for _, raw := range strings.Split(strings.TrimSpace(buf.String()), "\n") {
				if raw == "" {
					continue
				}
				var line map[string]any
				require.NoError(t, json.Unmarshal([]byte(raw), &line))
				got = append(got, line["msg"].(string))
			}
			assert.Equal(t, tt.want, got)
		})
	}
}
