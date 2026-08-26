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

# Clear screen utility
clear_screen() {
    clear 2>/dev/null || true
}

# Core Backup Logic
execute_backup() {
    echo -e "\n\033[33m⏳ Creating database backup...\033[0m"

    if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
        echo -e "\033[31m❌ Error: TELEGRAM_BOT_TOKEN or TELEGRAM_CHAT_ID is missing in .env\033[0m"
        return 1
    fi

    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    BACKUP_FILE="/tmp/shm_backup_${TIMESTAMP}.sql"

    # Dump database from the MySQL Docker container
    if docker compose -f "$SHM_DIR/docker-compose.yml" exec -T mysql /bin/bash -c 'MYSQL_PWD="${MYSQL_ROOT_PASSWORD}" mysqldump -u root shm' > "$BACKUP_FILE" 2>/dev/null; then
        echo -e "\033[32m✅ Database dumped successfully to $BACKUP_FILE\033[0m"
    else
        # Fallback for generic docker execution if compose file path isn't explicit
        if docker exec -t $(docker ps -qf "name=mysql") /bin/bash -c 'MYSQL_PWD="${MYSQL_ROOT_PASSWORD}" mysqldump -u root shm' > "$BACKUP_FILE" 2>/dev/null; then
             echo -e "\033[32m✅ Database dumped successfully to $BACKUP_FILE\033[0m"
        else
             echo -e "\033[31m❌ Error: Failed to generate MySQL dump.\033[0m"
             rm -f "$BACKUP_FILE"
             return 1
        fi
    fi

    echo -e "\033[33m⏳ Sending backup file to Telegram...\033[0m"

    # Send document via Telegram Bot API
    RESPONSE=$(curl -s -F chat_id="$TELEGRAM_CHAT_ID" \
         -F document=@"$BACKUP_FILE" \
         -F caption="📦 SHM Backup — $(date +'%Y-%m-%d %H:%M:%S')" \
         "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument")

    # Clean up local dump file
    rm -f "$BACKUP_FILE"

    if echo "$RESPONSE" | grep -q '"ok":true'; then
        echo -e "\033[32m✅ Backup successfully sent to Telegram!\033[0m"
    else
        echo -e "\033[31m❌ Failed to send backup to Telegram.\033[0m"
        echo "Telegram API Response: $RESPONSE"
        return 1
    fi
}

# Non-interactive mode (for Cron / automated tasks)
if [ "$1" == "--run" ]; then
    execute_backup
    exit 0
fi

# Interactive Menu Display
show_menu() {
    clear_screen
    echo -e "\033[1;36mSHM BACKUP TOOL\033[0m"
    echo "Version: $VERSION"
    echo -e "Target Directory: \033[33m$SHM_DIR\033[0m\n"
    echo "   1. Create backup manually (Send to Telegram)"
    echo ""
    echo "   2. Edit configuration (.env)"
    echo "   3. Update script"
    echo "   4. Remove script"
    echo ""
    echo "   0. Exit"
    echo -e "   — Quick launch: \033[32mshm-backup\033[0m available from anywhere\n"
}

run_manual_backup() {
    execute_backup
    echo -e "\nPress Enter to continue..."
    read -r
}

edit_config() {
    ${EDITOR:-nano} "$ENV_FILE"
    echo -e "\n\033[32m✅ Configuration saved.\033[0m"
    sleep 1
}

update_script() {
    echo -e "\n\033[33m⏳ Pulling latest updates from Git...\033[0m"
    git -C "$SCRIPT_DIR" pull
    echo -e "\033[32m✅ Update complete!\033[0m"
    echo -e "\nPress Enter to continue..."
    read -r
}

remove_script() {
    read -rp "⚠️ Remove shm-backup cron job and script binary? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        rm -f /usr/local/bin/shm-backup
        (crontab -l 2>/dev/null | grep -v "shm-backup") | crontab - 2>/dev/null || true
        echo -e "\n\033[32m✅ Cron job and global binary removed.\033[0m"
        echo "You can now safely delete $SCRIPT_DIR."
        exit 0
    fi
}

# Main Interactive Loop
while true; do
    show_menu
    read -rp "[?] Select option: " choice
    case "$choice" in
        1) run_manual_backup ;;
        2) edit_config ;;
        3) update_script ;;
        4) remove_script ;;
        0) echo -e "\nGoodbye!"; exit 0 ;;
        *) echo -e "\033[31mInvalid option.\033[0m"; sleep 1 ;;
    esac
done
