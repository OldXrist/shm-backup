#!/usr/bin/env bash

set -e

INSTALL_DIR="/opt/shm/backup"
REPO_URL="https://github.com/OldXrist/shm-backup.git"

echo "========================================="
echo "  SHM Backup Tool Setup (Pure Bash)"
echo "========================================="

# 1. Install system dependencies
echo "[1/4] Installing dependencies..."
apt-get update -qq && apt-get install -y -qq git curl docker-compose-plugin 2>/dev/null || true

# 2. Clone/Update repository
echo "[2/4] Deploying files to $INSTALL_DIR..."
if [ -d "$INSTALL_DIR/.git" ]; then
    git -C "$INSTALL_DIR" pull --quiet
else
    mkdir -p "$INSTALL_DIR"
    git clone --quiet "$REPO_URL" "$INSTALL_DIR"
fi

# 3. Interactive prompt for configuration
if [ ! -f "$INSTALL_DIR/.env" ]; then
    echo "[3/4] Configuring credentials..."
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

# 4. Global shortcut and cron setup
echo "[4/4] Creating executable shortcut and cron job..."
cat <<EOF > /usr/local/bin/shm-backup
#!/usr/bin/env bash
exec $INSTALL_DIR/shm-backup.sh "\$@"
EOF

chmod +x /usr/local/bin/shm-backup
chmod +x "$INSTALL_DIR/shm-backup.sh"

CRON_CMD="0 3 * * * /usr/local/bin/shm-backup --run > /dev/null 2>&1"
(crontab -l 2>/dev/null | grep -F "shm-backup") || (
    (crontab -l 2>/dev/null; echo "$CRON_CMD") | crontab -
)

echo "========================================="
echo "✅ Installation complete!"
echo "Run CLI Backup: shm-backup"
echo "========================================="
