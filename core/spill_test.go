package core

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"testing"

	"github.com/metacubex/mihomo/constant"
)

func withSpillHome(t *testing.T, threshold int) string {
	t.Helper()
	previousHome := constant.Path.HomeDir()
	previousThreshold := spillThreshold
	home := t.TempDir()
	constant.SetHomeDir(home)
	spillThreshold = threshold
	t.Cleanup(func() {
		constant.SetHomeDir(previousHome)
		spillThreshold = previousThreshold
	})
	return home
}

func getConfigCall(t *testing.T, id string) *MethodCall {
	t.Helper()
	path := filepath.Join(t.TempDir(), "profile.yaml")
	if err := os.WriteFile(path, []byte("mode: rule\nrules:\n  - MATCH,DIRECT\n"), 0o600); err != nil {
		t.Fatalf("write profile: %v", err)
	}
	arguments, _ := json.Marshal(PathParams{Path: path})
	return &MethodCall{ID: id, Method: configReadMethod, Arguments: arguments}
}

func TestHandleMethodCallSpillsALargeResultToAFile(t *testing.T) {
	home := withSpillHome(t, 64)

	frame := handleMethodCall(getConfigCall(t, "7"))

	var envelope MethodResponse
	if err := json.Unmarshal(frame, &envelope); err != nil {
		t.Fatalf("response is not valid JSON: %v", err)
	}
	if envelope.ID != "7" || envelope.Result != nil || envelope.Error != nil {
		t.Fatalf("envelope = %+v, want only the id and the file", envelope)
	}
	if filepath.Dir(envelope.File) != filepath.Join(home, spilledResponseDirName) {
		t.Fatalf("file = %s, want it under the home directory's spill directory", envelope.File)
	}
	data, err := os.ReadFile(envelope.File)
	if err != nil {
		t.Fatalf("read spilled response: %v", err)
	}
	var spilled struct {
		ID     string         `json:"id"`
		Result map[string]any `json:"result"`
	}
	if err := json.Unmarshal(data, &spilled); err != nil {
		t.Fatalf("spilled response is not valid JSON: %v", err)
	}
	if spilled.ID != "7" || spilled.Result["mode"] != "rule" {
		t.Errorf("spilled response = %+v, want the full answer to call 7", spilled)
	}
	if runtime.GOOS != "windows" {
		info, _ := os.Stat(envelope.File)
		if info.Mode().Perm() != 0o600 {
			t.Errorf("mode = %v, want it readable by its owner only", info.Mode().Perm())
		}
	}
}

func TestHandleMethodCallAnswersInlineUnderTheThreshold(t *testing.T) {
	home := withSpillHome(t, responseSpillThreshold)

	frame := handleMethodCall(getConfigCall(t, "8"))

	var envelope MethodResponse
	if err := json.Unmarshal(frame, &envelope); err != nil {
		t.Fatalf("response is not valid JSON: %v", err)
	}
	if envelope.File != "" || envelope.Result == nil {
		t.Errorf("envelope = %+v, want the result inline", envelope)
	}
	if _, err := os.Stat(filepath.Join(home, spilledResponseDirName)); !os.IsNotExist(err) {
		t.Errorf("stat spill directory = %v, want nothing written", err)
	}
}

func TestClearSpilledResponsesKeepsTheDirectory(t *testing.T) {
	home := withSpillHome(t, 64)
	handleMethodCall(getConfigCall(t, "9"))

	clearSpilledResponses()

	entries, err := os.ReadDir(filepath.Join(home, spilledResponseDirName))
	if err != nil {
		t.Fatalf("read spill directory: %v", err)
	}
	if len(entries) != 0 {
		t.Errorf("entries = %v, want none left", entries)
	}
}

// linkDir makes link lead to target: a symlink, or a junction on Windows,
// which any user can create there.
func linkDir(t *testing.T, target, link string) {
	t.Helper()
	if runtime.GOOS == "windows" {
		if out, err := exec.Command("cmd", "/c", "mklink", "/J", filepath.Clean(link), filepath.Clean(target)).CombinedOutput(); err != nil {
			t.Fatalf("mklink /J: %v: %s", err, out)
		}
		return
	}
	if err := os.Symlink(target, link); err != nil {
		t.Fatalf("symlink: %v", err)
	}
}

func TestSpillNeverWritesOrDeletesThroughALinkedResponseDirectory(t *testing.T) {
	home := withSpillHome(t, 64)
	elsewhere := t.TempDir()
	kept := filepath.Join(elsewhere, "kept.json")
	if err := os.WriteFile(kept, []byte("{}"), 0o600); err != nil {
		t.Fatal(err)
	}
	linkDir(t, elsewhere, filepath.Join(home, spilledResponseDirName))

	frame := handleMethodCall(getConfigCall(t, "10"))
	clearSpilledResponses()

	var envelope MethodResponse
	if err := json.Unmarshal(frame, &envelope); err != nil || envelope.File != "" || envelope.Result == nil {
		t.Errorf("reply = %s, want the result inline", frame)
	}
	entries, _ := os.ReadDir(elsewhere)
	if len(entries) != 1 || entries[0].Name() != "kept.json" {
		t.Errorf("link target holds %v, want only kept.json", entries)
	}
}

func TestClearSpilledResponsesRemovesALinkNotWhatItLeadsTo(t *testing.T) {
	home := withSpillHome(t, 64)
	dir := filepath.Join(home, spilledResponseDirName)
	if err := os.Mkdir(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	elsewhere := t.TempDir()
	kept := filepath.Join(elsewhere, "kept.json")
	if err := os.WriteFile(kept, []byte("{}"), 0o600); err != nil {
		t.Fatal(err)
	}
	linkDir(t, elsewhere, filepath.Join(dir, "link"))

	clearSpilledResponses()

	if _, err := os.Lstat(filepath.Join(dir, "link")); !os.IsNotExist(err) {
		t.Errorf("lstat link = %v, want it removed", err)
	}
	if _, err := os.Stat(kept); err != nil {
		t.Errorf("stat link target file = %v, want it kept", err)
	}
}

func TestAnOversizedReplyThatCannotSpillIsAnError(t *testing.T) {
	home := withSpillHome(t, 64)
	previousLimit := inlineResponseLimit
	inlineResponseLimit = 64
	t.Cleanup(func() { inlineResponseLimit = previousLimit })
	if err := os.WriteFile(filepath.Join(home, spilledResponseDirName), nil, 0o600); err != nil {
		t.Fatal(err)
	}

	frame := handleMethodCall(getConfigCall(t, "11"))

	var envelope MethodResponse
	if err := json.Unmarshal(frame, &envelope); err != nil {
		t.Fatalf("reply is not valid JSON: %v", err)
	}
	if envelope.ID != "11" || envelope.Error == nil || envelope.Error.Code != "response_too_large" {
		t.Errorf("reply = %s, want a response_too_large error for call 11", frame)
	}
}
