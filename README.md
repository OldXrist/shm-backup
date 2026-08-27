# SHM Backup & Restore

Bash utility for automated MySQL database dumps and manual restoration for SHM (Universal Billing System).

---

## Features

* **Manual Dumps:** Generate and send MySQL dumps directly to Telegram via CLI.
* **Database Restoration:** Restore database state directly from the latest SQL backup file.
* **Flexible Scheduling:** Configurable cron routines for 6h, 12h, daily, or weekly runs (UTC).
* **Environment Configuration:** Manage environment credentials and directory paths directly from the CLI.

---

## Installation

Run the installer script:

```bash
curl -sSL [https://raw.githubusercontent.com/OldXrist/shm-backup/main/install.sh](https://raw.githubusercontent.com/OldXrist/shm-backup/main/install.sh) | bash
```

---

## Usage
Launch the CLI:

```bash
shm-backup
