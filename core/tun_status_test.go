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

func TestTunStatusOfAStoppedCoreIsNotUp(t *testing.T) {
	general := &config.General{}
	general.Tun = LC.Tun{Enable: true}
	withCurrentConfig(t, &config.Config{General: general})
	isRunning.Store(false)

	if status := handleTunStatus(); status.Up {
		t.Fatalf("status = %+v, a stopped Core reported its TUN up", status)
	}
}

func TestTunStatusAsksAndroidsVpnServiceWhenThereIsOne(t *testing.T) {
	withCurrentConfig(t, &config.Config{General: &config.General{}})
	isRunning.Store(true)
	saved := androidTunUp
	t.Cleanup(func() {
		isRunning.Store(false)
		androidTunUp = saved
	})

	androidTunUp = func() bool { return true }
	if status := handleTunStatus(); !status.Up {
		t.Fatalf("status = %+v, want up while the VpnService holds the TUN", status)
	}
	androidTunUp = func() bool { return false }
	if status := handleTunStatus(); status.Up {
		t.Fatalf("status = %+v, want down without the VpnService TUN", status)
	}
}
