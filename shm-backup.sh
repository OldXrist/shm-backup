#!/usr/bin/env bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
BACKUP_DIR="$SCRIPT_DIR/backups"
LATEST_BACKUP_FILE="$BACKUP_DIR/shm_backup.sql"
VERSION="2.3.0"

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

# Returns active cron schedule key: "6h", "12h", "daily", "weekly", or "disabled"
get_current_schedule() {
    local cron_entry
    cron_entry=$(crontab -l 2>/dev/null | grep "shm-backup" || true)

    if [ -z "$cron_entry" ]; then
        echo "disabled"
    elif echo "$cron_entry" | grep -q "0 \*/6 \* \* \*"; then
        echo "6h"
    elif echo "$cron_entry" | grep -q "0 \*/12 \* \* \*"; then
        echo "12h"
    elif echo "$cron_entry" | grep -q "0 0 \* \* \*"; then
        echo "daily"
    elif echo "$cron_entry" | grep -q "0 0 \* \* 0"; then
        echo "weekly"
    else
        echo "custom"
    fi
}

get_current_schedule_label() {
    case "$(get_current_schedule)" in
        "6h") echo "Every 6 hours" ;;
        "12h") echo "Every 12 hours" ;;
        "daily") echo "Daily at 00:00 UTC (03:00 MSK)" ;;
        "weekly") echo "Weekly on Sunday at 00:00 UTC (03:00 MSK)" ;;
        "disabled") echo "Disabled" ;;
        *) echo "Custom Cron" ;;
    esac
}

execute_backup() {
    echo -e "\n\033[33m⏳ Creating database backup...\033[0m"

    if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
        echo -e "\033[31m❌ Error: TELEGRAM_BOT_TOKEN or TELEGRAM_CHAT_ID is missing in .env\033[0m"
        return 1
    fi

    mkdir -p "$BACKUP_DIR"

    # Dump database and overwrite the latest backup file
    if docker compose -f "$SHM_DIR/docker-compose.yml" exec -T mysql /bin/bash -c 'MYSQL_PWD="${MYSQL_ROOT_PASSWORD}" mysqldump -u root shm' > "$LATEST_BACKUP_FILE" 2>/dev/null; then
        echo -e "\033[32m✅ Database dumped successfully to $LATEST_BACKUP_FILE\033[0m"
    else
        if docker exec -t $(docker ps -qf "name=mysql") /bin/bash -c 'MYSQL_PWD="${MYSQL_ROOT_PASSWORD}" mysqldump -u root shm' > "$LATEST_BACKUP_FILE" 2>/dev/null; then
             echo -e "\033[32m✅ Database dumped successfully to $LATEST_BACKUP_FILE\033[0m"
        else
             echo -e "\033[31m❌ Error: Failed to generate MySQL dump.\033[0m"
             return 1
        fi
    fi

    echo -e "\033[33m⏳ Sending latest backup file to Telegram...\033[0m"

    RESPONSE=$(curl -s -F chat_id="$TELEGRAM_CHAT_ID" \
         -F document=@"$LATEST_BACKUP_FILE" \
         -F caption="📦 SHM Backup — $(date -u +'%Y-%m-%d %H:%M:%S UTC')" \
         "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument")

    if echo "$RESPONSE" | grep -q '"ok":true'; then
        echo -e "\033[32m✅ Backup successfully sent to Telegram!\033[0m"
    else
        echo -e "\033[31m❌ Failed to send backup to Telegram.\033[0m"
        echo "Telegram API Response: $RESPONSE"
        return 1
    fi
}

execute_restore() {
    echo -e "\n\033[1;33m=== Restore SHM Database ===\033[0m"

    if [ ! -f "$LATEST_BACKUP_FILE" ]; then
        echo -e "\033[31m❌ No backup file found at $LATEST_BACKUP_FILE\033[0m"
        echo "Please run a backup first."
        return 1
    fi

    echo -e "Target File: \033[36m$LATEST_BACKUP_FILE\033[0m"
    read -rp "⚠️ Are you sure you want to restore the database? This will OVERWRITE existing DB data! (y/N): " confirm

    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "\n\033[33m⏳ Restoring database into MySQL container...\033[0m"

        if docker compose -f "$SHM_DIR/docker-compose.yml" exec -T mysql /bin/bash -c 'MYSQL_PWD=${MYSQL_ROOT_PASSWORD} mysql -u root shm' < "$LATEST_BACKUP_FILE"; then
            echo -e "\033[32m✅ Database restore complete!\033[0m"
        else
            echo -e "\033[31m❌ Restore failed.\033[0m"
            return 1
        fi
    else
        echo "Cancelled."
    fi
}

