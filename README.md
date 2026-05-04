# Frappe Easy Installer (macOS)

[![GitHub License](https://img.shields.io/github/license/RanaOsamaAsif/frappe-easy-installer-macos?style=for-the-badge)](https://github.com/RanaOsamaAsif/frappe-easy-installer-macos/blob/main/LICENSE)
[![GitHub Last Commit](https://img.shields.io/github/last-commit/RanaOsamaAsif/frappe-easy-installer-macos?style=for-the-badge)](https://github.com/RanaOsamaAsif/frappe-easy-installer-macos/commits/main)
[![Status](https://img.shields.io/badge/status-actively%20maintained-brightgreen?style=for-the-badge)](https://github.com/RanaOsamaAsif/frappe-easy-installer-macos)

A single interactive Bash script that sets up a complete Frappe development environment on macOS with modern tooling (`uv` + `volta`), clean output, and idempotent re-runs.

## Highlights

- macOS-only, with Apple Silicon and Intel Homebrew path handling.
- Pre-flight checks before any installation starts.
- Frappe version choice:
  - v15 (`Python 3.11`, `Node 18`, `MariaDB 10.11`)
  - v16 (`Python 3.14`, `Node 24`, `MariaDB 11.8`)
- Uses:
  - `uv` for Python/runtime tooling
  - `volta` for Node and Yarn Classic (`1.22.x`)
- Optional ERPNext installation.
- Optional ordered custom app installation from `apps.txt`.
- Safe mode for existing MariaDB installs (recommended when migrating an existing setup).
- Final health check before completion.
- Clear spinner-based UX with full logs only on failure.

## Requirements

- macOS Ventura (13) or newer
- Internet connection
- Xcode Command Line Tools
- At least 10 GB free disk space

## Quick Start

```bash
git clone https://github.com/RanaOsamaAsif/frappe-easy-installer-macos.git
cd frappe-easy-installer-macos
chmod +x ./frappe-install.sh
./frappe-install.sh
```

## Existing Frappe/MariaDB Users

If the installer detects port `3306` already in use, it now asks:

- `Use safe mode and reuse existing MariaDB? [Y/n]`

Choose `Y` (recommended) to avoid modifying your current MariaDB configuration, auth, and service state.

If root passwordless access is unavailable in safe mode, the script asks whether you remember the root password.
If you do not, it fails fast and points you to the reset guide:

- https://gist.github.com/petehouston/13bfc8cba1991cc6741fbe28cfa5491c

## Custom Apps

Add optional Frappe apps to `apps.txt` before running the installer.

```txt
# <git_url> [branch]
https://github.com/frappe/hrms.git version-16
https://github.com/frappe/payments.git version-16
```

Rules:

- Apps install top-to-bottom after the site is created.
- Blank lines and full-line comments are ignored.
- Leave `apps.txt` comment-only to skip custom apps.
- The optional branch column is recommended for versioned Frappe apps.
- The repository name should match the Frappe app name because the installer uses it for idempotency and `bench install-app`.

## What This Installer Does

1. Runs compatibility and environment checks.
2. Installs required dependencies (`mariadb`, `redis`) and installs `wkhtmltopdf` via Homebrew or the upstream macOS package fallback.
3. Installs or updates `uv` and `volta`.
4. Creates a dedicated bench CLI virtual environment.
5. Initializes bench (or reuses existing bench if selected).
6. Creates/uses site, optionally installs ERPNext and apps from `apps.txt`, then builds assets.
7. Runs a final health check for bench, site, installed apps, and key binaries.
8. Persists minimal shell exports for `uv`/`volta`.

## Scope

- Intended for local development only.
- Not a production deployment script.

## PDF Generation Note

Homebrew has removed the `wkhtmltopdf` cask because the project is discontinued upstream. When that happens, the installer downloads the archived upstream macOS package to `/tmp/wkhtmltox-0.12.6-2.macos-cocoa.pkg`, verifies its SHA-256 checksum, and installs it with `sudo installer`.

The package installs `wkhtmltopdf` to `/usr/local/bin/wkhtmltopdf`. If sudo is unavailable or the package install fails, the rest of the Frappe setup continues, but PDF generation needs `wkhtmltopdf` available in `PATH`.

## License

MIT. See [LICENSE](./LICENSE).
