package core

import "testing"

func TestSelectedCheckersRunsRepeatedServiceOnlyOnce(t *testing.T) {
	got := selectedCheckers([]string{"claude", "claude", "unknown", "github", "claude", "github", "gemini"})
	want := []string{"claude", "github", "gemini"}
	if len(got) != len(want) {
		t.Fatalf("selected %d checkers, want %d: %+v", len(got), len(want), got)
	}
	for i, checker := range got {
		if checker.name != want[i] {
			t.Errorf("checker %d = %q, want %q", i, checker.name, want[i])
		}
	}
}

func TestSelectedCheckersBoundsDuplicateRequests(t *testing.T) {
	names := make([]string, 50000)
	for i := range names {
		if i%2 == 0 {
			names[i] = "not-a-service"
		} else {
			names[i] = "google"
		}
	}
	got := selectedCheckers(names)
	if len(got) != 1 || got[0].name != "google" {
		t.Fatalf("selected checkers = %+v; want one google check", got)
	}
}

func TestSelectedCheckersEmptyMeansAll(t *testing.T) {
	got := selectedCheckers(nil)
	if len(got) != len(serviceCheckers) {
		t.Fatalf("default list has %d checkers, want %d", len(got), len(serviceCheckers))
	}
}
