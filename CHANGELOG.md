# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.7] - 2026-05-04

### Fixed

- Explicitly disabled SSL in the isolated safe-mode MariaDB import client and unset inherited MySQL/MariaDB SSL environment variables before Frappe's shell restore runs.
- Verified the isolated import client against the same root route before site creation so client SSL issues fail earlier with a clearer message.

## [1.0.6] - 2026-05-04

### Fixed

- Reset stale safe-mode site database users before first site creation when the target database does not exist, preventing old account requirements such as `REQUIRE SSL` from surviving Frappe's `CREATE USER IF NOT EXISTS` path.

## [1.0.5] - 2026-05-04

### Fixed

- Isolated Frappe's safe-mode MariaDB import client from user/global client option files, preventing inherited SSL-required settings from breaking local non-SSL MariaDB restores.

## [1.0.4] - 2026-05-04

### Fixed

- Validated safe-mode MariaDB root passwords before site creation and allowed up to three attempts.
- Used the verified MariaDB connection route during safe-mode site creation so Frappe's Python setup and shell-based SQL import target the same local database server.
- Recovered from partial failed site directories by moving them aside on rerun, forcing site recreation, and resetting stale target MariaDB users.

## [1.0.3] - 2026-05-04

### Fixed

- Avoided failing on package-manager-installed `uv` binaries by validating a minimum `uv` version before attempting any self-update.
- Added package-manager-specific `uv` update guidance when the detected version is too old.

## [1.0.2] - 2026-05-04

### Fixed

- Started bench-local Redis queue/cache services before site app installs so ERPNext v16 install hooks can enqueue jobs on ports such as `11000`.
- Stopped only the temporary bench Redis services started by the installer, preserving existing manual benches.
- Added an ERPNext partial-install recovery path that reruns `install-app erpnext --force` when ERPNext is listed but the installer completion marker is missing.

## [1.0.1] - 2026-04-16

### Added

- Added optional ordered custom app installation from `apps.txt`.
- Added final health check for bench, site, installed apps, and key binaries.

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
