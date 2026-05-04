#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_VERSION="1.0.2"
MIN_MACOS_MAJOR=13
HOMEBREW_PREFIX_ARM="/opt/homebrew"
HOMEBREW_PREFIX_INTEL="/usr/local"
UV_INSTALL_URL="https://astral.sh/uv/install.sh"
VOLTA_INSTALL_URL="https://get.volta.sh"
MARIADB_RESET_GUIDE_URL="https://gist.github.com/petehouston/13bfc8cba1991cc6741fbe28cfa5491c"
WKHTMLTOPDF_DOWNLOADS_URL="https://wkhtmltopdf.org/downloads.html"
WKHTMLTOPDF_PKG_VERSION="0.12.6-2"
WKHTMLTOPDF_PKG_NAME="wkhtmltox-${WKHTMLTOPDF_PKG_VERSION}.macos-cocoa.pkg"
WKHTMLTOPDF_PKG_URL="https://github.com/wkhtmltopdf/packaging/releases/download/${WKHTMLTOPDF_PKG_VERSION}/${WKHTMLTOPDF_PKG_NAME}"
WKHTMLTOPDF_PKG_SHA256="81a66b77b508fede8dbcaa67127203748376568b3673a17f6611b6d51e9894f8"
WKHTMLTOPDF_INSTALL_BIN="/usr/local/bin/wkhtmltopdf"

FRAPPE_15_PYTHON="3.11"
FRAPPE_15_NODE="18"
FRAPPE_15_MARIADB="10.11"

FRAPPE_16_PYTHON="3.14"
FRAPPE_16_NODE="24"
FRAPPE_16_MARIADB="11.8"
YARN_CLASSIC_VERSION="1.22.22"
YARN_REGISTRY_URL="https://registry.npmjs.org"

MARIADB_VERSION="$FRAPPE_15_MARIADB"
BENCH_INIT_TIMEOUT=2700

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

print_header()  { echo -e "\n${BOLD}${BLUE}══════════════════════════════${RESET}"; echo -e "${BOLD}${BLUE}  $1${RESET}"; echo -e "${BOLD}${BLUE}══════════════════════════════${RESET}\n"; }
print_step()    { echo -e "${CYAN}  ▸ $1${RESET}"; }
print_ok()      { echo -e "${GREEN}  ✓ $1${RESET}"; }
print_warn()    { echo -e "${YELLOW}  ⚠ $1${RESET}"; }
print_error()   { echo -e "${RED}  ✗ $1${RESET}"; }
print_info()    { echo -e "    ${BLUE}$1${RESET}"; }

spinner() {
  local pid=$1 msg=$2 timeout_seconds=${3:-0}
  local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  local i=0
  local start=$SECONDS
  local elapsed=0
  local elapsed_fmt=""
  local remaining=0
  local remaining_fmt=""

  SPINNER_TIMED_OUT=0
  SPINNER_STOPPED=0

  while kill -0 "$pid" 2>/dev/null; do
    # Detect job-control stops (commonly SIGTTIN when a background command prompts).
    if (( i % 12 == 0 )); then
      local proc_state=""
      proc_state="$("$PS_BIN" -o state= -p "$pid" 2>/dev/null | "$AWK_BIN" '{print $1}')"
      if [[ "$proc_state" == "T" ]]; then
        SPINNER_STOPPED=1
        kill -TERM "$pid" 2>/dev/null || true
        sleep 1
        kill -KILL "$pid" 2>/dev/null || true
        break
      fi
    fi

    elapsed=$((SECONDS - start))

    if (( timeout_seconds > 0 && elapsed >= timeout_seconds )); then
      SPINNER_TIMED_OUT=1
      kill -TERM "$pid" 2>/dev/null || true
      sleep 2
      kill -KILL "$pid" 2>/dev/null || true
      break
    fi

    elapsed_fmt=$(printf "%02dm%02ds" $((elapsed / 60)) $((elapsed % 60)))
    if (( timeout_seconds > 0 )); then
      remaining=$((timeout_seconds - elapsed))
      (( remaining < 0 )) && remaining=0
      remaining_fmt=$(printf "%02dm%02ds" $((remaining / 60)) $((remaining % 60)))
      printf "\r  ${CYAN}%s${RESET}  %s ${BLUE}[%s elapsed, %s left]${RESET}" \
        "${frames[$((i % 10))]}" "$msg" "$elapsed_fmt" "$remaining_fmt"
    else
      printf "\r  ${CYAN}%s${RESET}  %s ${BLUE}[%s elapsed]${RESET}" \
        "${frames[$((i % 10))]}" "$msg" "$elapsed_fmt"
    fi

    sleep 0.08
    i=$((i + 1))
  done
  printf "\r\033[K"
}

run_silent() {
  local msg=$1
  shift

  local log
  log=$(mktemp)
  local timeout_seconds="${RUN_TIMEOUT_SECONDS:-0}"

  "$@" </dev/null >"$log" 2>&1 &
  local pid=$!

  spinner "$pid" "$msg" "$timeout_seconds"

  local exit_code=0
  wait "$pid" || exit_code=$?

  if [[ "${SPINNER_STOPPED:-0}" -eq 1 ]]; then
    print_error "$msg - stopped while waiting for input (non-interactive mode)"
    echo -e "\n${RED}--- Last 100 lines before stop ---${RESET}"
    "$TAIL_BIN" -n 100 "$log" || true
    echo -e "${RED}--- End ---${RESET}\n"
    rm -f "$log"
    return 125
  fi

  if [[ "${SPINNER_TIMED_OUT:-0}" -eq 1 ]]; then
    print_error "$msg - timed out after ${timeout_seconds}s"
    echo -e "\n${RED}--- Last 100 lines before timeout ---${RESET}"
    "$TAIL_BIN" -n 100 "$log" || true
    echo -e "${RED}--- End ---${RESET}\n"
    rm -f "$log"
    return 124
  fi

  if [[ $exit_code -ne 0 ]]; then
    print_error "$msg - failed"
    echo -e "\n${RED}--- Output ---${RESET}"
    cat "$log"
    echo -e "${RED}--- End ---${RESET}\n"
    rm -f "$log"
    return "$exit_code"
  fi

  rm -f "$log"
  print_ok "$msg"
}

cleanup() {
  local exit_code=$?
  if [[ $exit_code -eq 0 ]]; then
    return 0
  fi

  stop_started_bench_redis "quiet" || true

  echo ""
  print_error "Installation failed at step: ${CURRENT_STEP:-unknown}"
  print_info "The script is idempotent - fix the issue above and re-run"
  print_info "If a command failed inside run_silent, logs were printed above"
  print_info "If no logs appeared, failure happened in script control flow (not a wrapped command)"
}
trap cleanup EXIT

