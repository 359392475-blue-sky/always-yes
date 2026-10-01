# Contributing to Always Yes

Thanks for helping improve Always Yes. This project is small, hardware-sensitive, and security-sensitive because it reads Apple Silicon motion data through a privileged daemon and sends keyboard events through macOS accessibility permissions.

## Good First Contributions

- Documentation fixes and setup clarifications.
- Hardware compatibility reports for Apple Silicon models.
- Reproducible bug reports for false positives or missed taps.
- Small UI copy improvements in the menu-bar app.
- Tests or diagnostics around detection thresholds and permission states.

## Before Opening an Issue

Please include:

- macOS version.
- Mac model and chip.
- Whether Accessibility permission is granted.
- Whether the daemon is installed and running.
- Steps to reproduce.
- Expected behavior and actual behavior.

Do not paste private logs, account tokens, or unrelated system information.

## Pull Request Guidelines

1. Keep the pull request focused on one change.
2. Explain the user-visible behavior change.
3. Include manual test steps.
4. Update `README.md` when setup, permissions, or supported hardware changes.
5. Avoid adding network calls or telemetry without a clear issue discussion first.

## Local Development

```bash
git clone https://github.com/359392475-blue-sky/always-yes.git
cd always-yes/app
swift build
```

To build the app bundle:

```bash
cd app
./Bundle/build-app.sh
```

## Security-Sensitive Areas

Please be extra careful with changes touching:

- The root daemon.
- XPC boundaries.
- Accessibility permissions.
- Keyboard event generation.
- Installer or launch daemon plist files.

For suspected vulnerabilities, follow `SECURITY.md` instead of opening a public issue.
