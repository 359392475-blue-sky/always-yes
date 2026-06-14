package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/taigrr/apple-silicon-accelerometer/detector"
	"github.com/taigrr/apple-silicon-accelerometer/sensor"
	"github.com/taigrr/apple-silicon-accelerometer/shm"
)

const (
	pollInterval   = 10 * time.Millisecond
	maxSampleBatch = 200
	sensorWarmup   = 100 * time.Millisecond
)

func cmdDoctor(args []string) int {
	fs := flag.NewFlagSet("doctor", flag.ExitOnError)
	fs.Parse(args)

	rc := 0

	brand, ok := cpuBrand()
	if !ok || !isAppleSilicon(brand) {
		fmt.Printf("✗ CPU: %q (Apple Silicon required)\n", brand)
		rc = 1
	} else {
		fmt.Printf("✓ CPU: %s\n", brand)
	}

	if !hasAccelDevice() {
		fmt.Println("✗ AppleSPUHIDDevice 'accel' not found in IOKit registry")
		fmt.Println("  Your chip likely lacks the BMI286 IMU. Required: M2+ or M1 Pro.")
		rc = 1
	} else {
		fmt.Println("✓ AppleSPUHIDDevice 'accel' present")
	}

	cfg, src, err := loadConfig()
	if err != nil {
		fmt.Printf("⚠ Config: %v\n", err)
		rc = 1
	} else {
		fmt.Printf("✓ Config: %s\n", src)
		fmt.Printf("    mode=%s  min_amplitude=%.3f  cooldown=%dms  apps=%d\n",
			cfg.Mode, cfg.MinAmplitude, cfg.CooldownMs, len(cfg.Apps))
	}

	if os.Geteuid() == 0 {
		fmt.Println("✓ Running as root (sensor access OK)")
	} else {
		fmt.Println("ⓘ Not running as root — 'yes-engineer run' will need sudo")
	}

	return rc
}

func cmdRun(args []string) int {
	var (
		debug         bool
		threshold     float64
		modeOverride  string
		cooldownOverr int
	)
	fs := flag.NewFlagSet("run", flag.ExitOnError)
	fs.BoolVar(&debug, "debug", false, "log every detected event with details")
	fs.Float64Var(&threshold, "threshold", 0, "override min_amplitude (0 = use config)")
	fs.StringVar(&modeOverride, "mode", "", `override mode: "whitelist" | "global" | "off"`)
	fs.IntVar(&cooldownOverr, "cooldown", 0, "override cooldown_ms (0 = use config)")
	fs.Parse(args)

	if os.Geteuid() != 0 {
		fmt.Fprintln(os.Stderr, "yes-engineer run requires sudo for IOKit HID access")
		return 1
	}
	if !hasAccelDevice() {
		fmt.Fprintln(os.Stderr, "AppleSPUHIDDevice 'accel' not found — try 'yes-engineer doctor'")
		return 1
	}

	cfg, _, err := loadConfig()
	if err != nil {
		fmt.Fprintf(os.Stderr, "config: %v\n", err)
		return 1
	}
	if threshold > 0 {
		cfg.MinAmplitude = threshold
	}
	if modeOverride != "" {
		cfg.Mode = modeOverride
		if err := validateConfig(&cfg); err != nil {
			fmt.Fprintf(os.Stderr, "%v\n", err)
			return 1
		}
	}
	if cooldownOverr > 0 {
		cfg.CooldownMs = cooldownOverr
	}

	ctx, cancel := signal.NotifyContext(context.Background(),
		os.Interrupt, syscall.SIGTERM)
	defer cancel()

	return runDetector(ctx, cfg, debug)
}

func runDetector(ctx context.Context, cfg Config, debug bool) int {
	ring, err := shm.CreateRing(shm.NameAccel)
	if err != nil {
		fmt.Fprintf(os.Stderr, "shm: %v\n", err)
		return 1
	}
	defer ring.Close()
	defer ring.Unlink()

	senseErr := make(chan error, 1)
	go func() {
		senseErr <- sensor.Run(sensor.Config{AccelRing: ring})
	}()

	// Give the sensor goroutine time to start producing samples before
	// the first poll tick.
	select {
	case <-time.After(sensorWarmup):
	case err := <-senseErr:
		fmt.Fprintf(os.Stderr, "sensor: %v\n", err)
		return 1
	case <-ctx.Done():
		return 0
	}

	det := detector.New()
	cooldown := time.Duration(cfg.CooldownMs) * time.Millisecond
	var lastTotal uint64
	var lastEventTime time.Time
	var lastSlap time.Time

	fmt.Printf("yes-engineer: listening (mode=%s, threshold=%.3f, cooldown=%dms). ctrl+c to quit.\n",
		cfg.Mode, cfg.MinAmplitude, cfg.CooldownMs)

	tick := time.NewTicker(pollInterval)
	defer tick.Stop()

	for {
		select {
		case <-ctx.Done():
			fmt.Println("\nbye")
			return 0
		case err := <-senseErr:
			fmt.Fprintf(os.Stderr, "\nsensor died: %v\n", err)
			return 1
		case <-tick.C:
		}

		samples, total := ring.ReadNew(lastTotal, shm.AccelScale)
		lastTotal = total
		if len(samples) > maxSampleBatch {
			samples = samples[len(samples)-maxSampleBatch:]
		}

		nSamples := len(samples)
		if nSamples == 0 {
			continue
		}
		tNow := float64(time.Now().UnixNano()) / 1e9
		for idx, s := range samples {
			tSample := tNow - float64(nSamples-idx-1)/float64(det.FS)
			det.Process(s.X, s.Y, s.Z, tSample)
		}

		if len(det.Events) == 0 {
			continue
		}
		ev := det.Events[len(det.Events)-1]
		if ev.Time.Equal(lastEventTime) {
			continue
		}
		lastEventTime = ev.Time

		if debug {
			log.Printf("event amp=%.4f severity=%s", ev.Amplitude, ev.Severity)
		}

		if ev.Amplitude < cfg.MinAmplitude {
			continue
		}
		if time.Since(lastSlap) < cooldown {
			continue
		}
		lastSlap = time.Now()

		handleSlap(cfg, ev.Amplitude, debug)
	}
}

func handleSlap(cfg Config, amp float64, debug bool) {
	switch cfg.Mode {
	case "off":
		fmt.Printf("slap [amp=%.4f] (mode=off, no Enter)\n", amp)
	case "whitelist":
		bid := frontmostBundleID()
		if !contains(cfg.Apps, bid) {
			if debug {
				log.Printf("slap [amp=%.4f] ignored: front=%q not whitelisted", amp, bid)
			}
			return
		}
		if err := sendEnter(); err != nil {
			log.Printf("send enter failed: %v", err)
			return
		}
		fmt.Printf("⏎ slap [amp=%.4f] → Enter (front=%s)\n", amp, bid)
	case "global":
		if err := sendEnter(); err != nil {
			log.Printf("send enter failed: %v", err)
			return
		}
		fmt.Printf("⏎ slap [amp=%.4f] → Enter\n", amp)
	}
}