UNAME_BIN="/usr/bin/uname"
SW_VERS_BIN="/usr/bin/sw_vers"
DF_BIN="/bin/df"
CURL_BIN="/usr/bin/curl"
XCODE_SELECT_BIN="/usr/bin/xcode-select"
BASH_BIN="/bin/bash"
AWK_BIN="/usr/bin/awk"
GREP_BIN="/usr/bin/grep"
LFS_BIN="/usr/sbin/lsof"
PS_BIN="/bin/ps"
BASENAME_BIN="/usr/bin/basename"
TAIL_BIN="/usr/bin/tail"
DIRNAME_BIN="/usr/bin/dirname"
PWD_BIN="/bin/pwd"
INSTALLER_BIN="/usr/sbin/installer"
SHASUM_BIN="/usr/bin/shasum"
SUDO_BIN="/usr/bin/sudo"

ARCH=""
MACOS_VERSION=""
MACOS_MAJOR=""
DISK_AVAILABLE_GB=""
BREW_BIN=""
BREW_VERSION=""
HOMEBREW_PREFIX=""

FRAPPE_VERSION=""
PYTHON_VERSION=""
NODE_VERSION=""
BENCH_NAME=""
SITE_NAME=""
INSTALL_ERPNEXT="Y"
ADMIN_PASSWORD="admin"
SKIP_INIT="n"
DB_ROOT_PASSWORD=""

MARIADB_INSTALLED="false"
MARIADB_PORT_IN_USE="false"
MANAGE_MARIADB="true"
MARIADB_ROOT_PASSWORDLESS="false"
SCRIPT_DIR=""
CUSTOM_APPS_FILE=""
CUSTOM_APP_URLS=()
CUSTOM_APP_BRANCHES=()
CUSTOM_APP_NAMES=()
BENCH_REDIS_STARTED_PORTS=()

check_macos() {
  print_step "Checking macOS compatibility"

  if [[ "$($UNAME_BIN -s)" != "Darwin" ]]; then
    print_error "This installer supports macOS only"
    exit 1
  fi

  MACOS_VERSION="$($SW_VERS_BIN -productVersion)"
  MACOS_MAJOR="${MACOS_VERSION%%.*}"
  ARCH="$($UNAME_BIN -m)"

  if (( MACOS_MAJOR < MIN_MACOS_MAJOR )); then
    print_error "macOS $MIN_MACOS_MAJOR or newer is required (detected: $MACOS_VERSION)"
    exit 1
  fi

  if [[ "$ARCH" == "arm64" ]]; then
    HOMEBREW_PREFIX="$HOMEBREW_PREFIX_ARM"
  else
    HOMEBREW_PREFIX="$HOMEBREW_PREFIX_INTEL"
  fi

  print_ok "Detected macOS $MACOS_VERSION on $ARCH"
}

check_not_root() {
  print_step "Checking privileges"

  if [[ $EUID -eq 0 ]]; then
    print_error "Do not run as root"
    exit 1
  fi

  print_ok "Running as a regular user"
}

check_disk_space() {
  print_step "Checking available disk space"

  DISK_AVAILABLE_GB="$($DF_BIN -g "$HOME" | $AWK_BIN 'NR==2 {print int($4)}' 2>/dev/null || true)"

  if [[ -z "$DISK_AVAILABLE_GB" ]]; then
    local kb_available
    kb_available="$($DF_BIN -Pk "$HOME" | $AWK_BIN 'NR==2 {print int($4)}')"
    DISK_AVAILABLE_GB=$((kb_available / 1024 / 1024))
  fi

  if (( DISK_AVAILABLE_GB < 10 )); then
    print_error "At least 10 GB free space is required (available: ${DISK_AVAILABLE_GB}GB)"
    exit 1
  fi

  print_ok "${DISK_AVAILABLE_GB}GB available"
}

check_internet() {
  print_step "Checking internet connectivity"

  if ! "$CURL_BIN" -sf --max-time 5 https://1.1.1.1 >/dev/null; then
    print_error "No internet connection detected (failed to reach 1.1.1.1)"
    exit 1
  fi

  print_ok "Internet connection is available"
}

check_xcode_tools() {
  print_step "Checking Xcode Command Line Tools"

  if "$XCODE_SELECT_BIN" -p >/dev/null 2>&1; then
    print_ok "Xcode Command Line Tools detected"
    return
  fi

  print_warn "Xcode Command Line Tools are missing"
  print_info "A macOS dialog should appear now. Complete installation, then return here."
  "$XCODE_SELECT_BIN" --install || true

  read -rp "  Press Enter after Xcode Command Line Tools installation finishes... "

  if ! "$XCODE_SELECT_BIN" -p >/dev/null 2>&1; then
    print_error "Xcode Command Line Tools still not detected"
    exit 1
  fi

  print_ok "Xcode Command Line Tools installed"
}

check_homebrew() {
  print_step "Checking Homebrew"

  if ! command -v brew >/dev/null 2>&1; then
    print_info "Installing Homebrew..."
    "$BASH_BIN" -c "$("$CURL_BIN" -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi

  export PATH="$HOMEBREW_PREFIX/bin:$PATH"
  BREW_BIN="$HOMEBREW_PREFIX/bin/brew"

  if [[ ! -x "$BREW_BIN" ]]; then
    BREW_BIN="$(command -v brew || true)"
  fi

  if [[ -z "$BREW_BIN" || ! -x "$BREW_BIN" ]]; then
    print_error "Homebrew was not found after installation"
    exit 1
  fi

  BREW_VERSION="$($BREW_BIN --version | $AWK_BIN 'NR==1 {print $2}')"
  print_ok "Homebrew available"

  local doctor_output
  doctor_output="$($BREW_BIN doctor 2>&1 || true)"

  if echo "$doctor_output" | $GREP_BIN -q "Your system is ready"; then
    print_ok "Homebrew doctor: system is ready"
  else
    print_warn "Homebrew doctor reported warnings (continuing)"
    while IFS= read -r line; do
      [[ -n "$line" ]] && print_warn "$line"
    done <<< "$doctor_output"
  fi
}

