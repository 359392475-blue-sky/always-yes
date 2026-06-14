# Changelog / 更新日志

All notable changes to Yes Engineer are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-06-14

### Added / 新增
- **App Scope tab** in Settings that shows the full AI coding apps
  allowlist, grouped by category (Terminals, AI Coding Editors, Code
  Editors). Categories are collapsible and the list scrolls.
- **Built-in allowlist toggle**: every entry in the default allowlist can
  now be enabled or disabled from the UI. Disabled apps are excluded from
  the effective trigger scope without removing them from the catalog.
- **Custom apps**: add any macOS app to the allowlist by bundle ID
  (manual entry), by clicking "Add current foreground app", or by
  dragging a `.app` from Finder onto the Settings window. Duplicate
  bundle IDs are rejected.
- **New "Off (log only)" mode** is now exposed in both the menu bar and
  the Settings tab. In this mode, taps are detected and logged but no
  keystrokes are sent.
- **DMG distribution** in the release pipeline. Each release now ships a
  read-only, compressed `.dmg` alongside the existing `.app.zip`, with
  per-file SHA-256 checksums and a combined `SHA256SUMS.txt`.
- **Universal binary** (`arm64` + `x86_64`) for the main app and helper
  daemon, built with `lipo` and signed per-arch.
- **Notarization hook** in the release workflow, gated on repository
  secrets (`MACOS_NOTARY_PROFILE`, `MACOS_NOTARY_TEAM_ID`). Skipped
  silently when the secrets are not configured.
- 8 new unit tests covering config defaults, allowlist toggle persistence,
  custom-app serialization, and legacy config migration.

### Changed / 变更
- **Default mode is now "All apps"** (`.global`). The app fires in every
  foreground app on a fresh install. Switching to "All apps" from
  "Whitelist" requires confirming a one-time risk dialog.
- The status bar "App Scope" submenu now lists all three modes
  (Whitelist / All apps / Off) instead of two.
- The "AI coding apps" segmented control in the General tab is now a
  three-position control (Whitelist / All apps / Off) with refreshed
  help text pointing users at the App Scope tab for management.

### Migration notes / 迁移说明
- Existing `apps` array in `config.json` is migrated automatically. IDs
  matching the built-in catalog become enabled entries in
  `enabledDefaultApps`; unknown IDs become `customApps` so no entry is
  dropped silently.
- Pre-existing config files that lack the new fields keep their
  effective behavior (Whitelist + previous apps list) for one launch;
  subsequent writes adopt the new schema.

## [0.4.0] - 2026-05

- Settings window, automatic saves, duplicate-shortcut detection, English
  and Simplified Chinese UI.

## [0.3.0] - 2026-04

- Initial Settings UI for sensitivity, cooldown, and pause controls.

## [0.2.0] - 2026-03

- First public Swift menubar build with tap and shortcut input.
