#!/usr/bin/env bash

set -e

INSTALL_DIR="/opt/shm-backup"

echo "========================================="
echo "  SHM Backup Tool Installation Setup"
echo "========================================="

# 1. Create target directory if needed and copy files
if [ "$(pwd)" != "$INSTALL_DIR" ]; then
    echo "[1/4] Copying files to $INSTALL_DIR..."
    mkdir -p "$INSTALL_DIR"
    cp -r ./* "$INSTALL_DIR/"
    cd "$INSTALL_DIR"
fi

# 2. Install dependencies into virtual environment using requirements.txt
echo "[2/4] Installing Python dependencies..."
python3 -m venv venv
"$INSTALL_DIR/venv/bin/pip" install --quiet --upgrade pip
"$INSTALL_DIR/venv/bin/pip" install --quiet -r requirements.txt

# 3. Interactive prompt for environment setup
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
echo "Saved configuration to $INSTALL_DIR/.env"

# 4. Create systemd service for Bot Daemon
echo "[4/4] Creating systemd service for Bot daemon..."
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

# 5. Configure Cron job for automated daily backup
CRON_CMD="0 3 * * * $INSTALL_DIR/venv/bin/python3 $INSTALL_DIR/shm_backup.py --cli > /dev/null 2>&1"

(crontab -l 2>/dev/null | grep -F "$INSTALL_DIR/shm_backup.py") || (
    (crontab -l 2>/dev/null; echo "$CRON_CMD") | crontab -
)

echo "========================================="
echo "✅ Installation complete!"
echo "Bot Daemon Status: systemctl status shm-backup-bot"
echo "Manual Backup:     $INSTALL_DIR/venv/bin/python3 $INSTALL_DIR/shm_backup.py --cli"
echo "========================================="