check_existing_mariadb() {
  print_step "Checking existing MariaDB/MySQL state"

  local detected_mariadb_version=""
  if "$BREW_BIN" list "mariadb@$FRAPPE_16_MARIADB" >/dev/null 2>&1; then
    detected_mariadb_version="$FRAPPE_16_MARIADB"
  elif "$BREW_BIN" list "mariadb@$FRAPPE_15_MARIADB" >/dev/null 2>&1; then
    detected_mariadb_version="$FRAPPE_15_MARIADB"
  fi

  if [[ -n "$detected_mariadb_version" ]]; then
    MARIADB_INSTALLED="true"
    print_ok "MariaDB $detected_mariadb_version already installed"
  else
    print_info "No supported MariaDB version detected yet (will install selected version)"
  fi

  local port_info
  port_info="$($LFS_BIN -nP -iTCP:3306 -sTCP:LISTEN 2>/dev/null || true)"

  if [[ -n "$port_info" ]]; then
    MARIADB_PORT_IN_USE="true"
    print_warn "Detected an existing database process on port 3306:"
    echo "$port_info"
    echo ""
    print_info "Safe mode keeps existing MariaDB untouched (recommended for existing Frappe installs)."
    read -rp "  Use safe mode and reuse existing MariaDB? [Y/n]: " safe_mode_choice

    if [[ "${safe_mode_choice:-Y}" =~ ^[Nn]$ ]]; then
      MANAGE_MARIADB="true"
      print_warn "Managed mode selected - installer may modify MariaDB auth/config."
      read -rp "  Continue in managed mode? [y/N]: " continue_managed
      if [[ ! "$continue_managed" =~ ^[Yy]$ ]]; then
        print_error "Aborted by user"
        exit 1
      fi
    else
      MANAGE_MARIADB="false"
      print_ok "Safe mode enabled for existing MariaDB"
    fi
  fi

  local mysql_candidate=""

  if [[ -x "$HOMEBREW_PREFIX/opt/mariadb@$FRAPPE_16_MARIADB/bin/mysql" ]]; then
    mysql_candidate="$HOMEBREW_PREFIX/opt/mariadb@$FRAPPE_16_MARIADB/bin/mysql"
  elif [[ -x "$HOMEBREW_PREFIX/opt/mariadb@$FRAPPE_15_MARIADB/bin/mysql" ]]; then
    mysql_candidate="$HOMEBREW_PREFIX/opt/mariadb@$FRAPPE_15_MARIADB/bin/mysql"
  elif command -v mysql >/dev/null 2>&1; then
    mysql_candidate="$(command -v mysql)"
  fi

  if [[ -n "$mysql_candidate" ]]; then
    if "$mysql_candidate" -u root -e "SELECT 1" >/dev/null 2>&1; then
      MARIADB_ROOT_PASSWORDLESS="true"
      print_ok "MariaDB root is accessible"
    elif [[ "$MANAGE_MARIADB" == "true" && -n "$detected_mariadb_version" ]]; then
      if command -v mariadb >/dev/null 2>&1 && sudo -n mariadb -e "SELECT 1" >/dev/null 2>&1; then
        print_ok "MariaDB root accessible with sudo fallback"
      else
        print_warn "MariaDB root is not currently accessible; installer will configure root auth"
      fi
    elif [[ "$MANAGE_MARIADB" != "true" ]]; then
      print_warn "Could not verify passwordless MariaDB root; you can provide root password during prompts"
    fi
  fi
}

print_preflight_summary() {
  local mariadb_mode="managed"
  if [[ "$MANAGE_MARIADB" != "true" ]]; then
    mariadb_mode="safe/reuse-existing"
  fi

  echo -e "  macOS version    ${GREEN}✓${RESET}  $MACOS_VERSION ($ARCH)"
  echo -e "  Disk space       ${GREEN}✓${RESET}  ${DISK_AVAILABLE_GB}GB available"
  echo -e "  Internet         ${GREEN}✓${RESET}"
  echo -e "  Xcode tools      ${GREEN}✓${RESET}"
  echo -e "  Homebrew         ${GREEN}✓${RESET}  $BREW_VERSION"
  echo -e "  MariaDB mode     ${GREEN}✓${RESET}  $mariadb_mode"
}

prompt_for_inputs() {
  print_header "Frappe version"
  echo "  Which version would you like to install?"
  echo ""
  echo "  [1] Frappe v15  (Python 3.11, Node 18, MariaDB 10.11, stable)"
  echo "  [2] Frappe v16  (Python 3.14, Node 24, MariaDB 11.8, latest)"
  echo ""
  read -rp "  Enter choice [1/2]: " version_choice

  case $version_choice in
    1)
      FRAPPE_VERSION="version-15"
      PYTHON_VERSION="$FRAPPE_15_PYTHON"
      NODE_VERSION="$FRAPPE_15_NODE"
      MARIADB_VERSION="$FRAPPE_15_MARIADB"
      ;;
    2)
      FRAPPE_VERSION="version-16"
      PYTHON_VERSION="$FRAPPE_16_PYTHON"
      NODE_VERSION="$FRAPPE_16_NODE"
      MARIADB_VERSION="$FRAPPE_16_MARIADB"
      ;;
    *)
      print_error "Invalid choice"
      exit 1
      ;;
  esac

  echo ""
  read -rp "  Bench folder name [frappe-bench-$version_choice]: " BENCH_NAME
  BENCH_NAME="${BENCH_NAME:-frappe-bench-$version_choice}"

  if [[ ! "$BENCH_NAME" =~ ^[a-zA-Z0-9._-]+$ ]]; then
    print_error "Bench folder name can only contain letters, numbers, dot, underscore, and hyphen"
    exit 1
  fi

  if [[ -e "$HOME/$BENCH_NAME" && ! -d "$HOME/$BENCH_NAME" ]]; then
    print_error "$HOME/$BENCH_NAME exists but is not a directory"
    exit 1
  fi

  if [[ -d "$HOME/$BENCH_NAME" ]]; then
    if [[ -n "$(ls -A "$HOME/$BENCH_NAME" 2>/dev/null)" ]]; then
      print_warn "Folder $HOME/$BENCH_NAME already exists"
      read -rp "  Continue anyway and skip bench init? [y/N]: " skip_init_choice
      if [[ "$skip_init_choice" =~ ^[Yy]$ ]]; then
        SKIP_INIT="y"
      else
        exit 1
      fi
    fi
  fi

  read -rp "  Site name [site.local]: " SITE_NAME
  SITE_NAME="${SITE_NAME:-site.local}"

  if [[ ! "$SITE_NAME" =~ ^[a-zA-Z0-9.-]+$ ]]; then
    print_error "Site name can only contain letters, numbers, dot, and hyphen"
    exit 1
  fi

  read -rp "  Install ERPNext? [Y/n]: " INSTALL_ERPNEXT
  INSTALL_ERPNEXT="${INSTALL_ERPNEXT:-Y}"

  read -rsp "  Admin password [admin]: " ADMIN_PASSWORD
  echo ""
  ADMIN_PASSWORD="${ADMIN_PASSWORD:-admin}"

  if [[ "$MANAGE_MARIADB" != "true" ]]; then
    if [[ "$MARIADB_ROOT_PASSWORDLESS" == "true" ]]; then
      print_ok "Detected passwordless MariaDB root access"
      DB_ROOT_PASSWORD=""
    else
      read -rp "  Do you remember your MariaDB root password? [Y/n]: " remembers_db_password
      if [[ "${remembers_db_password:-Y}" =~ ^[Nn]$ ]]; then
        print_error "Cannot continue without MariaDB root access."
        print_info "Reset root password first (guide): $MARIADB_RESET_GUIDE_URL"
        print_info "Then re-run this installer."
        exit 1
      fi
      read -rsp "  MariaDB root password: " DB_ROOT_PASSWORD
      echo ""
    fi
  fi

  echo ""
  print_header "Installation summary"
  echo "  Frappe version  :  $FRAPPE_VERSION"
  echo "  Python          :  $PYTHON_VERSION"
  echo "  Node            :  $NODE_VERSION"
  echo "  MariaDB         :  $MARIADB_VERSION"
  echo "  Bench folder    :  $HOME/$BENCH_NAME"
  echo "  Site name       :  $SITE_NAME"
  echo "  ERPNext         :  $([[ $INSTALL_ERPNEXT =~ ^[Yy] ]] && echo yes || echo no)"
  echo "  MariaDB mode    :  $([[ \"$MANAGE_MARIADB\" == \"true\" ]] && echo managed || echo safe/reuse-existing)"
  echo ""
  read -rp "  Proceed? [Y/n]: " confirm
  if [[ "$confirm" =~ ^[Nn] ]]; then
    exit 0
  fi

  return 0
}

