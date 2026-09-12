#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PAGES_DIR="${HOME}/.nomadnetwork/storage/pages"
DATA_DIR="${PAGES_DIR}/.darktsunami_keep"
OLD_DATA_DIR="${PAGES_DIR}/.ashfall_keep"
APP_DIR="${HOME}/.local/share/darktsunami-keep"
BIN_DIR="${HOME}/.local/bin"
APPLICATIONS_DIR="${HOME}/.local/share/applications"
AUTOSTART_DIR="${HOME}/.config/autostart"
SYSTEMD_DIR="${HOME}/.config/systemd/user"
AUTOSTART=1
BACKUP_TIMER=1
LAUNCH=0

for arg in "$@"; do
  case "$arg" in
    --no-autostart) AUTOSTART=0 ;;
    --no-backup-timer) BACKUP_TIMER=0 ;;
    --launch) LAUNCH=1 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

mkdir -p "$PAGES_DIR" "$DATA_DIR" "$APP_DIR" "$BIN_DIR" "$APPLICATIONS_DIR"
chmod 700 "$DATA_DIR"

if [[ ! -f "$DATA_DIR/game.sqlite3" && -f "$OLD_DATA_DIR/game.sqlite3" ]]; then
  python3 - "$OLD_DATA_DIR/game.sqlite3" "$DATA_DIR/game.sqlite3" <<'PY'
import sqlite3
import sys
src = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True, timeout=10)
dst = sqlite3.connect(sys.argv[2], timeout=10)
try:
    src.backup(dst)
finally:
    dst.close()
    src.close()
PY
  echo "Migrated existing Ashfall save database to DarkTsunami Keep."
fi

install -m 755 "$ROOT/index.mu" "$PAGES_DIR/index.mu"
install -m 755 "$ROOT/dashboard.py" "$APP_DIR/dashboard.py"
install -m 755 "$ROOT/backup.py" "$APP_DIR/backup.py"
install -m 644 "$ROOT/README.md" "$APP_DIR/README.md"

cat > "$BIN_DIR/darktsunami-dashboard" <<EOF
#!/usr/bin/env bash
exec python3 "$APP_DIR/dashboard.py" "\$@"
EOF
chmod 755 "$BIN_DIR/darktsunami-dashboard"

cat > "$BIN_DIR/darktsunami-backup" <<EOF
#!/usr/bin/env bash
exec python3 "$APP_DIR/backup.py" "\$@"
EOF
chmod 755 "$BIN_DIR/darktsunami-backup"

cat > "$APPLICATIONS_DIR/darktsunami-keep-dashboard.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=DarkTsunami Keep Dashboard
Comment=Local DarkTsunami Keep server statistics
Exec=$BIN_DIR/darktsunami-dashboard
Terminal=false
Categories=Game;Utility;
EOF

if [[ "$AUTOSTART" -eq 1 ]]; then
  mkdir -p "$AUTOSTART_DIR"
  cp "$APPLICATIONS_DIR/darktsunami-keep-dashboard.desktop" "$AUTOSTART_DIR/darktsunami-keep-dashboard.desktop"
else
  rm -f "$AUTOSTART_DIR/darktsunami-keep-dashboard.desktop"
fi

if [[ "$BACKUP_TIMER" -eq 1 ]] && command -v systemctl >/dev/null 2>&1; then
  mkdir -p "$SYSTEMD_DIR"
  cat > "$SYSTEMD_DIR/darktsunami-keep-backup.service" <<EOF
[Unit]
Description=Back up DarkTsunami Keep database

[Service]
Type=oneshot
ExecStart=$BIN_DIR/darktsunami-backup
EOF
  cat > "$SYSTEMD_DIR/darktsunami-keep-backup.timer" <<'EOF'
[Unit]
Description=Daily DarkTsunami Keep database backup

[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=15m

[Install]
WantedBy=timers.target
EOF
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  systemctl --user enable --now darktsunami-keep-backup.timer >/dev/null 2>&1 || true
fi

if ! python3 -c 'import tkinter' >/dev/null 2>&1; then
  echo "WARNING: Python Tk is not installed. Install your distribution's Tkinter package before launching the dashboard."
fi

if [[ "$LAUNCH" -eq 1 ]]; then
  "$BIN_DIR/darktsunami-dashboard" >/dev/null 2>&1 &
fi

echo "DarkTsunami Keep installed."
echo "NomadNet page: $PAGES_DIR/index.mu"
echo "Game address: :/page/index.mu"
echo "Database: $DATA_DIR/game.sqlite3"
echo "Dashboard: $BIN_DIR/darktsunami-dashboard"
echo "Backup: $BIN_DIR/darktsunami-backup"
echo "Dashboard autostart: $AUTOSTART"
echo "Players must use Identify When Connecting; LXMF addresses remain the permanent player IDs."
