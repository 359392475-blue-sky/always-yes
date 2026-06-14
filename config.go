package main

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/BurntSushi/toml"
)

type Config struct {
	MinAmplitude float64  `toml:"min_amplitude"`
	CooldownMs   int      `toml:"cooldown_ms"`
	Mode         string   `toml:"mode"`
	Apps         []string `toml:"apps"`
}

// Default app whitelist: terminals where Claude Code typically runs +
// vibe-coding editors with built-in AI confirmation prompts.
var defaultApps = []string{
	"com.apple.Terminal",
	"com.googlecode.iterm2",
	"com.mitchellh.ghostty",
	"dev.warp.Warp-Stable",
	"dev.warp.Warp",
	"net.kovidgoyal.kitty",
	"io.alacritty",
	"co.zeit.hyper",
	"org.tabby",
	"com.github.wez.wezterm",
	"com.todesktop.230313mzl4w4u92", // Cursor
	"com.exafunction.windsurf",
	"dev.zed.Zed",
	"com.microsoft.VSCode",
	"com.apple.dt.Xcode",
}

func defaultConfig() Config {
	return Config{
		MinAmplitude: 0.144,
		CooldownMs:   600,
		Mode:         "whitelist",
		Apps:         append([]string(nil), defaultApps...),
	}
}

func configPath() string {
	if x := os.Getenv("XDG_CONFIG_HOME"); x != "" {
		return filepath.Join(x, "yes-engineer", "config.toml")
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return ""
	}
	return filepath.Join(home, ".config", "yes-engineer", "config.toml")
}

// loadConfig returns the resolved config, the source label (for logs),
// and any read/parse error. A missing file falls back to defaults silently.
func loadConfig() (Config, string, error) {
	path := configPath()
	cfg := defaultConfig()
	if path == "" {
		return cfg, "(defaults; could not resolve home dir)", nil
	}

	data, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return cfg, "(defaults; no config file at " + path + ")", nil
	}
	if err != nil {
		return cfg, path, err
	}
	if err := toml.Unmarshal(data, &cfg); err != nil {
		return cfg, path, fmt.Errorf("parse %s: %w", path, err)
	}
	if err := validateConfig(&cfg); err != nil {
		return cfg, path, err
	}
	return cfg, path, nil
}

func validateConfig(c *Config) error {
	if c.MinAmplitude < 0 || c.MinAmplitude > 2 {
		return fmt.Errorf("min_amplitude must be between 0 and 2, got %.3f", c.MinAmplitude)
	}
	if c.CooldownMs < 50 {
		return fmt.Errorf("cooldown_ms must be >= 50, got %d", c.CooldownMs)
	}
	switch c.Mode {
	case "whitelist", "global", "off":
	default:
		return fmt.Errorf(`mode must be "whitelist", "global", or "off", got %q`, c.Mode)
	}
	return nil
}
