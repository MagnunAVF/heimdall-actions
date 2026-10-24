package errs_test

import (
	"fmt"
	"testing"

	"github.com/stretchr/testify/assert"

	"github.com/MagnunAVF/heimdall-actions/internal/platform/errs"
)

func sentinels() map[string]error {
	return map[string]error{
		"ErrNotFound":     errs.ErrNotFound,
		"ErrConflict":     errs.ErrConflict,
		"ErrInvalidInput": errs.ErrInvalidInput,
		"ErrUnauthorized": errs.ErrUnauthorized,
		"ErrForbidden":    errs.ErrForbidden,
		"ErrUnavailable":  errs.ErrUnavailable,
	}
}

func TestSentinelsSurviveWrapping(t *testing.T) {
	for name, sentinel := range sentinels() {
		t.Run(name, func(t *testing.T) {
			wrapped := fmt.Errorf("outer: %w", fmt.Errorf("inner: %w", sentinel))
			assert.ErrorIs(t, wrapped, sentinel)
		})
	}
}

func TestSentinelsAreDistinct(t *testing.T) {
	all := sentinels()
	for nameA, a := range all {
		for nameB, b := range all {
			if nameA == nameB {
				continue
			}
			assert.NotErrorIs(t, a, b, "%s must not match %s", nameA, nameB)
		}
	}
}
