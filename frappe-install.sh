#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_VERSION="1.0.0"
MIN_MACOS_MAJOR=13
HOMEBREW_PREFIX_ARM="/opt/homebrew"
HOMEBREW_PREFIX_INTEL="/usr/local"
UV_INSTALL_URL="https://astral.sh/uv/install.sh"
VOLTA_INSTALL_URL="https://get.volta.sh"
MARIADB_RESET_GUIDE_URL="https://gist.github.com/petehouston/13bfc8cba1991cc6741fbe28cfa5491c"

FRAPPE_15_PYTHON="3.11"
FRAPPE_15_NODE="18"
FRAPPE_16_PYTHON="3.12"
FRAPPE_16_NODE="20"

MARIADB_VERSION="10.11"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

print_header()  { echo -e "\n${BOLD}${BLUE}══════════════════════════════${RESET}"; echo -e "${BOLD}${BLUE}  $1${RESET}"; echo -e "${BOLD}${BLUE}══════════════════════════════${RESET}\n"; }
print_step()    { echo -e "${CYAN}  ▸ $1${RESET}"; }
print_ok()      { echo -e "${GREEN}  ✓ $1${RESET}"; }
print_warn()    { echo -e "${YELLOW}  ⚠ $1${RESET}"; }
print_error()   { echo -e "${RED}  ✗ $1${RESET}"; }
print_info()    { echo -e "    ${BLUE}$1${RESET}"; }

spinner() {
  local pid=$1 msg=$2
  local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  local i=0
  while kill -0 "$pid" 2>/dev/null; do
    printf "\r  ${CYAN}%s${RESET}  %s" "${frames[$((i % 10))]}" "$msg"
    sleep 0.08
    i=$((i + 1))
  done
  printf "\r"
}

run_silent() {
  local msg=$1
  shift

  local log
  log=$(mktemp)

  "$@" >"$log" 2>&1 &
  local pid=$!

  spinner "$pid" "$msg"

  local exit_code=0
  wait "$pid" || exit_code=$?

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
  [[ $exit_code -ne 0 ]] || return
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

  if "$BREW_BIN" list "mariadb@$MARIADB_VERSION" >/dev/null 2>&1; then
    MARIADB_INSTALLED="true"
    print_ok "MariaDB $MARIADB_VERSION already installed"
  else
    print_info "MariaDB $MARIADB_VERSION not installed yet (will install)"
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

  if [[ -x "$HOMEBREW_PREFIX/opt/mariadb@$MARIADB_VERSION/bin/mysql" ]]; then
    mysql_candidate="$HOMEBREW_PREFIX/opt/mariadb@$MARIADB_VERSION/bin/mysql"
  elif command -v mysql >/dev/null 2>&1; then
    mysql_candidate="$(command -v mysql)"
  fi

  if [[ -n "$mysql_candidate" ]]; then
    if "$mysql_candidate" -u root -e "SELECT 1" >/dev/null 2>&1; then
      MARIADB_ROOT_PASSWORDLESS="true"
      print_ok "MariaDB root is accessible"
    elif [[ "$MANAGE_MARIADB" == "true" ]] && "$BREW_BIN" list "mariadb@$MARIADB_VERSION" >/dev/null 2>&1; then
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
  echo "  [1] Frappe v15  (Python 3.11, Node 18, stable)"
  echo "  [2] Frappe v16  (Python 3.12, Node 20, latest)"
  echo ""
  read -rp "  Enter choice [1/2]: " version_choice

  case $version_choice in
    1)
      FRAPPE_VERSION="version-15"
      PYTHON_VERSION="$FRAPPE_15_PYTHON"
      NODE_VERSION="$FRAPPE_15_NODE"
      ;;
    2)
      FRAPPE_VERSION="version-16"
      PYTHON_VERSION="$FRAPPE_16_PYTHON"
      NODE_VERSION="$FRAPPE_16_NODE"
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

  if "$BREW_BIN" list --cask wkhtmltopdf >/dev/null 2>&1; then
    print_ok "wkhtmltopdf already installed"
  else
    run_silent "Installing wkhtmltopdf" "$BREW_BIN" install --cask wkhtmltopdf
  fi

  if [[ -d "$HOMEBREW_PREFIX/opt/mariadb@$MARIADB_VERSION/bin" ]]; then
    export PATH="$HOMEBREW_PREFIX/opt/mariadb@$MARIADB_VERSION/bin:$PATH"
  fi
}