install_dependencies() {
  CURRENT_STEP="Installing Homebrew dependencies"
  print_header "Installing dependencies"

  if [[ "$MANAGE_MARIADB" == "true" ]]; then
    run_silent "Updating Homebrew" "$BREW_BIN" update
  else
    print_warn "Safe mode: skipping Homebrew update to reduce changes on existing setup"
  fi

  if [[ "$MANAGE_MARIADB" == "true" ]]; then
    run_silent "Installing MariaDB $MARIADB_VERSION" "$BREW_BIN" install "mariadb@$MARIADB_VERSION"
  else
    print_ok "Safe mode: skipping MariaDB install/update"
  fi

  if "$BREW_BIN" list redis >/dev/null 2>&1; then
    print_ok "Redis already installed"
  else
    run_silent "Installing Redis" "$BREW_BIN" install redis
  fi

  install_wkhtmltopdf

  if "$BREW_BIN" list mariadb-connector-c >/dev/null 2>&1; then
    print_ok "mariadb-connector-c already installed"
  else
    run_silent "Installing mariadb-connector-c" "$BREW_BIN" install mariadb-connector-c
  fi

  if command -v pkg-config >/dev/null 2>&1; then
    print_ok "pkg-config already installed"
  else
    run_silent "Installing pkgconf (pkg-config)" "$BREW_BIN" install pkgconf
  fi

  if [[ -d "$HOMEBREW_PREFIX/opt/mariadb@$MARIADB_VERSION/bin" ]]; then
    export PATH="$HOMEBREW_PREFIX/opt/mariadb@$MARIADB_VERSION/bin:$PATH"
  fi
}

install_wkhtmltopdf() {
  if command -v wkhtmltopdf >/dev/null 2>&1; then
    print_ok "wkhtmltopdf already available"
    return
  fi

  if "$BREW_BIN" list --cask wkhtmltopdf >/dev/null 2>&1; then
    print_ok "wkhtmltopdf cask already installed"
    return
  fi

  if "$BREW_BIN" info --cask wkhtmltopdf >/dev/null 2>&1; then
    if run_silent "Installing wkhtmltopdf" "$BREW_BIN" install --cask wkhtmltopdf; then
      return
    fi

    print_warn "wkhtmltopdf could not be installed with Homebrew; trying upstream package fallback"
  else
    print_warn "wkhtmltopdf Homebrew cask is unavailable; trying upstream package fallback"
  fi

  install_wkhtmltopdf_pkg
}

verify_wkhtmltopdf_pkg() {
  local pkg_path=$1
  local actual_sha

  [[ -f "$pkg_path" ]] || return 1

  actual_sha="$("$SHASUM_BIN" -a 256 "$pkg_path" | "$AWK_BIN" '{print $1}')"
  [[ "$actual_sha" == "$WKHTMLTOPDF_PKG_SHA256" ]]
}

install_wkhtmltopdf_pkg() {
  local pkg_path="/tmp/$WKHTMLTOPDF_PKG_NAME"

  if verify_wkhtmltopdf_pkg "$pkg_path"; then
    print_ok "wkhtmltopdf package already downloaded"
  else
    rm -f "$pkg_path"
    if ! run_silent "Downloading wkhtmltopdf package" "$CURL_BIN" -fL -o "$pkg_path" "$WKHTMLTOPDF_PKG_URL"; then
      print_warn "Could not download wkhtmltopdf package; continuing without it"
      print_info "Manual download: $WKHTMLTOPDF_DOWNLOADS_URL"
      return 0
    fi
  fi

  if ! verify_wkhtmltopdf_pkg "$pkg_path"; then
    print_warn "Downloaded wkhtmltopdf package checksum did not match; skipping package install"
    print_info "Manual download: $WKHTMLTOPDF_DOWNLOADS_URL"
    rm -f "$pkg_path"
    return 0
  fi

  print_info "Installing wkhtmltopdf package requires sudo and may ask for your macOS password."
  if ! "$SUDO_BIN" -v; then
    print_warn "Could not acquire sudo privileges; continuing without wkhtmltopdf"
    print_info "Manual install: sudo installer -pkg $pkg_path -target /"
    return 0
  fi

  if ! run_silent "Installing wkhtmltopdf package" "$SUDO_BIN" "$INSTALLER_BIN" -pkg "$pkg_path" -target /; then
    print_warn "wkhtmltopdf package installation failed; continuing without it"
    print_info "Manual install: sudo installer -pkg $pkg_path -target /"
    return 0
  fi

  export PATH="/usr/local/bin:$PATH"

  if [[ -x "$WKHTMLTOPDF_INSTALL_BIN" ]] || command -v wkhtmltopdf >/dev/null 2>&1; then
    print_ok "wkhtmltopdf package installed"
  else
    print_warn "wkhtmltopdf package installed, but wkhtmltopdf was not found in PATH"
    print_info "Expected binary: $WKHTMLTOPDF_INSTALL_BIN"
  fi

  return 0
}

