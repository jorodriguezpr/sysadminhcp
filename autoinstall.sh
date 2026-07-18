#!/bin/bash
# ============================================================================
# SysAdminHCP - One-line installer
# ============================================================================
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/jorodriguezpr/sysadminhcp/main/autoinstall.sh | sudo bash
#
# Or download first and run locally:
#   curl -fsSLo autoinstall.sh https://raw.githubusercontent.com/jorodriguezpr/sysadminhcp/main/autoinstall.sh
#   sudo bash autoinstall.sh
#
# This script does NOT install the application itself - it detects your OS,
# installs git/git-lfs if needed, clones the SysAdminHCP repository (which
# ships a pre-built, license-gated binary - no application source code), and
# hands off to the correct install-*.sh script for your distro.
#
# By running this script you accept the End User License Agreement (EULA)
# distributed as LICENSE.md in the repository this script clones.
# ============================================================================

set -euo pipefail

REPO_URL="${SYSADMINHCP_REPO_URL:-https://github.com/jorodriguezpr/sysadminhcp.git}"
CLONE_DIR="${SYSADMINHCP_CLONE_DIR:-/usr/local/src/sysadminhcp}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

info "SysAdminHCP One-Line Installer"
info "=============================="
echo ""
info "SysAdminHCP is proprietary software. By continuing, you accept the"
info "End User License Agreement (see LICENSE.md in the cloned repository)."
echo ""

# ─── Pre-flight: root check ─────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
  error "This script must be run as root (use sudo)"
fi

# ─── Detect OS ───────────────────────────────────────────────────────────────
if [[ ! -f /etc/os-release ]]; then
  error "Cannot detect OS. /etc/os-release not found"
fi
# shellcheck disable=SC1091
source /etc/os-release
info "Detected OS: $NAME $VERSION_ID"

INSTALLER=""
PKG_MANAGER=""

case "$ID" in
  almalinux|rocky|centos|rhel)
    PKG_MANAGER="dnf"
    MAJOR_VER="${VERSION_ID%%.*}"
    case "$MAJOR_VER" in
      8)  INSTALLER="install-almalinux8.sh" ;;
      9)  INSTALLER="install-almalinux9.sh" ;;
      10) INSTALLER="install-almalinux10.sh" ;;
      *)
        error "Unsupported EL major version: $MAJOR_VER. SysAdminHCP supports EL 8, 9, and 10 (AlmaLinux, Rocky, RHEL, CentOS Stream)."
        ;;
    esac
    ;;
  ubuntu|debian)
    PKG_MANAGER="apt"
    UBUNTU_MAJOR="${VERSION_ID%%.*}"
    if [[ "$ID" == "ubuntu" && "$UBUNTU_MAJOR" -lt 22 ]]; then
      error "Ubuntu $VERSION_ID is too old. SysAdminHCP requires Ubuntu 22.04 or newer."
    fi
    INSTALLER="install-ubuntu22.sh"
    ;;
  *)
    error "Unsupported OS: $ID. SysAdminHCP supports AlmaLinux/Rocky/RHEL 8-10 and Ubuntu 22.04+/Debian."
    ;;
esac

info "Selected installer: deploy/$INSTALLER"

# ─── Install git + git-lfs if missing ───────────────────────────────────────
# git-lfs is required: the compiled binary in this repo is stored via Git LFS.
# Without it, cloning only fetches a small pointer file, not the real binary.
if ! command -v git &>/dev/null || ! command -v git-lfs &>/dev/null; then
  info "Installing git and git-lfs..."
  if [[ "$PKG_MANAGER" == "dnf" ]]; then
    dnf install -y git git-lfs 2>&1 | tail -5 \
      || error "Failed to install git/git-lfs. On some EL releases git-lfs needs EPEL: dnf install -y epel-release && dnf install -y git-lfs"
  else
    apt-get update -y 2>&1 | tail -3
    apt-get install -y git git-lfs 2>&1 | tail -5 \
      || error "Failed to install git/git-lfs."
  fi
fi
git lfs install --skip-repo &>/dev/null || true

# ─── Clone or update the repository ─────────────────────────────────────────
if [[ -d "$CLONE_DIR/.git" ]]; then
  info "Existing checkout found at $CLONE_DIR — updating..."
  git -C "$CLONE_DIR" fetch --all --tags 2>&1 | tail -5
  git -C "$CLONE_DIR" reset --hard origin/HEAD 2>&1 | tail -5
  git -C "$CLONE_DIR" lfs pull 2>&1 | tail -5
else
  info "Cloning $REPO_URL to $CLONE_DIR..."
  rm -rf "$CLONE_DIR"
  mkdir -p "$(dirname "$CLONE_DIR")"
  git clone "$REPO_URL" "$CLONE_DIR" 2>&1 | tail -10 \
    || error "Clone failed. If this is a private repository, clone it manually with credentials first, then re-run this script (it will detect the existing checkout and update it instead)."
fi

# ─── Sanity check: the binary must be a real ELF, not an LFS pointer file ──
BINARY_PATH="$CLONE_DIR/sysadminhcp"
if [[ ! -f "$BINARY_PATH" ]]; then
  error "sysadminhcp binary not found in the cloned repository."
fi
if ! head -c 4 "$BINARY_PATH" | grep -q $'\x7fELF'; then
  error "sysadminhcp is not a valid binary (looks like an unresolved Git LFS pointer file). Run 'git lfs pull' inside $CLONE_DIR and re-run this script."
fi
info "Binary verified OK"

# ─── Hand off to the OS-specific installer ──────────────────────────────────
INSTALLER_PATH="$CLONE_DIR/deploy/$INSTALLER"
if [[ ! -f "$INSTALLER_PATH" ]]; then
  error "Installer not found at $INSTALLER_PATH"
fi

info "Running deploy/$INSTALLER..."
echo ""
chmod +x "$INSTALLER_PATH"
exec bash "$INSTALLER_PATH"
