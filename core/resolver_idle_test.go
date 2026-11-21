package core

import (
	"bytes"
	"runtime"
	"testing"
	"time"
)

// Frames of a DNS lookup still in flight. Mihomo keeps resolver settings such
// as resolver.DisableIPv6 in plain package variables, and parsing or updating
// a config rewrites them. A lookup a previous test left running would read
// them concurrently, which the race detector reports against whichever test
// writes next (issue #60).
var resolverBusyFrames = [][]byte{
	[]byte("github.com/metacubex/mihomo/dns.batchExchange"),
	[]byte("github.com/metacubex/mihomo/component/resolver.LookupIP"),
	[]byte("github.com/metacubex/mihomo/component/resolver.ResolveIP"),
}

func resolverBusy() bool {
	buf := make([]byte, 1<<20)
	for {
		n := runtime.Stack(buf, true)
		if n < len(buf) {
			buf = buf[:n]
			break
		}
		buf = make([]byte, 2*len(buf))
	}
	for _, frame := range resolverBusyFrames {
		if bytes.Contains(buf, frame) {
			return true
		}
	}
	return false
}

// waitResolverIdle waits for lookups earlier tests started before a test
// rewrites resolver settings. It only delays the test: a lookup that outlives
// the wait still finishes, and the race detector would still report it.
func waitResolverIdle(t testing.TB) {
	t.Helper()
	deadline := time.Now().Add(15 * time.Second)
	for resolverBusy() {
		if time.Now().After(deadline) {
			t.Log("DNS lookups from earlier tests are still running")
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
}