configure_services() {
  CURRENT_STEP="Configuring MariaDB and Redis"
  print_header "Configuring services"

  if [[ "$MANAGE_MARIADB" != "true" ]]; then
    print_warn "Safe mode enabled - skipping MariaDB config, restart, and root auth changes"
    print_ok "Redis formula available; bench Redis will start from bench config"
    return
  fi

  local mariadb_conf_dir="$HOMEBREW_PREFIX/etc/my.cnf.d"
  mkdir -p "$mariadb_conf_dir"

  cat > "$mariadb_conf_dir/frappe.cnf" <<'CNF'
[mysqld]
character-set-client-handshake = FALSE
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci
innodb-file-format = barracuda
innodb-file-per-table = 1
innodb-large-prefix = 1
skip-name-resolve
CNF
  print_ok "Wrote MariaDB config: $mariadb_conf_dir/frappe.cnf"

  run_silent "Starting MariaDB" "$BREW_BIN" services restart "mariadb@$MARIADB_VERSION"

  local mysqladmin_bin="$HOMEBREW_PREFIX/opt/mariadb@$MARIADB_VERSION/bin/mysqladmin"
  local mysql_bin="$HOMEBREW_PREFIX/opt/mariadb@$MARIADB_VERSION/bin/mysql"

  wait_for_mariadb() {
    local tries=0
    until "$mysqladmin_bin" ping --silent >/dev/null 2>&1; do
      tries=$((tries + 1))
      if [[ $tries -ge 30 ]]; then
        print_error "MariaDB did not become ready in time"
        exit 1
      fi
      sleep 0.5
    done
  }

  configure_mariadb_root() {
    if "$mysql_bin" -uroot -e "SELECT 1;" >/dev/null 2>&1; then
      "$mysql_bin" -uroot <<'SQL'
ALTER USER 'root'@'localhost' IDENTIFIED VIA mysql_native_password USING '';
FLUSH PRIVILEGES;
SQL
      return 0
    fi

    if "$mysql_bin" -uroot -p'' -e "SELECT 1;" >/dev/null 2>&1; then
      print_ok "MariaDB root already configured"
      return 0
    fi

    if sudo -n "$mysql_bin" -uroot -e "SELECT 1;" >/dev/null 2>&1; then
      sudo -n "$mysql_bin" -uroot <<'SQL'
ALTER USER 'root'@'localhost' IDENTIFIED VIA mysql_native_password USING '';
FLUSH PRIVILEGES;
SQL
      return 0
    fi

    print_error "Cannot access MariaDB root. Please check your MariaDB installation."
    print_info "Try running: sudo $mysql_bin -uroot"
    exit 1
  }

  run_silent "Waiting for MariaDB" wait_for_mariadb
  run_silent "Configuring MariaDB root auth" configure_mariadb_root
  print_ok "Redis formula available; bench Redis will start from bench config"
}

install_uv() {
  CURRENT_STEP="Installing uv"
  print_header "Installing uv"

  UV_BIN="$HOME/.local/bin/uv"

  if [[ ! -f "$UV_BIN" ]]; then
    run_silent "Installing uv (Python manager)" \
      "$BASH_BIN" -c "set -euo pipefail; \"$CURL_BIN\" -LsSf \"$UV_INSTALL_URL\" | /bin/sh"
  else
    run_silent "Updating uv" "$UV_BIN" self update
  fi

  if [[ ! -x "$UV_BIN" ]]; then
    print_error "uv binary not found at $UV_BIN after installation/update"
    print_info "Check network/proxy and rerun the installer"
    print_info "Manual command: $CURL_BIN -LsSf $UV_INSTALL_URL | /bin/sh"
    exit 1
  fi

  export PATH="$HOME/.local/bin:$PATH"
}

install_volta() {
  CURRENT_STEP="Installing volta"
  print_header "Installing volta"

  VOLTA_HOME="$HOME/.volta"
  VOLTA_BIN="$VOLTA_HOME/bin/volta"
  YARN_BIN="$VOLTA_HOME/bin/yarn"

  if [[ ! -f "$VOLTA_BIN" ]]; then
    run_silent "Installing volta (Node manager)" \
      "$BASH_BIN" -c "set -euo pipefail; \"$CURL_BIN\" -fsSL \"$VOLTA_INSTALL_URL\" | /bin/bash -s -- --skip-setup"
  fi

  export VOLTA_HOME="$HOME/.volta"
  export PATH="$VOLTA_HOME/bin:$PATH"

  if [[ ! -x "$VOLTA_BIN" ]]; then
    print_error "Volta binary not found at $VOLTA_BIN after installation"
    print_info "Check network/proxy and rerun the installer"
    print_info "Manual command: $CURL_BIN -fsSL $VOLTA_INSTALL_URL | /bin/bash -s -- --skip-setup"
    exit 1
  fi

  run_silent "Installing Node $NODE_VERSION" "$VOLTA_BIN" install "node@$NODE_VERSION"
  run_silent "Installing Yarn $YARN_CLASSIC_VERSION (classic)" "$VOLTA_BIN" install "yarn@$YARN_CLASSIC_VERSION"

  local yarn_version
  yarn_version="$("$YARN_BIN" --version 2>/dev/null || true)"
  if [[ ! "$yarn_version" =~ ^1\. ]]; then
    print_error "Detected unsupported Yarn version: ${yarn_version:-unknown}"
    print_info "Frappe bench currently requires Yarn classic (1.x) for '--check-files'"
    print_info "Try: $VOLTA_BIN install yarn@$YARN_CLASSIC_VERSION"
    exit 1
  fi
  print_ok "Using Yarn $yarn_version (classic)"

  # Avoid registry.yarnpkg.com DNS issues by pinning Yarn to npmjs registry.
  run_silent "Configuring Yarn registry" "$YARN_BIN" config set registry "$YARN_REGISTRY_URL"
}

install_bench_cli() {
  CURRENT_STEP="Installing frappe-bench CLI"
  print_header "Installing bench CLI"

  BENCH_VENV="$HOME/.bench-cli"
  run_silent "Creating bench CLI environment" \
    "$UV_BIN" venv "$BENCH_VENV" --python "$PYTHON_VERSION" --clear

  run_silent "Installing frappe-bench" \
    "$UV_BIN" pip install --python "$BENCH_VENV/bin/python" frappe-bench

  BENCH_BIN="$BENCH_VENV/bin/bench"
}

initialize_bench() {
  CURRENT_STEP="Initializing bench"
  print_header "Initializing bench"
  print_info "Bench init timeout: $((BENCH_INIT_TIMEOUT / 60)) minutes"

  run_bench_init() {
    # If bench init fails, bench may ask for rollback confirmation.
    # Feed a default "n" so non-interactive runs do not hang.
    printf 'n\n' | "$BENCH_BIN" init "$HOME/$BENCH_NAME" \
      --frappe-branch "$FRAPPE_VERSION" \
      --python "$BENCH_VENV/bin/python" \
      --skip-assets
  }

  if [[ ! -d "$HOME/$BENCH_NAME" ]] || [[ "$SKIP_INIT" != "y" ]]; then
    export YARN_REGISTRY="$YARN_REGISTRY_URL"
    export npm_config_registry="$YARN_REGISTRY_URL"
    export PATH="$VOLTA_HOME/bin:$HOME/.local/bin:$HOMEBREW_PREFIX/bin:$PATH"
    RUN_TIMEOUT_SECONDS="$BENCH_INIT_TIMEOUT" run_silent "Initializing bench (this takes a few minutes)" run_bench_init
  else
    print_ok "Skipping bench init (existing directory)"
  fi

  if [[ ! -d "$HOME/$BENCH_NAME" ]]; then
    print_error "Bench directory not found: $HOME/$BENCH_NAME"
    exit 1
  fi

  cd "$HOME/$BENCH_NAME"
}

