#!/usr/bin/env bash
set -euo pipefail

PAGES_DIR="${HOME}/.nomadnetwork/storage/pages"
APP_DIR="${HOME}/.local/share/darktsunami-keep"
BIN_DIR="${HOME}/.local/bin"
APPLICATIONS_DIR="${HOME}/.local/share/applications"
AUTOSTART_DIR="${HOME}/.config/autostart"
SYSTEMD_DIR="${HOME}/.config/systemd/user"

systemctl --user disable --now darktsunami-keep-backup.timer >/dev/null 2>&1 || true
rm -f "$SYSTEMD_DIR/darktsunami-keep-backup.timer" "$SYSTEMD_DIR/darktsunami-keep-backup.service"
rm -f "$BIN_DIR/darktsunami-dashboard" "$BIN_DIR/darktsunami-backup"
rm -f "$APPLICATIONS_DIR/darktsunami-keep-dashboard.desktop" "$AUTOSTART_DIR/darktsunami-keep-dashboard.desktop"
rm -rf "$APP_DIR"
rm -f "$PAGES_DIR/index.mu"

echo "DarkTsunami Keep application files removed."
echo "Saved game data was preserved at: $PAGES_DIR/.darktsunami_keep"
