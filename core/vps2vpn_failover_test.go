package core

import (
	"testing"
	"time"
)

type fakeLineConn struct {
	chains []string
	closed int
}

func (c *fakeLineConn) chain() []string { return c.chains }

func (c *fakeLineConn) Close() error {
	c.closed++
	return nil
}

type fakeClock struct{ at time.Time }

func (c *fakeClock) now() time.Time { return c.at }

func (c *fakeClock) advance(d time.Duration) { c.at = c.at.Add(d) }

func newTestLineWatch() (*lineWatch, *fakeClock) {
	clock := &fakeClock{at: time.Unix(1_700_000_000, 0)}
	return newLineWatch(lineWatchCooldown, clock.now), clock
}

func smartGroupAt(id any, now string, dead ...string) lineGroup {
	down := map[string]bool{}
	for _, line := range dead {
		down[line] = true
	}
	return lineGroup{
		name:  vpsSmartGroup,
		id:    id,
		now:   now,
		alive: func(line string) bool { return !down[line] },
	}
}

func TestLineWatchClosesOnlyTheConnectionsOnTheLineThatWentDown(t *testing.T) {
	watch, _ := newTestLineWatch()
	group := new(int)
	if moves := watch.observe([]lineGroup{smartGroupAt(group, "hy2")}); len(moves) != 0 {
		t.Fatalf("first sight moved: %v", moves)
	}
	moves := watch.observe([]lineGroup{smartGroupAt(group, "reality", "hy2")})
	if len(moves) != 1 || moves[0] != (lineMove{group: vpsSmartGroup, from: "hy2", to: "reality"}) {
		t.Fatalf("moves = %v", moves)
	}

	viaSmart := &fakeLineConn{chains: []string{"hy2", vpsSmartGroup, "Proxy"}}
	viaAI := &fakeLineConn{chains: []string{"hy2", vpsAIGroup}}
	pickedDirectly := &fakeLineConn{chains: []string{"hy2", "Proxy"}}
	onNewLine := &fakeLineConn{chains: []string{"reality", vpsSmartGroup, "Proxy"}}
	direct := &fakeLineConn{chains: []string{"DIRECT"}}
	conns := []lineConn{viaSmart, viaAI, pickedDirectly, onNewLine, direct}

	if closed := closeOnMovedLines(conns, moves); closed != 1 {
		t.Fatalf("closed %d connections, want 1", closed)
	}
	if viaSmart.closed != 1 {
		t.Fatal("the connection the smart group sent over the dead line stayed open")
	}
	for _, conn := range []*fakeLineConn{viaAI, pickedDirectly, onNewLine, direct} {
		if conn.closed != 0 {
			t.Fatalf("closed %v, which the move does not touch", conn.chains)
		}
	}
}

func TestLineWatchLeavesAWorkingLineAloneWhenTheGroupMovesBack(t *testing.T) {
	watch, _ := newTestLineWatch()
	group := new(int)
	watch.observe([]lineGroup{smartGroupAt(group, "reality", "hy2")})
	// hy2 recovered; the group goes back to it while reality still works.
	if moves := watch.observe([]lineGroup{smartGroupAt(group, "hy2")}); len(moves) != 0 {
		t.Fatalf("moving off a working line closed its connections: %v", moves)
	}
}

func TestLineWatchClosesOncePerCooldownForAFlappingLine(t *testing.T) {
	watch, clock := newTestLineWatch()
	group := new(int)
	watch.observe([]lineGroup{smartGroupAt(group, "hy2")})
	if moves := watch.observe([]lineGroup{smartGroupAt(group, "reality", "hy2")}); len(moves) != 1 {
		t.Fatalf("first drop: %v", moves)
	}
	clock.advance(lineWatchInterval)
	watch.observe([]lineGroup{smartGroupAt(group, "hy2")})
	clock.advance(lineWatchInterval)
	if moves := watch.observe([]lineGroup{smartGroupAt(group, "reality", "hy2")}); len(moves) != 0 {
		t.Fatalf("a flap inside the cooldown closed again: %v", moves)
	}
	clock.advance(lineWatchCooldown)
	watch.observe([]lineGroup{smartGroupAt(group, "hy2")})
	if moves := watch.observe([]lineGroup{smartGroupAt(group, "reality", "hy2")}); len(moves) != 1 {
		t.Fatalf("a drop after the cooldown was ignored: %v", moves)
	}
}

func TestLineWatchCooldownIsPerLine(t *testing.T) {
	watch, clock := newTestLineWatch()
	group := new(int)
	watch.observe([]lineGroup{smartGroupAt(group, "hy2")})
	watch.observe([]lineGroup{smartGroupAt(group, "reality", "hy2")})
	clock.advance(lineWatchInterval)
	moves := watch.observe([]lineGroup{smartGroupAt(group, "trojan", "hy2", "reality")})
	if len(moves) != 1 || moves[0].from != "reality" {
		t.Fatalf("the second line going down was held back by the first: %v", moves)
	}
}

func TestLineWatchTakesAReloadAsAFreshStart(t *testing.T) {
	watch, _ := newTestLineWatch()
	watch.observe([]lineGroup{smartGroupAt(new(int), "hy2")})
	if moves := watch.observe([]lineGroup{smartGroupAt(new(int), "reality", "hy2")}); len(moves) != 0 {
		t.Fatalf("a rebuilt group was taken for a failover: %v", moves)
	}
}

func TestLineWatchForgetsAGroupThatIsGone(t *testing.T) {
	watch, _ := newTestLineWatch()
	group := new(int)
	watch.observe([]lineGroup{smartGroupAt(group, "hy2")})
	watch.observe(nil)
	if moves := watch.observe([]lineGroup{smartGroupAt(group, "reality", "hy2")}); len(moves) != 0 {
		t.Fatalf("a group seen again after it was gone moved: %v", moves)
	}
}

func TestChainLeavesNeedsTheLineRightBeforeTheGroup(t *testing.T) {
	cases := []struct {
		chain []string
		want  bool
	}{
		{[]string{"hy2", vpsSmartGroup}, true},
		{[]string{"hy2", vpsSmartGroup, "Proxy", "GLOBAL"}, true},
		{[]string{"hy2", "Other", vpsSmartGroup}, false},
		{[]string{vpsSmartGroup, "hy2"}, false},
		{[]string{"hy2"}, false},
		{nil, false},
	}
	for _, tc := range cases {
		if got := chainLeaves(tc.chain, vpsSmartGroup, "hy2"); got != tc.want {
			t.Errorf("chainLeaves(%v) = %v, want %v", tc.chain, got, tc.want)
		}
	}
}

func TestCloseOnMovedLinesClosesAConnectionOnce(t *testing.T) {
	conn := &fakeLineConn{chains: []string{"hy2", vpsAIGroup, "hy2", vpsSmartGroup}}
	moves := []lineMove{
		{group: vpsSmartGroup, from: "hy2", to: "reality"},
		{group: vpsAIGroup, from: "hy2", to: "reality"},
	}
	if closed := closeOnMovedLines([]lineConn{conn}, moves); closed != 1 || conn.closed != 1 {
		t.Fatalf("closed = %d, conn closed %d times", closed, conn.closed)
	}
}
