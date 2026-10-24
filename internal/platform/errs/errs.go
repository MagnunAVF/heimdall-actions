// Package errs holds the sentinel errors shared across packages. Wrap them with
// fmt.Errorf("doing x: %w", errs.ErrNotFound) and match them with errors.Is.
package errs

import "errors"

var (
	// ErrNotFound means the requested entity does not exist.
	ErrNotFound = errors.New("not found")
	// ErrConflict means the change clashes with existing state, such as a duplicate key.
	ErrConflict = errors.New("conflict")
	// ErrInvalidInput means a caller-supplied value failed validation.
	ErrInvalidInput = errors.New("invalid input")
	// ErrUnauthorized means the caller is not authenticated.
	ErrUnauthorized = errors.New("unauthorized")
	// ErrForbidden means the caller is authenticated but not allowed to do this.
	ErrForbidden = errors.New("forbidden")
	// ErrUnavailable means a dependency (database, cache, queue) cannot be reached.
	ErrUnavailable = errors.New("unavailable")
)
