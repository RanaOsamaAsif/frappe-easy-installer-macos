# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.1] - 2026-04-16

### Fixed

- Prevented false early exit after confirmation prompt due to strict-mode shell flow.
- Hardened `uv` and `volta` installer pipes with `pipefail` and binary existence checks.
- Added timeout and better progress UX for long-running commands, especially `bench init`.
- Fixed spinner output artifacts and line-clearing issues that caused duplicated status text.
- Made bench CLI environment creation idempotent with `uv venv --clear`.
- Added detection/fail-fast behavior for background processes stopped while waiting for input.
- Installed missing `pkgconf` (`pkg-config`) dependency automatically before bench initialization.
- Prevented hidden hangs on bench rollback prompt by auto-answering rollback question.
- Updated Frappe v16 stack defaults to current requirements:
  - Python `3.14`
  - Node `24`
  - MariaDB `11.8`
- Added `mariadb-connector-c` dependency install for improved DB client compatibility.
- Enforced Yarn Classic (`1.22.x`) for bench compatibility with `--check-files`.
- Pinned Yarn registry to `https://registry.npmjs.org` to avoid `registry.yarnpkg.com` DNS failures.

## [1.0.0] - 2026-04-16

### Added

- Initial `frappe-install.sh` release for macOS.
- Interactive installer flow for selecting Frappe version, bench name, site, and ERPNext option.
- Pre-flight checks for OS/version, disk space, internet, Xcode tools, Homebrew, and MariaDB state.
- Safe mode for existing MariaDB setups to avoid modifying active DB configuration/auth.
- Automated installation flow using:
  - Homebrew dependencies
  - `uv` for Python tooling
  - `volta` for Node/Yarn
  - bench CLI setup, bench init, site creation, optional ERPNext, and asset build
- README and MIT license.

