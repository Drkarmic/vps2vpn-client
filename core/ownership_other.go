//go:build !(darwin || linux) || android

package core

import "os"

// handOverPrivate: see ownership_unix.go. Here the Core runs as the app user
// (or in its process), so owner-only is enough.
func handOverPrivate(file *os.File) error { return file.Chmod(0o600) }

func initOwnership(homeDir string) {}

func scheduleReclaimOwnership() {}

func reclaimDirOwnership(path string) {}