create_site() {
  CURRENT_STEP="Creating site"
  print_header "Creating site"

  if [[ -d "$HOME/$BENCH_NAME/sites/$SITE_NAME" ]]; then
    print_warn "Site $SITE_NAME already exists - skipping site creation"
  else
    run_silent "Creating site $SITE_NAME" \
      "$BENCH_BIN" new-site "$SITE_NAME" \
        --mariadb-root-password "$DB_ROOT_PASSWORD" \
        --admin-password "$ADMIN_PASSWORD" \
        --db-name "${SITE_NAME//./_}"
  fi

  run_silent "Setting default site" "$BENCH_BIN" use "$SITE_NAME"
}

resolve_redis_server_bin() {
  local redis_server_bin="$HOMEBREW_PREFIX/bin/redis-server"
  if [[ -x "$redis_server_bin" ]]; then
    printf '%s\n' "$redis_server_bin"
    return 0
  fi

  command -v redis-server 2>/dev/null
}

resolve_redis_cli_bin() {
  local redis_cli_bin="$HOMEBREW_PREFIX/bin/redis-cli"
  if [[ -x "$redis_cli_bin" ]]; then
    printf '%s\n' "$redis_cli_bin"
    return 0
  fi

  command -v redis-cli 2>/dev/null
}

redis_port_from_conf() {
  local conf_file="$1"

  "$AWK_BIN" '
    $1 == "port" && $2 ~ /^[0-9]+$/ {
      print $2
      exit
    }
  ' "$conf_file"
}

redis_dir_from_conf() {
  local conf_file="$1"

  "$AWK_BIN" '
    $1 == "dir" {
      value = $2
      gsub(/^"|"$/, "", value)
      print value
      exit
    }
  ' "$conf_file"
}

normalize_redis_dir() {
  local dir_path="$1"

  if [[ -z "$dir_path" ]]; then
    return 0
  fi

  case "$dir_path" in
    /*) ;;
    *) dir_path="$HOME/$BENCH_NAME/$dir_path" ;;
  esac

  if [[ -d "$dir_path" ]]; then
    (cd "$dir_path" && "$PWD_BIN" -P)
  else
    printf '%s\n' "$dir_path"
  fi
}

redis_ping_port() {
  local redis_cli_bin="$1"
  local port="$2"

  "$redis_cli_bin" -h 127.0.0.1 -p "$port" ping 2>/dev/null | "$GREP_BIN" -qx "PONG"
}

redis_running_dir() {
  local redis_cli_bin="$1"
  local port="$2"

  "$redis_cli_bin" -h 127.0.0.1 -p "$port" config get dir 2>/dev/null \
    | "$AWK_BIN" 'NR == 2 { print; exit }'
}

redis_port_matches_conf() {
  local redis_cli_bin="$1"
  local port="$2"
  local conf_file="$3"
  local expected_dir=""
  local actual_dir=""

  expected_dir="$(normalize_redis_dir "$(redis_dir_from_conf "$conf_file")")"
  actual_dir="$(normalize_redis_dir "$(redis_running_dir "$redis_cli_bin" "$port")")"

  [[ -z "$expected_dir" || -z "$actual_dir" || "$expected_dir" == "$actual_dir" ]]
}

wait_for_redis_port() {
  local redis_cli_bin="$1"
  local port="$2"
  local tries=0

  until redis_ping_port "$redis_cli_bin" "$port"; do
    tries=$((tries + 1))
    if [[ $tries -ge 40 ]]; then
      print_error "Redis on port $port did not become ready in time"
      return 1
    fi
    sleep 0.25
  done
}

ensure_bench_redis_services() {
  CURRENT_STEP="Starting bench Redis services"
  print_header "Starting bench Redis services"

  local redis_server_bin
  local redis_cli_bin
  redis_server_bin="$(resolve_redis_server_bin || true)"
  redis_cli_bin="$(resolve_redis_cli_bin || true)"

  if [[ -z "$redis_server_bin" || ! -x "$redis_server_bin" ]]; then
    print_error "redis-server was not found"
    print_info "Install Redis with: $BREW_BIN install redis"
    exit 1
  fi

  if [[ -z "$redis_cli_bin" || ! -x "$redis_cli_bin" ]]; then
    print_error "redis-cli was not found"
    print_info "Install Redis with: $BREW_BIN install redis"
    exit 1
  fi

  local config_dir="$HOME/$BENCH_NAME/config"
  local redis_configs=(
    "$config_dir/redis_queue.conf"
    "$config_dir/redis_cache.conf"
    "$config_dir/redis_socketio.conf"
  )
  local conf_file=""
  local port=""
  local label=""
  local seen_ports=" "
  local found_config="false"

  mkdir -p "$config_dir/pids" "$HOME/$BENCH_NAME/logs"

  for conf_file in "${redis_configs[@]}"; do
    [[ -f "$conf_file" ]] || continue
    found_config="true"

    label="$("$BASENAME_BIN" "$conf_file")"
    port="$(redis_port_from_conf "$conf_file")"

    if [[ -z "$port" ]]; then
      print_warn "Could not read Redis port from $label - skipping"
      continue
    fi

    if [[ "$seen_ports" == *" $port "* ]]; then
      print_ok "Bench Redis port $port already covered"
      continue
    fi
    seen_ports="${seen_ports}${port} "

    if redis_ping_port "$redis_cli_bin" "$port"; then
      if redis_port_matches_conf "$redis_cli_bin" "$port" "$conf_file"; then
        print_ok "Bench Redis $label is already running on port $port"
        continue
      fi

      print_error "Redis port $port is already used by a different Redis instance"
      print_info "Stop the other bench first, or change this bench's Redis ports before rerunning."
      print_info "Current config: $conf_file"
      exit 1
    fi

    run_silent "Starting bench Redis $label on port $port" \
      "$redis_server_bin" "$conf_file" --daemonize yes
    BENCH_REDIS_STARTED_PORTS+=("$port")
    run_silent "Waiting for bench Redis $label" wait_for_redis_port "$redis_cli_bin" "$port"
  done

  if [[ "$found_config" != "true" ]]; then
    print_error "Bench Redis config files were not found in $config_dir"
    print_info "Re-run bench init or check that $HOME/$BENCH_NAME is a valid bench directory"
    exit 1
  fi
}

stop_started_bench_redis() {
  local mode="${1:-normal}"

  if [[ ${#BENCH_REDIS_STARTED_PORTS[@]} -eq 0 ]]; then
    return 0
  fi

  local redis_cli_bin
  redis_cli_bin="$(resolve_redis_cli_bin || true)"

  if [[ -z "$redis_cli_bin" || ! -x "$redis_cli_bin" ]]; then
    BENCH_REDIS_STARTED_PORTS=()
    return 0
  fi

  if [[ "$mode" != "quiet" ]]; then
    print_header "Stopping temporary bench Redis services"
  fi

  local port=""
  for port in "${BENCH_REDIS_STARTED_PORTS[@]}"; do
    if redis_ping_port "$redis_cli_bin" "$port"; then
      if "$redis_cli_bin" -h 127.0.0.1 -p "$port" shutdown nosave >/dev/null 2>&1; then
        [[ "$mode" == "quiet" ]] || print_ok "Stopped bench Redis on port $port"
      else
        [[ "$mode" == "quiet" ]] || print_warn "Could not stop bench Redis on port $port"
      fi
    else
      [[ "$mode" == "quiet" ]] || print_ok "Bench Redis on port $port is already stopped"
    fi
  done

  BENCH_REDIS_STARTED_PORTS=()
}

install_erpnext_if_requested() {
  CURRENT_STEP="Installing ERPNext"

  if [[ ! "$INSTALL_ERPNEXT" =~ ^[Yy]$ ]]; then
    return
  fi

  print_header "Installing ERPNext"

  if [[ ! -d "$HOME/$BENCH_NAME/apps/erpnext" ]]; then
    run_silent "Fetching ERPNext $FRAPPE_VERSION" \
      "$BENCH_BIN" get-app erpnext --branch "$FRAPPE_VERSION"
  else
    print_ok "ERPNext app already fetched"
  fi

  local erpnext_marker="$HOME/$BENCH_NAME/sites/$SITE_NAME/.frappe-installer-erpnext-installed"

  if "$BENCH_BIN" --site "$SITE_NAME" list-apps 2>/dev/null | $GREP_BIN -qx "erpnext"; then
    if [[ -f "$erpnext_marker" ]]; then
      print_ok "ERPNext already installed on $SITE_NAME"
    else
      print_warn "ERPNext is listed on $SITE_NAME, but installer completion marker is missing"
      print_info "Re-running install with --force to recover from possible partial installation"
      run_silent "Repairing ERPNext install on $SITE_NAME" \
        "$BENCH_BIN" --site "$SITE_NAME" install-app erpnext --force
      touch "$erpnext_marker"
    fi
  else
    run_silent "Installing ERPNext on $SITE_NAME" \
      "$BENCH_BIN" --site "$SITE_NAME" install-app erpnext
    touch "$erpnext_marker"
  fi
}

trim_line() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

is_supported_app_source() {
  case "$1" in
    http://*|https://*|ssh://*|git@*) return 0 ;;
    *) return 1 ;;
  esac
}

app_name_from_source() {
  local source="$1"
  source="${source%/}"

  local name="${source##*/}"

  name="${name%.git}"
  printf '%s' "$name"
}

