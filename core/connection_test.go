package core

import (
	"io"
	"net"
	"testing"
	"time"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/adapter/outbound"
	"github.com/metacubex/mihomo/adapter/provider"
	"github.com/metacubex/mihomo/constant"
	cp "github.com/metacubex/mihomo/constant/provider"
	"github.com/metacubex/mihomo/tunnel"
	"github.com/metacubex/mihomo/tunnel/statistic"
)

func TestProxyOnlyTrafficLeavesOutADirectProxyOfAnyName(t *testing.T) {
	direct := outbound.NewDirectWithOption(outbound.DirectOption{Name: "直连"})
	reject := outbound.NewRejectWithOption(outbound.RejectOption{Name: "HK"})
	tunnel.UpdateProxies(map[string]constant.Proxy{
		"直连": adapter.NewProxy(direct),
		"HK": adapter.NewProxy(reject),
	}, nil)
	t.Cleanup(func() { tunnel.UpdateProxies(nil, nil) })

	for _, test := range []struct {
		outbound constant.ProxyAdapter
		proxied  int64
	}{
		{direct, 0},
		{reject, 5},
	} {
		statistic.DefaultManager.ResetStatistic()
		local, remote := net.Pipe()
		go func() { _, _ = io.Copy(io.Discard, remote) }()
		tracker := statistic.NewTCPTracker(
			outbound.NewConn(local, test.outbound),
			statistic.DefaultManager,
			&constant.Metadata{},
			nil,
			0,
			0,
			true,
		)

		if _, err := tracker.Write([]byte("hello")); err != nil {
			t.Fatalf("write through %s: %v", test.outbound.Name(), err)
		}
		_ = tracker.Close()
		_ = remote.Close()

		all, _ := statistic.DefaultManager.TotalTraffic(false)
		proxied, _ := statistic.DefaultManager.TotalTraffic(true)
		if all != 5 || proxied != test.proxied {
			t.Errorf("%s: total %d, proxied %d; want 5 and %d", test.outbound.Name(), all, proxied, test.proxied)
		}
	}
	statistic.DefaultManager.ResetStatistic()
}

type resettableOutbound struct {
	constant.ProxyAdapter
	resets int
}

func (o *resettableOutbound) ResetNetwork() { o.resets++ }

func TestResetNetworkResetsOutboundsThatShareAConnection(t *testing.T) {
	shared := &resettableOutbound{ProxyAdapter: outbound.NewRejectWithOption(outbound.RejectOption{Name: "WG"})}
	tunnel.UpdateProxies(map[string]constant.Proxy{
		"WG":     adapter.NewProxy(shared),
		"DIRECT": adapter.NewProxy(outbound.NewDirect()),
	}, nil)
	t.Cleanup(func() { tunnel.UpdateProxies(nil, nil) })

	handleResetNetwork()

	if shared.resets != 1 {
		t.Fatalf("ResetNetwork ran %d times, want 1", shared.resets)
	}
}

func TestResetNetworkResetsEveryProvidersNodeOfOneName(t *testing.T) {
	first := &resettableOutbound{ProxyAdapter: outbound.NewRejectWithOption(outbound.RejectOption{Name: "WG"})}
	second := &resettableOutbound{ProxyAdapter: outbound.NewRejectWithOption(outbound.RejectOption{Name: "WG"})}
	providerOf := func(name string, outbound *resettableOutbound) cp.ProxyProvider {
		proxies := []constant.Proxy{adapter.NewProxy(outbound)}
		pd, err := provider.NewCompatibleProvider(name, proxies, provider.NewHealthCheck(proxies, "", 0, 0, true, nil))
		if err != nil {
			t.Fatal(err)
		}
		return pd
	}
	tunnel.UpdateProxies(map[string]constant.Proxy{}, map[string]cp.ProxyProvider{
		"A": providerOf("A", first),
		"B": providerOf("B", second),
	})
	t.Cleanup(func() { tunnel.UpdateProxies(nil, nil) })

	handleResetNetwork()

	if first.resets != 1 || second.resets != 1 {
		t.Fatalf("ResetNetwork ran %d and %d times, want 1 each", first.resets, second.resets)
	}
}

type checkedProvider struct {
	fakeProxyProvider
	checked chan string
}

func (p *checkedProvider) HealthCheck() { p.checked <- p.name }

type providerGroupAdapter struct {
	constant.ProxyAdapter
	providers []cp.ProxyProvider
}

func (g *providerGroupAdapter) Providers() []cp.ProxyProvider { return g.providers }

func TestNetworkResetResetsOutboundsAndChecksOnlyTheSmartGroups(t *testing.T) {
	checked := make(chan string, 4)
	group := func(name string) constant.Proxy {
		return adapter.NewProxy(&providerGroupAdapter{
			ProxyAdapter: outbound.NewRejectWithOption(outbound.RejectOption{Name: name}),
			providers:    []cp.ProxyProvider{&checkedProvider{fakeProxyProvider{name: name}, checked}},
		})
	}
	shared := &resettableOutbound{ProxyAdapter: outbound.NewRejectWithOption(outbound.RejectOption{Name: "HY2"})}
	tunnel.UpdateProxies(map[string]constant.Proxy{
		"HY2":         adapter.NewProxy(shared),
		vpsSmartGroup: group(vpsSmartGroup),
		vpsAIGroup:    group(vpsAIGroup),
		"Proxy":       group("Proxy"),
	}, nil)
	t.Cleanup(func() { tunnel.UpdateProxies(nil, nil) })

	if _, err := methodHandlers[networkResetMethod](&MethodCall{Method: networkResetMethod}); err != nil {
		t.Fatal(err)
	}

	if shared.resets != 1 {
		t.Fatalf("ResetNetwork ran %d times, want 1", shared.resets)
	}
	got := map[string]bool{}
	for len(got) < 2 {
		select {
		case name := <-checked:
			got[name] = true
		case <-time.After(5 * time.Second):
			t.Fatalf("health checks run: %v, want both smart groups", got)
		}
	}
	if !got[vpsSmartGroup] || !got[vpsAIGroup] {
		t.Fatalf("health checks run: %v, want both smart groups", got)
	}
	select {
	case name := <-checked:
		t.Fatalf("%s was checked; only the smart groups should be", name)
	case <-time.After(100 * time.Millisecond):
	}
}

func TestNetworkResetWithoutSmartGroupsStillResets(t *testing.T) {
	shared := &resettableOutbound{ProxyAdapter: outbound.NewRejectWithOption(outbound.RejectOption{Name: "HY2"})}
	tunnel.UpdateProxies(map[string]constant.Proxy{"HY2": adapter.NewProxy(shared)}, nil)
	t.Cleanup(func() { tunnel.UpdateProxies(nil, nil) })

	handleNetworkReset()

	if shared.resets != 1 {
		t.Fatalf("ResetNetwork ran %d times, want 1", shared.resets)
	}
}
