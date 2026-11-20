package core

import (
	"runtime"
	"runtime/debug"
	"sync"
	"sync/atomic"
	"time"

	"github.com/metacubex/mihomo/adapter/inbound"
	"github.com/metacubex/mihomo/component/resolver"
	"github.com/metacubex/mihomo/component/updater"
	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/constant/features"
	"github.com/metacubex/mihomo/hub/executor"
	"github.com/metacubex/mihomo/listener"
	"github.com/metacubex/mihomo/tunnel"
	"github.com/metacubex/mihomo/tunnel/statistic"
)

var (
	isInit     atomic.Bool
	isRunning  atomic.Bool
	sdkVersion atomic.Int32
)

func handleInit(params *InitParams) error {
	configMu.Lock()
	defer configMu.Unlock()
	sdkVersion.Store(int32(params.Version))
	constant.SetHomeDir(params.HomeDir)
	initOwnership(params.HomeDir)
	clearSpilledResponses()
	clearProxyDefinitionCache()
	isInit.Store(true)
	return nil
}

func handleInitialized() bool {
	return isInit.Load()
}

func setRunning(running bool) {
	isRunning.Store(running)
}

func handleStartListener() {
	configMu.Lock()
	defer configMu.Unlock()
	setRunning(true)
	updateListeners(currentConfig)
	resolver.ResetConnection()
	// A probe already out left before the TUN routes and over the DNS
	// connections just dropped, so its answer must not stand for this route.
	bumpRouteEpoch()
}

func handleStopListener() {
	configMu.Lock()
	defer configMu.Unlock()
	setRunning(false)
	listener.StopListener()
	resolver.ResetConnection()
	bumpRouteEpoch()
}

// TunStatus says whether the TUN the config asks for is actually listening.
// mihomo's listener.ReCreateTun only logs a failed sing_tun.New and records
// the conf with Enable=false (listener/listener.go), so GetTunConf().Enable is
// the core-side signal that the adapter and stack came up.
type TunStatus struct {
	Running   bool   `json:"running"`
	Requested bool   `json:"requested"`
	Up        bool   `json:"up"`
	Stack     string `json:"stack"`
}

// Holding configMu waits out an update or setup still creating the TUN, so
// the answer is the settled state, not one taken halfway through.
func handleTunStatus() TunStatus {
	configMu.Lock()
	defer configMu.Unlock()
	status := TunStatus{Running: isRunning.Load()}
	if currentConfig != nil && currentConfig.General != nil {
		status.Requested = currentConfig.General.Tun.Enable
	}
	tun := listener.GetTunConf()
	status.Up = tun.Enable
	status.Stack = tun.Stack.String()
	return status
}

func updateListeners(cfg *config.Config) {
	if cfg == nil || !isRunning.Load() {
		return
	}
	general := cfg.General
	listener.PatchInboundListeners(cfg.Listeners, tunnel.Tunnel, true)

	listener.SetAllowLan(general.AllowLan)
	inbound.SetSkipAuthPrefixes(general.SkipAuthPrefixes)
	inbound.SetAllowedIPs(general.LanAllowedIPs)
	inbound.SetDisAllowedIPs(general.LanDisAllowedIPs)

	listener.SetBindAddress(general.BindAddress)
	listener.ReCreateHTTP(general.Port, tunnel.Tunnel)
	listener.ReCreateSocks(general.SocksPort, tunnel.Tunnel)
	listener.ReCreateRedir(general.RedirPort, tunnel.Tunnel)
	listener.ReCreateTProxy(general.TProxyPort, tunnel.Tunnel)
	listener.ReCreateMixed(general.MixedPort, tunnel.Tunnel)
	listener.ReCreateShadowSocks(general.ShadowSocksConfig, tunnel.Tunnel)
	listener.ReCreateVmess(general.VmessConfig, tunnel.Tunnel)
	listener.ReCreateTuic(general.TuicServer, tunnel.Tunnel)
	if !features.Android {
		listener.ReCreateTun(general.Tun, tunnel.Tunnel)
	}
}

func handleShutdown() {
	handleStopLog()
	stopRouteWatch()

	configMu.Lock()
	setRunning(false)
	listener.StopListener()
	updater.StopGeoUpdater()
	executor.Shutdown()
	currentConfig = nil
	clearProxyDefinitionCache()
	isInit.Store(false)
	configMu.Unlock()

	handleForceGC()
}

func handleForceGC() {
	tunnel.InvalidateAllProxies()
	debug.FreeOSMemory()
}

// mihomo loads providers without waiting for them, so its own GC misses their decode buffers.
var (
	loadReleaseDelay  = 2 * time.Second
	releaseLoadMemory = debug.FreeOSMemory

	loadReleaseMu    sync.Mutex
	loadReleaseTimer *time.Timer
)

func scheduleLoadMemoryRelease() {
	loadReleaseMu.Lock()
	defer loadReleaseMu.Unlock()
	if loadReleaseTimer == nil {
		loadReleaseTimer = time.AfterFunc(loadReleaseDelay, func() { releaseLoadMemory() })
		return
	}
	loadReleaseTimer.Reset(loadReleaseDelay)
}

// HeapIdle still counts spans the runtime has already handed back to the OS,
// so the retained-but-unused figure subtracts HeapReleased.
func handleGetMemoryStats() MemoryStats {
	var stats runtime.MemStats
	runtime.ReadMemStats(&stats)
	return MemoryStats{
		Rss:          statistic.DefaultManager.Memory(),
		HeapInuse:    stats.HeapInuse,
		HeapIdle:     stats.HeapIdle - stats.HeapReleased,
		StackInuse:   stats.StackInuse,
		RuntimeOther: stats.MSpanInuse + stats.MCacheInuse + stats.BuckHashSys + stats.GCSys + stats.OtherSys,
	}
}
