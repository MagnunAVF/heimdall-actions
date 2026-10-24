// Package obs sets up observability shared by the binaries: structured JSON logging with
// log/slog.
package obs

import (
	"io"
	"log/slog"
)

// NewLogger returns a logger that writes one JSON object per line to w and drops records
// below level.
func NewLogger(w io.Writer, level slog.Level) *slog.Logger {
	return slog.New(slog.NewJSONHandler(w, &slog.HandlerOptions{Level: level}))
}
