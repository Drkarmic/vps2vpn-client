package core

import (
	"errors"
	"fmt"
	"io/fs"
	"math/rand/v2"
	"os"
	"path/filepath"
	"strconv"

	"github.com/metacubex/mihomo/constant"
)

// Android copies a reply into the Java heap three times and the desktop IPC
// frame stops at maxIPCFrameSize. The directory name is mirrored in Dart.
const (
	responseSpillThreshold = 1 << 20
	spilledResponseDirName = "responses"
	maxIPCFrameSize        = 64 * 1024 * 1024
)

var (
	spillThreshold      = responseSpillThreshold
	inlineResponseLimit = maxIPCFrameSize
)

var errSpillDirNotPlain = errors.New("the response directory is a link or not a directory")

func spilledResponseDir() string {
	return filepath.Join(constant.Path.HomeDir(), spilledResponseDirName)
}

// An elevated Core writes and deletes here; os.Root refuses a link out of the
// home directory at any step, a junction included.
func openSpilledResponseDir(create bool) (*os.Root, error) {
	home, err := os.OpenRoot(constant.Path.HomeDir())
	if err != nil {
		return nil, err
	}
	defer home.Close()
	if create {
		if err := home.Mkdir(spilledResponseDirName, 0o755); err != nil && !errors.Is(err, fs.ErrExist) {
			return nil, err
		}
	}
	info, err := home.Lstat(spilledResponseDirName)
	if err != nil {
		return nil, err
	}
	if info.Mode().Type() != fs.ModeDir {
		return nil, errSpillDirNotPlain
	}
	return home.OpenRoot(spilledResponseDirName)
}

func writeSpilledFile(suffix string, write func(*os.File) error) (string, error) {
	dir, err := openSpilledResponseDir(true)
	if err != nil {
		return "", err
	}
	defer dir.Close()
	// The host deletes each file it reads, which a directory an elevated Core made would refuse.
	reclaimDirOwnership(spilledResponseDir())
	name, file, err := createUniqueFile(dir, suffix)
	if err != nil {
		return "", err
	}
	// An elevated Core still answers a host running as the app user: the file
	// goes to that user, not to every account (it can hold proxy passwords).
	err = handOverPrivate(file)
	if err == nil {
		err = write(file)
	}
	if err = errors.Join(err, file.Close()); err != nil {
		_ = dir.Remove(name)
		return "", err
	}
	scheduleReclaimOwnership()
	return filepath.Join(spilledResponseDir(), name), nil
}

func createUniqueFile(dir *os.Root, suffix string) (string, *os.File, error) {
	for range 16 {
		name := strconv.FormatUint(rand.Uint64(), 36) + suffix
		file, err := dir.OpenFile(name, os.O_RDWR|os.O_CREATE|os.O_EXCL, 0o600)
		if errors.Is(err, fs.ErrExist) {
			continue
		}
		return name, file, err
	}
	return "", nil, errors.New("no free name in the response directory")
}

func spillResponse(id string, data []byte) []byte {
	if len(data) <= spillThreshold {
		return data
	}
	path, err := writeSpilledResponse(data)
	if err == nil {
		return encodeResponse(MethodResponse{ID: id, File: path})
	}
	logError("spill response %s: %v", id, err)
	if len(data) > inlineResponseLimit {
		// A reply no frame carries would close the host's connection.
		return encodeResponse(MethodResponse{ID: id, Error: &MethodError{
			Code:    "response_too_large",
			Message: fmt.Sprintf("a %d-byte reply could not be written to a file: %v", len(data), err),
		}})
	}
	return data
}

func writeSpilledResponse(data []byte) (string, error) {
	return writeSpilledFile(".json", func(file *os.File) error {
		_, err := file.Write(data)
		return err
	})
}

func clearSpilledResponses() {
	dir, err := openSpilledResponseDir(false)
	if err != nil {
		return
	}
	defer dir.Close()
	listing, err := dir.Open(".")
	if err != nil {
		return
	}
	entries, _ := listing.ReadDir(-1)
	_ = listing.Close()
	for _, entry := range entries {
		_ = dir.Remove(entry.Name())
	}
}
