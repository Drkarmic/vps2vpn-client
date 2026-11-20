package core

import (
	"testing"

	"github.com/metacubex/mihomo/config"
	LC "github.com/metacubex/mihomo/listener/config"
)

// ReCreateTun leaves no listener after a failed sing_tun.New, so a config that
// asks for the TUN while the listener reports it down is what the app's
// self-check takes for a failed adapter.
func TestTunStatusTellsARequestedTunThatIsNotUp(t *testing.T) {
	general := &config.General{}
	general.Tun = LC.Tun{Enable: true}
	withCurrentConfig(t, &config.Config{General: general})
	isRunning.Store(true)
	t.Cleanup(func() { isRunning.Store(false) })

	status := handleTunStatus()

	if !status.Running || !status.Requested || status.Up {
		t.Fatalf("status = %+v, want running and requested but not up", status)
	}
}

func TestTunStatusWithoutAConfigAsksForNothing(t *testing.T) {
	withCurrentConfig(t, nil)

	status := handleTunStatus()

	if status.Running || status.Requested || status.Up {
		t.Fatalf("status = %+v, want nothing running, requested or up", status)
	}
}
