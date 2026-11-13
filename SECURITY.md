# Security Policy

## Supported Versions

| Version        | Supported  |
| -------------- | ---------- |
| Latest release | ✅ Current |

Only the latest release receives security fixes. Please update to the latest
version before reporting issues found in older releases.

## Reporting a Vulnerability

Please do **not** open public issues for security problems. Report privately instead:

- **GitHub Security Advisory**: https://github.com/LarsArtmann/nixos-modules/security/advisories/new

### What to include

- Vulnerability type and severity
- Steps to reproduce
- Potential impact
- Proof of concept (if available)

### Response commitments

| Phase            | Timeline                    |
| ---------------- | --------------------------- |
| Initial response | Within 48 hours             |
| Triage           | Within 72 hours             |
| Disclosure       | Coordinated, within 90 days |

## Security Practices

- All changes are code-reviewed before merge
- Automated checks run in CI via `nix flake check` (`.github/workflows/check.yml`:
  formatting gate, module introspection, eval contracts, VM tests, aarch64
  eval portability)
- Dependencies are kept up to date

---

_Maintained with [securitymd](https://github.com/LarsArtmann/securitymd). Last updated: 2026-11-12._
