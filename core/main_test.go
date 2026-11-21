package core

import (
	"fmt"
	"os"
	"testing"

	"github.com/metacubex/mihomo/component/profile/cachefile"
	"github.com/metacubex/mihomo/constant"
)

// TestMain opens the cache file, a process-wide singleton the Core opens once
// under whatever home is current, in a directory of its own. Opened under a
// test's TempDir instead, the open file would keep Windows from removing it.
func TestMain(m *testing.M) {
	dir, err := os.MkdirTemp("", "core-test-cache")
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	previous := constant.Path.HomeDir()
	constant.SetHomeDir(dir)
	cache := cachefile.Cache()
	constant.SetHomeDir(previous)

	code := m.Run()

	if cache.DB != nil {
		_ = cache.Close()
	}
	_ = os.RemoveAll(dir)
	os.Exit(code)
}
