#!/usr/bin/env bash

set -e

INSTALL_DIR="/opt/shm/backup"
REPO_URL="https://github.com/OldXrist/shm-backup.git"

echo "========================================="
echo "  SHM Backup Tool Installation Setup"
echo "========================================="

# 1. Ensure git, python3.12, and python3.12-venv are installed
echo "[1/5] Checking dependencies and cloning repository..."

if ! command -v git &> /dev/null || ! command -v python3.12 &> /dev/null || ! python3.12 -m venv --help &> /dev/null; then
    echo "[!] Installing missing system packages (git, python3.12, python3.12-venv)..."
    apt-get update && apt-get install -y git python3.12 python3.12-venv || yum install -y git python312
fi

if [ -d "$INSTALL_DIR/.git" ]; then
    git -C "$INSTALL_DIR" pull --quiet
else
    mkdir -p "$INSTALL_DIR"
    git clone --quiet "$REPO_URL" "$INSTALL_DIR"
fi

cd "$INSTALL_DIR"

# 2. Install Python dependencies using Python 3.12
echo "[2/5] Creating Python 3.12 virtual environment..."
python3.12 -m venv venv
"$INSTALL_DIR/venv/bin/pip" install --quiet --upgrade pip
"$INSTALL_DIR/venv/bin/pip" install --quiet -r requirements.txt

# 3. Interactive prompt for configuration
echo "[3/5] Configuring credentials..."

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
echo "Saved configuration to $INSTALL_DIR/.env"

# 4. Create systemd service for Bot Daemon
echo "[4/5] Creating systemd service for Bot daemon..."
cat <<EOF > /etc/systemd/system/shm-backup-bot.service
[Unit]
Description=SHM Backup Telegram Bot Daemon
After=network.target docker.service

[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/venv/bin/python3 $INSTALL_DIR/shm_backup.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now shm-backup-bot.service

# 5. Create global binary `shm-backup`
echo "[5/5] Creating global 'shm-backup' executable command..."
cat <<EOF > /usr/local/bin/shm-backup
#!/usr/bin/env bash
exec $INSTALL_DIR/venv/bin/python3 $INSTALL_DIR/shm_backup.py "\$@"
EOF

chmod +x /usr/local/bin/shm-backup

# 6. Configure Cron job using global binary
CRON_CMD="0 3 * * * /usr/local/bin/shm-backup > /dev/null 2>&1"

(crontab -l 2>/dev/null | grep -F "shm-backup") || (
    (crontab -l 2>/dev/null; echo "$CRON_CMD") | crontab -
)

echo "========================================="
echo "✅ Installation complete!"
echo "Bot Daemon Status: systemctl status shm-backup-bot"
echo "Run CLI Backup:    shm-backup"
echo "========================================="