load_custom_apps_file() {
  CUSTOM_APP_URLS=()
  CUSTOM_APP_BRANCHES=()
  CUSTOM_APP_NAMES=()

  if [[ ! -f "$CUSTOM_APPS_FILE" ]]; then
    return
  fi

  local line_no=0
  local raw_line=""
  local line=""

  while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
    line_no=$((line_no + 1))
    line="$(trim_line "$raw_line")"

    [[ -z "$line" || "$line" == \#* ]] && continue

    local app_url=""
    local app_branch=""
    local extra=""
    local old_ifs="$IFS"
    IFS=$' \t'
    read -r app_url app_branch extra <<< "$line"
    IFS="$old_ifs"

    if [[ -n "$extra" ]]; then
      print_error "Invalid apps.txt line $line_no: expected '<git_url> [branch]'"
      exit 1
    fi

    if ! is_supported_app_source "$app_url"; then
      print_error "Invalid apps.txt line $line_no: unsupported app source '$app_url'"
      print_info "Use https://, http://, ssh://, or git@ Git URLs"
      exit 1
    fi

    local app_name
    app_name="$(app_name_from_source "$app_url")"

    if [[ -z "$app_name" || ! "$app_name" =~ ^[a-zA-Z0-9._-]+$ ]]; then
      print_error "Invalid apps.txt line $line_no: could not infer app name from '$app_url'"
      print_info "The repository name should match the Frappe app name"
      exit 1
    fi

    CUSTOM_APP_URLS+=("$app_url")
    CUSTOM_APP_BRANCHES+=("$app_branch")
    CUSTOM_APP_NAMES+=("$app_name")
  done < "$CUSTOM_APPS_FILE"
}

install_custom_apps_if_present() {
  CURRENT_STEP="Installing custom apps"

  if [[ ! -f "$CUSTOM_APPS_FILE" ]]; then
    print_info "No apps.txt found - skipping custom apps"
    return
  fi

  load_custom_apps_file

  if [[ ${#CUSTOM_APP_URLS[@]} -eq 0 ]]; then
    print_info "No custom apps listed in $CUSTOM_APPS_FILE - skipping custom apps"
    return
  fi

  print_header "Installing custom apps"
  print_info "Using $CUSTOM_APPS_FILE"

  export YARN_REGISTRY="$YARN_REGISTRY_URL"
  export npm_config_registry="$YARN_REGISTRY_URL"
  export PATH="$VOLTA_HOME/bin:$HOME/.local/bin:$HOMEBREW_PREFIX/bin:$PATH"

  local index
  for ((index = 0; index < ${#CUSTOM_APP_URLS[@]}; index++)); do
    local app_url="${CUSTOM_APP_URLS[$index]}"
    local app_branch="${CUSTOM_APP_BRANCHES[$index]}"
    local app_name="${CUSTOM_APP_NAMES[$index]}"

    if [[ -d "$HOME/$BENCH_NAME/apps/$app_name" ]]; then
      print_ok "$app_name app already fetched"
    elif [[ -n "$app_branch" ]]; then
      run_silent "Fetching $app_name ($app_branch)" \
        "$BENCH_BIN" get-app "$app_url" --branch "$app_branch"
    else
      run_silent "Fetching $app_name" \
        "$BENCH_BIN" get-app "$app_url"
    fi

    if "$BENCH_BIN" --site "$SITE_NAME" list-apps 2>/dev/null | "$GREP_BIN" -qx "$app_name"; then
      print_ok "$app_name already installed on $SITE_NAME"
    else
      run_silent "Installing $app_name on $SITE_NAME" \
        "$BENCH_BIN" --site "$SITE_NAME" install-app "$app_name"
    fi
  done
}

build_assets() {
  CURRENT_STEP="Building assets"
  print_header "Building assets"
  run_silent "Building assets" "$BENCH_BIN" build
}

assert_installed_app() {
  local installed_apps="$1"
  local app_name="$2"

  if printf '%s\n' "$installed_apps" | "$AWK_BIN" '{print $1}' | "$GREP_BIN" -qx "$app_name"; then
    print_ok "$app_name is installed on $SITE_NAME"
    return
  fi

  print_error "$app_name is not installed on $SITE_NAME"
  exit 1
}

final_health_check() {
  CURRENT_STEP="Final health check"
  print_header "Final health check"

  if [[ ! -x "$BENCH_BIN" ]]; then
    print_error "Bench CLI not found at $BENCH_BIN"
    exit 1
  fi
  print_ok "Bench CLI is available"

  if [[ ! -d "$HOME/$BENCH_NAME" ]]; then
    print_error "Bench directory not found: $HOME/$BENCH_NAME"
    exit 1
  fi
  print_ok "Bench directory exists"

  if [[ ! -d "$HOME/$BENCH_NAME/sites/$SITE_NAME" ]]; then
    print_error "Site directory not found: $HOME/$BENCH_NAME/sites/$SITE_NAME"
    exit 1
  fi
  print_ok "Site directory exists"

  local current_site_file="$HOME/$BENCH_NAME/sites/currentsite.txt"
  local current_site=""
  if [[ -f "$current_site_file" ]]; then
    read -r current_site < "$current_site_file" || true
  fi

  if [[ "$current_site" != "$SITE_NAME" ]]; then
    print_error "Default site is not set to $SITE_NAME"
    print_info "Run manually: cd $HOME/$BENCH_NAME && $BENCH_BIN use $SITE_NAME"
    exit 1
  fi
  print_ok "Default site is $SITE_NAME"

  local installed_apps=""
  if ! installed_apps="$("$BENCH_BIN" --site "$SITE_NAME" list-apps 2>&1)"; then
    print_error "Could not list installed apps for $SITE_NAME"
    echo -e "\n${RED}--- Output ---${RESET}"
    printf '%s\n' "$installed_apps"
    echo -e "${RED}--- End ---${RESET}\n"
    exit 1
  fi
  print_ok "Site responds to bench commands"

  assert_installed_app "$installed_apps" "frappe"

  if [[ "$INSTALL_ERPNEXT" =~ ^[Yy]$ ]]; then
    assert_installed_app "$installed_apps" "erpnext"
  fi

  load_custom_apps_file
  local index
  for ((index = 0; index < ${#CUSTOM_APP_NAMES[@]}; index++)); do
    assert_installed_app "$installed_apps" "${CUSTOM_APP_NAMES[$index]}"
  done

  local redis_server_bin="$HOMEBREW_PREFIX/bin/redis-server"
  if [[ -x "$redis_server_bin" ]]; then
    print_ok "Redis binary is available"
  else
    print_warn "Redis binary was not found at $redis_server_bin"
  fi

  local wkhtmltopdf_bin
  wkhtmltopdf_bin="$(command -v wkhtmltopdf || true)"
  if [[ -n "$wkhtmltopdf_bin" ]]; then
    print_ok "wkhtmltopdf is available"
  elif [[ -x "$WKHTMLTOPDF_INSTALL_BIN" ]]; then
    print_warn "wkhtmltopdf is installed at $WKHTMLTOPDF_INSTALL_BIN but was not found in PATH"
    print_info "Add /usr/local/bin to PATH before generating PDFs"
  else
    print_warn "wkhtmltopdf was not found in PATH; PDF generation may need manual attention"
    print_info "Manual download: $WKHTMLTOPDF_DOWNLOADS_URL"
  fi

  print_ok "Final health check passed"
}

detect_shell_config() {
  local shell_name
  shell_name="$($BASENAME_BIN "$SHELL")"

  case "$shell_name" in
    zsh)  echo "$HOME/.zshrc" ;;
    bash) echo "$HOME/.bashrc" ;;
    *)    echo "$HOME/.profile" ;;
  esac
}

persist_shell_env() {
  CURRENT_STEP="Persisting environment settings"
  print_header "Persisting environment"

  SHELL_CONFIG="$(detect_shell_config)"
  MARKER="# frappe-installer managed - do not edit"

  touch "$SHELL_CONFIG"

  if ! $GREP_BIN -q "$MARKER" "$SHELL_CONFIG" 2>/dev/null; then
    cat >> "$SHELL_CONFIG" <<'__ENV__'

# frappe-installer managed - do not edit
export VOLTA_HOME="$HOME/.volta"
export PATH="$HOME/.local/bin:$VOLTA_HOME/bin:$PATH"
__ENV__
    print_ok "Updated $SHELL_CONFIG"
  else
    print_ok "$SHELL_CONFIG already contains installer environment block"
  fi
}

print_completion() {
  print_header "Installation complete"
  echo -e "  ${GREEN}${BOLD}Frappe $FRAPPE_VERSION is ready.${RESET}"
  echo ""
  echo -e "  ${BOLD}Start your bench:${RESET}"
  echo -e "    cd $HOME/$BENCH_NAME && $BENCH_BIN start"
  echo ""
  echo -e "  ${BOLD}Access your site:${RESET}"
  echo -e "    http://$SITE_NAME:8000"
  echo ""
  echo -e "  ${BOLD}Add $SITE_NAME to /etc/hosts if needed:${RESET}"
  echo -e "    echo '127.0.0.1  $SITE_NAME' | sudo tee -a /etc/hosts"
  echo ""
  echo -e "  ${BOLD}Bench location:${RESET}  $HOME/$BENCH_NAME"
  echo -e "  ${BOLD}Admin password:${RESET}  $ADMIN_PASSWORD"
  echo ""
  print_info "Restart your terminal or run: source $SHELL_CONFIG"
}

main() {
  SCRIPT_DIR="$(cd "$("$DIRNAME_BIN" "${BASH_SOURCE[0]}")" && "$PWD_BIN")"
  CUSTOM_APPS_FILE="$SCRIPT_DIR/apps.txt"

  print_header "Frappe Mac Installer v$SCRIPT_VERSION"

  CURRENT_STEP="Pre-flight checks"
  print_header "Pre-flight checks"

  check_macos
  check_not_root
  check_disk_space
  check_internet
  check_xcode_tools
  check_homebrew
  check_existing_mariadb

  print_preflight_summary

  CURRENT_STEP="Interactive prompts"
  prompt_for_inputs

  install_dependencies
  configure_services
  install_uv
  install_volta
  install_bench_cli
  initialize_bench
  ensure_bench_redis_services
  create_site
  install_erpnext_if_requested
  install_custom_apps_if_present
  build_assets
  final_health_check
  stop_started_bench_redis
  persist_shell_env
  print_completion
}

main "$@"