configure_schedule() {
    clear_screen
    local current
    current=$(get_current_schedule)

    mark() {
        if [ "$1" == "$current" ]; then
            echo -e " \033[1;32m[ACTIVE]\033[0m"
        else
            echo ""
        fi
    }

    echo -e "\033[1;36mBACKUP FREQUENCY CONFIGURATION\033[0m\n"
    echo -e "   1. Every 6 hours$(mark '6h')"
    echo -e "   2. Every 12 hours$(mark '12h')"
    echo -e "   3. Daily at 00:00 UTC (03:00 MSK)$(mark 'daily')"
    echo -e "   4. Weekly (Every Sunday at 00:00 UTC)$(mark 'weekly')"
    echo -e "   5. Disable automated backups$(mark 'disabled')"
    echo ""
    echo "   0. Back to main menu"
    echo ""
    read -rp "[?] Select option: " sched_choice

    local cron_time=""
    case "$sched_choice" in
        1) cron_time="0 */6 * * *" ;;
        2) cron_time="0 */12 * * *" ;;
        3) cron_time="0 0 * * *" ;;
        4) cron_time="0 0 * * 0" ;;
        5)
            (crontab -l 2>/dev/null | grep -v "shm-backup") | crontab - 2>/dev/null || true
            echo -e "\n\033[32m✅ Automated backups disabled.\033[0m"
            sleep 1.5
            return 0
            ;;
        0) return 0 ;;
        *) echo -e "\033[31mInvalid option.\033[0m"; sleep 1; return 0 ;;
    esac

    (crontab -l 2>/dev/null | grep -v "shm-backup") | crontab - 2>/dev/null || true
    (crontab -l 2>/dev/null; echo "$cron_time /usr/local/bin/shm-backup --run > /dev/null 2>&1") | crontab -

    echo -e "\n\033[32m✅ Backup schedule updated!\033[0m"
    sleep 1.5
}

# Non-interactive CLI mode (used by cron)
if [ "$1" == "--run" ]; then
    execute_backup
    exit 0
fi

show_menu() {
    clear_screen
    local sched_status
    sched_status=$(get_current_schedule_label)

    echo -e "\033[1;36mSHM BACKUP & RESTORE TOOL\033[0m"
    echo "Version: $VERSION"
    echo -e "Target Directory: \033[33m$SHM_DIR\033[0m"
    echo -e "Active Schedule:  \033[32m$sched_status\033[0m\n"
    echo "   1. Create backup manually (Send to Telegram)"
    echo "   2. Restore from backup"
    echo ""
    echo "   3. Configure backup schedule"
    echo "   4. Edit configuration"
    echo "   5. Update script"
    echo "   6. Remove script"
    echo ""
    echo "   0. Exit"
    echo -e "   — Quick launch: \033[32mshm-backup\033[0m available from anywhere\n"
}

run_manual_backup() {
    execute_backup
    echo -e "\nPress Enter to continue..."
    read -r
}

run_manual_restore() {
    execute_restore
    echo -e "\nPress Enter to continue..."
    read -r
}

edit_config() {
    ${EDITOR:-nano} "$ENV_FILE"
    echo -e "\n\033[32m✅ Configuration saved.\033[0m"
    sleep 1
}

update_script() {
    echo -e "\n\033[33m⏳ Fetching latest script update...\033[0m"
    curl -sSL "https://raw.githubusercontent.com/OldXrist/shm-backup/main/shm-backup.sh" -o "$SCRIPT_DIR/shm-backup.sh"
    chmod +x "$SCRIPT_DIR/shm-backup.sh"
    echo -e "\033[32m✅ Update complete!\033[0m"
    echo -e "\nPress Enter to continue..."
    read -r
}

remove_script() {
    read -rp "⚠️ Remove shm-backup cron job, global command, and files from $SCRIPT_DIR? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "\n\033[33m⏳ Cleaning up...\033[0m"
        rm -f /usr/local/bin/shm-backup
        (crontab -l 2>/dev/null | grep -v "shm-backup") | crontab - 2>/dev/null || true

        # Completely delete /opt/shm/shm-backup directory
        rm -rf "$SCRIPT_DIR"

        echo -e "\033[32m✅ Complete cleanup finished. Project folder removed.\033[0m"
        exit 0
    fi
}

while true; do
    show_menu
    read -rp "[?] Select option: " choice
    case "$choice" in
        1) run_manual_backup ;;
        2) run_manual_restore ;;
        3) configure_schedule ;;
        4) edit_config ;;
        5) update_script ;;
        6) remove_script ;;
        0) echo -e "\nGoodbye!"; exit 0 ;;
        *) echo -e "\033[31mInvalid option.\033[0m"; sleep 1 ;;
    esac
done
