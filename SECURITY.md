# Security Policy

Always Yes is local-first and does not intentionally send data over the network. Security matters because the app uses a privileged daemon to read motion sensors and macOS accessibility permissions to send Enter.

## Supported Versions

Security fixes are considered for the latest public release and the current `main` branch.

| Version | Supported |
| --- | --- |
| v0.2.x | Yes |
| older | Best effort |

## Reporting a Vulnerability

Please do not open a public GitHub issue for vulnerabilities.

Instead, contact the maintainer through GitHub:

- Maintainer: https://github.com/359392475-blue-sky
- Repository: https://github.com/359392475-blue-sky/always-yes

Include:

- A short description of the issue.
- Affected version or commit.
- Reproduction steps.
- Potential impact.
- Any suggested fix, if known.

## Scope

In scope:

- Privilege escalation paths.
- Unsafe daemon installation or update behavior.
- XPC misuse.
- Unexpected keyboard event generation outside user intent.
- Privacy issues or unexpected network behavior.

Out of scope:

- Unsupported hardware behavior without a security impact.
- General macOS permission prompts behaving as designed.
- Social engineering unrelated to this repository.
