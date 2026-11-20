//go:build !android

package core

import (
	"fmt"
	"os"
	"os/signal"
	"sync"
	"syscall"
	"time"
)

const exitCleanupTimeout = 3 * time.Second // sing-tun's Linux policy routes outlive the process; only a shutdown removes them

var (
	exitCleanupOnce sync.Once
	exitCleanupDone = make(chan struct{})
)

func releaseOnExit() {
	if !isInit.Load() {
		return
	}
	exitCleanupOnce.Do(func() {
		go func() {
			defer close(exitCleanupDone)
			handleShutdown()
		}()
	})
	select {
	case <-exitCleanupDone:
	case <-time.After(exitCleanupTimeout):
		fmt.Fprintln(os.Stderr, "[ERROR] core cleanup did not finish before exit")
	}
}

func ExitOnTermination() {
	signals := make(chan os.Signal, 1)
	signal.Notify(signals, os.Interrupt, syscall.SIGTERM)
	<-signals
	releaseOnExit()
	os.Exit(0)
}
