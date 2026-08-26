#!/usr/bin/env bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
VERSION="1.0.0"

# Load environment variables
if [ -f "$ENV_FILE" ]; then
    set -a
    source "$ENV_FILE"
    set +a
fi

SHM_DIR="${SHM_DIR:-/opt/shm}"

clear_screen() {
    clear 2>/dev/null || true
}

run_manual_backup() {
    echo -e "\n\033[33m⏳ Executing manual backup...\033[0m"
    "$SCRIPT_DIR/venv/bin/python3" "$SCRIPT_DIR/shm_backup.py" --cli
    echo -e "\nPress Enter to continue..."
    read -r
}

# Non-interactive CLI flag support (used by cron or automated triggers)
if [ "$1" == "--run" ]; then
    "$SCRIPT_DIR/venv/bin/python3" "$SCRIPT_DIR/shm_backup.py" --cli
    exit 0
fi

show_menu() {
    clear_screen
    echo -e "\033[1;36mSHM BACKUP TOOL\033[0m"
    echo "Version: $VERSION"
    echo -e "Target Directory: \033[33m$SHM_DIR\033[0m\n"
    echo "   1. Create backup manually (Send to Telegram)"
    echo ""
    echo "   2. Telegram bot status / restart"
    echo "   3. Edit configuration (.env)"
    echo ""
    echo "   4. Update script"
    echo "   5. Remove script"
    echo ""
    echo "   0. Exit"
    echo -e "   — Quick launch: \033[32mshm-backup\033[0m available from anywhere\n"
}

edit_config() {
    ${EDITOR:-nano} "$ENV_FILE"
    systemctl restart shm-backup-bot.service 2>/dev/null || true
    echo -e "\n\033[32m✅ Configuration saved & Bot restarted.\033[0m"
    sleep 1
}

check_bot_status() {
    echo ""
    systemctl status shm-backup-bot.service --no-pager || true
    echo -e "\nPress Enter to continue..."
    read -r
}

update_script() {
    echo -e "\n\033[33m⏳ Pulling latest updates from Git...\033[0m"
    git -C "$SCRIPT_DIR" pull
    echo -e "\033[32m✅ Update complete!\033[0m"
    echo -e "\nPress Enter to continue..."
    read -r
}

remove_script() {
    read -rp "⚠️ Remove shm-backup service, cron job, and script directory? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        systemctl disable --now shm-backup-bot.service 2>/dev/null || true
        rm -f /etc/systemd/system/shm-backup-bot.service
        systemctl daemon-reload
        rm -f /usr/local/bin/shm-backup
        (crontab -l 2>/dev/null | grep -v "shm-backup") | crontab - 2>/dev/null || true
        echo -e "\n\033[32m✅ Service and global binary removed.\033[0m"
        echo "You can now safely delete $SCRIPT_DIR."
        exit 0
    fi
}

# Interactive Menu Loop
while true; do
    show_menu
    read -rp "[?] Select option: " choice
    case "$choice" in
        1) run_manual_backup ;;
        2) check_bot_status ;;
        3) edit_config ;;
        4) update_script ;;
        5) remove_script ;;
        0) echo -e "\nGoodbye!"; exit 0 ;;
        *) echo -e "\033[31mInvalid option.\033[0m"; sleep 1 ;;
    esac
done
