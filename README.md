# Enterprise Bash Backup & Restore Tool

A robust, production-grade Bash utility designed for automated system backups, retention management, remote synchronization, webhook alerts, and military-grade GPG encryption.

# Features
* **Automated Archiving:** Compresses directories into standardized `.tar.gz` archives with dynamic timestamps.
* **Military-Grade Encryption:** Protects sensitive data at rest using GnuPG (GPG).
* **Seamless Restoration:** Safely extracts archives and handles on-the-fly decryption.
* **Automated Retention:** Cleans up old backups based on a configurable retention policy.
* **Background Cron Automation:** Runs seamlessly on Linux via scheduled cron jobs.
* **Remote Sync & Webhooks:** Replicates backups to remote servers and sends status notifications.
* **Centralized Audit Logging:** Tracks all actions, warnings, and errors in real-time.

##  Usage
Run the interactive manager:
```bash
./bin/backup_manager.sh
