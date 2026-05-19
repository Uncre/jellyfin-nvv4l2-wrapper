#!/bin/bash
# install.sh - Installer for jellyfin-nvv4l2-wrapper
# License: MIT

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="/usr/local/bin"
FFMPEG_WRAPPER="jellyfin-nvv4l2-wrapper"
FFPROBE_WRAPPER="ffprobe-wrapper"
JELLYFIN_DEFAULT="/etc/default/jellyfin"

# --- Color output helpers ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# --- Root check ---
if [ "$EUID" -ne 0 ]; then
    error "Please run as root: sudo bash install.sh"
fi

# --- Prerequisite checks ---
info "Checking prerequisites..."

if ! command -v ffmpeg &> /dev/null; then
    echo ""
    error "ffmpeg not found.
  Please install FFmpeg with nvv4l2 support for Tegra:
    https://github.com/theofficialgman/FFmpeg/tree/6.1.1-nvv4l2

  Instructions:
    Follow the build instructions in the repository linked above."
fi

if ! ffmpeg -encoders 2>/dev/null | grep -q "h264_nvv4l2"; then
    error "h264_nvv4l2 encoder not found.
  Your FFmpeg was not built with nvv4l2 support.
  Please install FFmpeg with nvv4l2 support:
    https://github.com/theofficialgman/FFmpeg/tree/6.1.1-nvv4l2"
fi

info "FFmpeg with nvv4l2 support detected."

if ! command -v ffprobe &> /dev/null; then
    error "ffprobe not found."
fi

# --- Install FFmpeg wrapper ---
info "Installing ${FFMPEG_WRAPPER} to ${INSTALL_DIR}/..."

if [ -f "${INSTALL_DIR}/${FFMPEG_WRAPPER}" ]; then
    BACKUP="${INSTALL_DIR}/${FFMPEG_WRAPPER}.bak.$(date +%Y%m%d%H%M%S)"
    warn "Existing wrapper found. Backing up to ${BACKUP}"
    cp "${INSTALL_DIR}/${FFMPEG_WRAPPER}" "${BACKUP}"
fi

cp "${SCRIPT_DIR}/${FFMPEG_WRAPPER}" "${INSTALL_DIR}/${FFMPEG_WRAPPER}"
chmod +x "${INSTALL_DIR}/${FFMPEG_WRAPPER}"
info "Installed ${FFMPEG_WRAPPER}."

# --- Install ffprobe wrapper ---
info "Installing ${FFPROBE_WRAPPER} to ${INSTALL_DIR}/..."

CURRENT_FFPROBE="$(readlink -f "${INSTALL_DIR}/ffprobe" 2>/dev/null || echo "")"
if [ -L "${INSTALL_DIR}/ffprobe" ]; then
    BACKUP_LINK="${INSTALL_DIR}/ffprobe.orig"
    if [ ! -e "${BACKUP_LINK}" ]; then
        info "Saving original ffprobe symlink target: ${CURRENT_FFPROBE}"
        echo "${CURRENT_FFPROBE}" > "${BACKUP_LINK}"
    fi
fi

cp "${SCRIPT_DIR}/${FFPROBE_WRAPPER}" "${INSTALL_DIR}/${FFPROBE_WRAPPER}"
chmod +x "${INSTALL_DIR}/${FFPROBE_WRAPPER}"
ln -sf "${INSTALL_DIR}/${FFPROBE_WRAPPER}" "${INSTALL_DIR}/ffprobe"
info "Installed ${FFPROBE_WRAPPER} and linked ffprobe."

# --- Configure Jellyfin FFmpeg path (apt version) ---
info "Configuring Jellyfin FFmpeg path..."

if [ -f "${JELLYFIN_DEFAULT}" ]; then
    # Backup
    if [ ! -f "${JELLYFIN_DEFAULT}.bak" ]; then
        cp "${JELLYFIN_DEFAULT}" "${JELLYFIN_DEFAULT}.bak"
        info "Backed up ${JELLYFIN_DEFAULT} to ${JELLYFIN_DEFAULT}.bak"
    fi

    # Check if JELLYFIN_FFMPEG_OPT exists
    if grep -q "^JELLYFIN_FFMPEG_OPT" "${JELLYFIN_DEFAULT}"; then
        # Replace existing line
        sed -i "s|^JELLYFIN_FFMPEG_OPT=.*|JELLYFIN_FFMPEG_OPT=\"--ffmpeg ${INSTALL_DIR}/${FFMPEG_WRAPPER}\"|" "${JELLYFIN_DEFAULT}"
        info "Updated JELLYFIN_FFMPEG_OPT in ${JELLYFIN_DEFAULT}"
    elif grep -q "^#.*JELLYFIN_FFMPEG_OPT" "${JELLYFIN_DEFAULT}"; then
        # Uncomment and set
        sed -i "s|^#.*JELLYFIN_FFMPEG_OPT.*|JELLYFIN_FFMPEG_OPT=\"--ffmpeg ${INSTALL_DIR}/${FFMPEG_WRAPPER}\"|" "${JELLYFIN_DEFAULT}"
        info "Uncommented and set JELLYFIN_FFMPEG_OPT in ${JELLYFIN_DEFAULT}"
    else
        # Add new line
        echo "" >> "${JELLYFIN_DEFAULT}"
        echo "JELLYFIN_FFMPEG_OPT=\"--ffmpeg ${INSTALL_DIR}/${FFMPEG_WRAPPER}\"" >> "${JELLYFIN_DEFAULT}"
        info "Added JELLYFIN_FFMPEG_OPT to ${JELLYFIN_DEFAULT}"
    fi
else
    warn "${JELLYFIN_DEFAULT} not found."
    warn "This installer supports the apt version of Jellyfin only."
    warn "For Docker/Snap/Flatpak, please configure the FFmpeg path manually."
fi

# --- Summary ---
echo ""
info "Installation complete!"
echo ""
echo "Restart Jellyfin to apply changes:"
echo "  sudo systemctl restart jellyfin"
echo ""
echo "Log file: /tmp/jellyfin-ffmpeg-wrapper.log"
echo ""
echo "Note: This installer configures the apt version of Jellyfin."
echo "      Docker, Snap, and Flatpak versions are not supported."
