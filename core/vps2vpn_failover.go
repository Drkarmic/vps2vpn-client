package core

import (
	"encoding/json"
	"sync"
	"time"

	"github.com/metacubex/mihomo/adapter/outboundgroup"
	"github.com/metacubex/mihomo/log"
	"github.com/metacubex/mihomo/tunnel"
	"github.com/metacubex/mihomo/tunnel/statistic"
)

// mihomo's fallback group moves to the next line without telling anyone, and a
// connection already open on the line it left stays there: an AI stream or a
// websocket on a dead line hangs until TCP gives up. Like sing-box url-test's
// interrupt_exist_connections, the watch closes the connections a smart group
// sent out over the line it left, and only those, so the app reopens them on
// the line in use now.
//
// It only acts when the line left behind is down. A group that moves back to
// a preferred line that recovered leaves the connections on the line it moves
// away from, which still works.
const (
	lineWatchInterval = 2 * time.Second
	// A line that keeps dropping out and coming back has its connections
	// closed once per cooldown rather than on every flap.
	lineWatchCooldown = 30 * time.Second
)

var lineWatchGroups = []string{vpsSmartGroup, vpsAIGroup}

type lineGroup struct {
	name string
	// The group object; a config load builds new ones, and a group seen for
	// the first time has nothing to compare with.
	id    any
	now   string
	alive func(line string) bool
}

type lineMove struct {
	group string
	from  string
	to    string
}

type lineSeen struct {
	id  any
	now string
}

type lineWatch struct {
	cooldown time.Duration
	clock    func() time.Time
	seen     map[string]lineSeen
	closed   map[[2]string]time.Time
}

func newLineWatch(cooldown time.Duration, clock func() time.Time) *lineWatch {
	return &lineWatch{
		cooldown: cooldown,
		clock:    clock,
		seen:     map[string]lineSeen{},
		closed:   map[[2]string]time.Time{},
	}
}

// observe records where each group points now and answers the moves whose
// connections should be closed.
func (w *lineWatch) observe(groups []lineGroup) []lineMove {
	at := w.clock()
	var moves []lineMove
	present := make(map[string]bool, len(groups))
	for _, group := range groups {
		present[group.name] = true
		last, known := w.seen[group.name]
		w.seen[group.name] = lineSeen{id: group.id, now: group.now}
		if !known || last.id != group.id || last.now == "" || last.now == group.now {
			continue
		}
		if group.alive != nil && group.alive(last.now) {
			continue
		}
		key := [2]string{group.name, last.now}
		if closedAt, ok := w.closed[key]; ok && at.Sub(closedAt) < w.cooldown {
			continue
		}
		w.closed[key] = at
		moves = append(moves, lineMove{group: group.name, from: last.now, to: group.now})
	}
	for name := range w.seen {
		if !present[name] {
			delete(w.seen, name)
		}
	}
	for key, closedAt := range w.closed {
		if at.Sub(closedAt) >= w.cooldown {
			delete(w.closed, key)
		}
	}
	return moves
}

// A connection's chain runs from the line out through each group it passed,
// so the group's own member is the entry just before it.
func chainLeaves(chain []string, group, line string) bool {
	for i := 1; i < len(chain); i++ {
		if chain[i] == group && chain[i-1] == line {
			return true
		}
	}
	return false
}

type lineConn interface {
	chain() []string
	Close() error
}

func closeOnMovedLines(conns []lineConn, moves []lineMove) int {
	if len(moves) == 0 {
		return 0
	}
	closed := 0
	for _, conn := range conns {
		chain := conn.chain()
		for _, move := range moves {
			if chainLeaves(chain, move.group, move.from) {
				_ = conn.Close()
				closed++
				break
			}
		}
	}
	return closed
}

type trackerConn struct{ statistic.Tracker }

func (c trackerConn) chain() []string { return c.Info().Chain }

func trackedConns() []lineConn {
	var conns []lineConn
	statistic.DefaultManager.Range(func(c statistic.Tracker) bool {
		conns = append(conns, trackerConn{c})
		return true
	})
	return conns
}

// The test URL is the group's own; a line's health is kept per URL.
func fallbackTestURL(group *outboundgroup.Fallback) string {
	data, err := group.MarshalJSON()
	if err != nil {
		return ""
	}
	var view struct {
		TestURL string `json:"testUrl"`
	}
	if json.Unmarshal(data, &view) != nil {
		return ""
	}
	return view.TestURL
}

func currentLineGroups() []lineGroup {
	selectMu.Lock()
	defer selectMu.Unlock()
	proxies := tunnel.AllProxies()
	groups := make([]lineGroup, 0, len(lineWatchGroups))
	for _, name := range lineWatchGroups {
		group, ok := adapterAs[*outboundgroup.Fallback](proxies[name])
		if !ok {
			continue
		}
		groups = append(groups, lineGroup{
			name: name,
			id:   group,
			now:  group.Now(),
			alive: func(line string) bool {
				url := fallbackTestURL(group)
				for _, proxy := range group.Proxies() {
					if proxy.Name() == line {
						return proxy.AliveForTestUrl(url)
					}
				}
				// A line the group no longer has carries nothing new.
				return true
			},
		})
	}
	return groups
}

var (
	lineWatchOnce  sync.Once
	lineWatchState = newLineWatch(lineWatchCooldown, time.Now)
)

// The watch runs for the life of the process, and on Android that process is
// the app: a panic on one tick must not take it down or end the watch.
func startLineWatch() {
	lineWatchOnce.Do(func() {
		go func() {
			ticker := time.NewTicker(lineWatchInterval)
			defer ticker.Stop()
			for range ticker.C {
				runLineCheck(func() { checkLineMoves(lineWatchState) })
			}
		}()
	})
}

func runLineCheck(check func()) {
	defer func() {
		if r := recover(); r != nil {
			logError("panic in line watch: %v\n%s", r, stackTrace())
		}
	}()
	check()
}

func checkLineMoves(w *lineWatch) {
	if !isRunning.Load() || !vpsSmartEnabled.Load() {
		// The groups last seen hold the whole proxy graph of a config that
		// is gone or stopped, and are no baseline for the next one.
		w.observe(nil)
		return
	}
	moves := w.observe(currentLineGroups())
	if len(moves) == 0 {
		return
	}
	closed := closeOnMovedLines(trackedConns(), moves)
	for _, move := range moves {
		log.Infoln("[vps2vpn] %s moved from %s to %s", move.group, move.from, move.to)
	}
	if closed > 0 {
		log.Infoln("[vps2vpn] closed %d connections left on a line that went down", closed)
	}
}
