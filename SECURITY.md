# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in LidIA, please report it responsibly. **Do not open a public GitHub issue for security vulnerabilities.**

### How to Report

1. **Preferred:** Use [GitHub's private vulnerability reporting](https://github.com/lidia-app/LidIA/security/advisories/new) to submit a report directly on this repository.
2. **Email:** Send details to **julio@juliops.eu**.

### What to Include

- A description of the vulnerability and its potential impact
- Steps to reproduce the issue
- Any relevant logs, screenshots, or proof-of-concept code
- Your suggested fix, if you have one

### What Qualifies as a Security Issue

- Authentication or authorization bypasses
- Data exposure or leakage (transcripts, API keys, meeting content)
- Remote code execution
- Privilege escalation
- Vulnerabilities in dependencies that affect LidIA

### What Does NOT Qualify

- Bugs that don't have a security impact (please open a regular issue instead)
- Feature requests
- Questions about configuration or usage

## Response Timeline

- **Acknowledgment:** Within **72 hours** of your report
- **Initial assessment:** Within 1 week
- **Fix timeline:** Depends on severity — critical issues will be prioritized for immediate patching

## Security Architecture

LidIA is designed with a **local-first, privacy-focused** architecture:

- **API keys** are stored in the **macOS Keychain**, never in plain text files or UserDefaults
- **Meeting data stays on your device** — transcripts, summaries, and recordings are stored locally via SwiftData
- **Local AI by default** — MLX and Parakeet run entirely on-device with no network calls
- **Cloud providers are optional** — OpenAI, Anthropic, and other cloud APIs are only contacted when explicitly configured by the user
- **No telemetry or analytics** — LidIA does not phone home

## Supported Versions

| Version | Supported |
|---------|-----------|
| 1.x     | Yes       |

We recommend always running the latest version.
