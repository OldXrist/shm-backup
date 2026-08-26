#!/usr/bin/env bash

set -e

INSTALL_DIR="/opt/shm/shm-backup"
RAW_SCRIPT_URL="https://raw.githubusercontent.com/OldXrist/shm-backup/main/shm-backup.sh"

echo "========================================="
echo "  SHM Backup Tool Setup (Pure Bash)"
echo "========================================="

# 1. Install system dependencies
echo "[1/4] Checking system dependencies..."
apt-get update -qq && apt-get install -y -qq curl docker-compose-plugin 2>/dev/null || true

# 2. Setup directory and download primary script only
echo "[2/4] Setting up directory at $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR/backups"

echo "[3/4] Fetching latest shm-backup.sh..."
curl -sSL "$RAW_SCRIPT_URL" -o "$INSTALL_DIR/shm-backup.sh"
chmod +x "$INSTALL_DIR/shm-backup.sh"

# 3. Interactive configuration
if [ ! -f "$INSTALL_DIR/.env" ]; then
    echo "[4/4] Configuring credentials..."
    read -rp "Enter Telegram Bot Token: " bot_token
    read -rp "Enter Telegram Chat ID: " chat_id
    read -rp "Enter SHM project directory [/opt/shm]: " shm_dir
    shm_dir=${shm_dir:-/opt/shm}

    cat <<EOF > "$INSTALL_DIR/.env"
TELEGRAM_BOT_TOKEN=$bot_token
TELEGRAM_CHAT_ID=$chat_id
SHM_DIR=$shm_dir
EOF
    chmod 600 "$INSTALL_DIR/.env"
fi

# 4. Global shortcut setup
cat <<EOF > /usr/local/bin/shm-backup
#!/usr/bin/env bash
exec $INSTALL_DIR/shm-backup.sh "\$@"
EOF

chmod +x /usr/local/bin/shm-backup

# Default Cron: Daily at 03:00 AM
CRON_CMD="0 0 * * * /usr/local/bin/shm-backup --run > /dev/null 2>&1"
(crontab -l 2>/dev/null | grep -F "shm-backup") || (
    (crontab -l 2>/dev/null; echo "$CRON_CMD") | crontab -
)

echo "========================================="
echo "✅ Installation complete!"
echo "Run CLI Backup: shm-backup"
echo "========================================="