configure_services() {
  CURRENT_STEP="Configuring MariaDB and Redis"
  print_header "Configuring services"

  if [[ "$MANAGE_MARIADB" != "true" ]]; then
    print_warn "Safe mode enabled - skipping MariaDB config, restart, and root auth changes"
    run_silent "Starting Redis" "$BREW_BIN" services start redis
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
  run_silent "Starting Redis" "$BREW_BIN" services start redis
}

install_uv() {
  CURRENT_STEP="Installing uv"
  print_header "Installing uv"

  UV_BIN="$HOME/.local/bin/uv"

  if [[ ! -f "$UV_BIN" ]]; then
    run_silent "Installing uv (Python manager)" \
      "$BASH_BIN" -c "$CURL_BIN -LsSf $UV_INSTALL_URL | /bin/sh"
  else
    run_silent "Updating uv" "$UV_BIN" self update
  fi

  export PATH="$HOME/.local/bin:$PATH"
}

install_volta() {
  CURRENT_STEP="Installing volta"
  print_header "Installing volta"

  VOLTA_HOME="$HOME/.volta"
  VOLTA_BIN="$VOLTA_HOME/bin/volta"

  if [[ ! -f "$VOLTA_BIN" ]]; then
    run_silent "Installing volta (Node manager)" \
      "$BASH_BIN" -c "$CURL_BIN -fsSL $VOLTA_INSTALL_URL | /bin/bash -s -- --skip-setup"
  fi

  export VOLTA_HOME="$HOME/.volta"
  export PATH="$VOLTA_HOME/bin:$PATH"

  run_silent "Installing Node $NODE_VERSION" "$VOLTA_BIN" install "node@$NODE_VERSION"
  run_silent "Installing Yarn" "$VOLTA_BIN" install yarn
}

install_bench_cli() {
  CURRENT_STEP="Installing frappe-bench CLI"
  print_header "Installing bench CLI"

  BENCH_VENV="$HOME/.bench-cli"
  run_silent "Creating bench CLI environment" \
    "$UV_BIN" venv "$BENCH_VENV" --python "$PYTHON_VERSION"

  run_silent "Installing frappe-bench" \
    "$UV_BIN" pip install --python "$BENCH_VENV/bin/python" frappe-bench

  BENCH_BIN="$BENCH_VENV/bin/bench"
}

initialize_bench() {
  CURRENT_STEP="Initializing bench"
  print_header "Initializing bench"

  if [[ ! -d "$HOME/$BENCH_NAME" ]] || [[ "$SKIP_INIT" != "y" ]]; then
    export PATH="$VOLTA_HOME/bin:$HOME/.local/bin:$HOMEBREW_PREFIX/bin:$PATH"
    run_silent "Initializing bench (this takes a few minutes)" \
      "$BENCH_BIN" init "$HOME/$BENCH_NAME" \
        --frappe-branch "$FRAPPE_VERSION" \
        --python "$BENCH_VENV/bin/python" \
        --skip-assets
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

  if "$BENCH_BIN" --site "$SITE_NAME" list-apps 2>/dev/null | $GREP_BIN -qx "erpnext"; then
    print_ok "ERPNext already installed on $SITE_NAME"
  else
    run_silent "Installing ERPNext on $SITE_NAME" \
      "$BENCH_BIN" --site "$SITE_NAME" install-app erpnext
  fi
}

build_assets() {
  CURRENT_STEP="Building assets"
  print_header "Building assets"
  run_silent "Building assets" "$BENCH_BIN" build
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
  create_site
  install_erpnext_if_requested
  build_assets
  persist_shell_env
  print_completion
}

main "$@"
