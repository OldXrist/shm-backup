# SHM Backup

Automated Telegram backup bot and CLI utility for **SHM** database dumps.

---

## Features

* **One-Click Backups:** Trigger instant MySQL database dumps directly inside Telegram.
* **Automated Cron Backups:** Scheduled daily backups sent straight to your personal Telegram chat or channel.
* **Service Daemon:** Automatically runs in the background using a lightweight `systemd` unit with minimal memory overhead.

---

## Installation

Run the installer script on your server:

```bash
curl -o ~/shm-backup.sh [https://raw.githubusercontent.com/OldXrist/shm-backup/main/install.sh](https://raw.githubusercontent.com/OldXrist/shm-backup/main/install.sh) && chmod +x ~/shm-backup.sh && ~/shm-backup.sh