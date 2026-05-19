#!/bin/bash
# uninstall.sh - Uninstaller for jellyfin-nvv4l2-wrapper
# License: MIT

set -e

INSTALL_DIR="/usr/local/bin"
FFMPEG_WRAPPER="jellyfin-nvv4l2-wrapper"
FFPROBE_WRAPPER="ffprobe-wrapper"
JELLYFIN_DEFAULT="/etc/default/jellyfin"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

if [ "$EUID" -ne 0 ]; then
    error "Please run as root: sudo bash uninstall.sh"
fi

# --- Remove FFmpeg wrapper ---
if [ -f "${INSTALL_DIR}/${FFMPEG_WRAPPER}" ]; then
    rm "${INSTALL_DIR}/${FFMPEG_WRAPPER}"
    info "Removed ${FFMPEG_WRAPPER}."
else
    warn "${FFMPEG_WRAPPER} not found, skipping."
fi

# --- Restore ffprobe ---
ORIG_FILE="${INSTALL_DIR}/ffprobe.orig"
if [ -f "${ORIG_FILE}" ]; then
    ORIG_TARGET="$(cat "${ORIG_FILE}")"
    ln -sf "${ORIG_TARGET}" "${INSTALL_DIR}/ffprobe"
    rm "${ORIG_FILE}"
    info "Restored ffprobe symlink to ${ORIG_TARGET}."
else
    ln -sf /usr/bin/ffprobe "${INSTALL_DIR}/ffprobe"
    info "Restored ffprobe symlink to /usr/bin/ffprobe."
fi

# --- Remove ffprobe wrapper ---
if [ -f "${INSTALL_DIR}/${FFPROBE_WRAPPER}" ]; then
    rm "${INSTALL_DIR}/${FFPROBE_WRAPPER}"
    info "Removed ${FFPROBE_WRAPPER}."
fi

# --- Remove backups ---
for f in "${INSTALL_DIR}/${FFMPEG_WRAPPER}.bak."*; do
    if [ -f "$f" ]; then
        rm "$f"
        info "Removed backup: $f"
    fi
done

# --- Restore Jellyfin FFmpeg path ---
if [ -f "${JELLYFIN_DEFAULT}.bak" ]; then
    cp "${JELLYFIN_DEFAULT}.bak" "${JELLYFIN_DEFAULT}"
    rm "${JELLYFIN_DEFAULT}.bak"
    info "Restored ${JELLYFIN_DEFAULT} from backup."
elif [ -f "${JELLYFIN_DEFAULT}" ]; then
    if grep -q "^JELLYFIN_FFMPEG_OPT.*${FFMPEG_WRAPPER}" "${JELLYFIN_DEFAULT}"; then
        sed -i "s|^JELLYFIN_FFMPEG_OPT=.*|JELLYFIN_FFMPEG_OPT=\"--ffmpeg /usr/lib/jellyfin-ffmpeg/ffmpeg\"|" "${JELLYFIN_DEFAULT}"
        info "Reset JELLYFIN_FFMPEG_OPT to default in ${JELLYFIN_DEFAULT}"
    fi
fi

echo ""
info "Uninstallation complete!"
echo ""
echo "Restart Jellyfin to apply changes:"
echo "  sudo systemctl restart jellyfin"
