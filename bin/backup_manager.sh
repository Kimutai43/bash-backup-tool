#!/usr/bin/env bash

set -Eeuo pipefail

# Determine configuration path (supports global install or local dev)
if [[ -f "/opt/bash-backup-tool/config/settings.env" ]]; then
    source "/opt/bash-backup-tool/config/settings.env"
else
    # Fallback to local development paths
    CONFIG_PATH="$(dirname "$(readlink -f "$0")")/../config/settings.env"
    if [[ -f "$CONFIG_PATH" ]]; then
        source "$CONFIG_PATH"
    else
        echo "Error: Configuration file settings.env not found!" >&2
        exit 1
    fi
fi

# Ensure log and backup directories exist
mkdir -p "$(dirname "$LOG_FILE")"
mkdir -p "$BACKUP_DEST"

# Logging function
log_message() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date +"%Y-%m-%d %T")
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# Dependency health check
check_dependencies() {
    for cmd in tar gzip gpg curl rsync; do
        if ! command -v "$cmd" &> /dev/null; then
            echo "Warning: Required tool '$cmd' is missing." >&2
        fi
    done
}

# Webhook notification
send_webhook() {
    local status="$1"
    local message="$2"

    if [[ "${ENABLE_WEBHOOK:-false}" != "true" || -z "${WEBHOOK_URL:-}" ]]; then
        return
    fi

    local payload
    payload=$(jq -n --arg content "🔔 **Backup Tool Alert** [$status]: $message" '{content: $content}' 2>/dev/null || echo "{\"content\": \"Backup Tool Alert [$status]: $message\"}")

    curl -s -H "Content-Type: application/json" -X POST -d "$payload" "$WEBHOOK_URL" &>/dev/null || true
}

# Remote synchronization
push_to_remote() {
    local file_path="$1"

    if [[ "${ENABLE_REMOTE_SYNC:-false}" != "true" ]]; then
        return
    fi

    log_message "INFO" "Syncing '$file_path' to remote server $REMOTE_HOST:$REMOTE_DIR..."
    if rsync -avz -e "ssh" "$file_path" "$REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR"; then
        log_message "SUCCESS" "Successfully synced backup to remote server."
        send_webhook "SUCCESS" "Backup synced successfully to remote server!"
    else
        log_message "ERROR" "Failed to sync backup to remote server."
        send_webhook "ERROR" "Local backup succeeded, but remote sync failed."
    fi
}

# Backup function with disk space health check
perform_backup() {
    echo ""
    read -rp "Enter the absolute path of the directory to backup: " src_dir

    if [[ ! -d "$src_dir" ]]; then
        log_message "ERROR" "Source directory does not exist: $src_dir"
        echo "Directory not found."
        return
    fi

    mkdir -p "$BACKUP_DEST"

    # Pre-flight check: Verify destination disk space (ensure at least 100MB free)
    local available_space
    available_space=$(df -k "$BACKUP_DEST" | awk 'NR==2 {print $4}')
    if [[ "$available_space" -lt 102400 ]]; then
        log_message "ERROR" "Insufficient disk space on destination partition."
        echo "Error: Insufficient disk space in $BACKUP_DEST."
        return
    fi

    local timestamp
    timestamp=$(date +"%Y%m%d_%H%M%S")
    local archive_name="backup_$(basename "$src_dir")_$timestamp.tar.gz"
    local archive_path="$BACKUP_DEST/$archive_name"

    log_message "INFO" "Starting backup of '$src_dir' to '$archive_path'..."
    
    if tar -czf "$archive_path" -C "$(dirname "$src_dir")" "$(basename "$src_dir")"; then
        log_message "SUCCESS" "Archive created successfully: $archive_path"
        
        local final_backup_path="$archive_path"

        # Optional GPG Encryption
        read -rp "Do you want to encrypt this backup with GPG? (y/n): " encrypt_choice
        if [[ "$encrypt_choice" =~ ^[Yy]$ ]]; then
            read -rp "Enter GPG Recipient/Email: " gpg_recipient
            if gpg --encrypt --recipient "$gpg_recipient" "$archive_path"; then
                rm -f "$archive_path"
                final_backup_path="$archive_path.gpg"
                log_message "SUCCESS" "Backup encrypted successfully: $final_backup_path"
                echo "Backup completed and encrypted: $final_backup_path"
            else
                log_message "ERROR" "GPG encryption failed."
                echo "Encryption failed. Unencrypted archive remains at $archive_path"
            fi
        else
            echo "Backup completed successfully: $archive_path"
        fi

        push_to_remote "$final_backup_path"
        send_webhook "SUCCESS" "Backup completed successfully for $src_dir"
    else
        log_message "ERROR" "Failed to create archive for '$src_dir'."
        echo "Backup failed. Check logs."
        send_webhook "ERROR" "Failed to create archive for $src_dir"
    fi
}

# Restore function
perform_restore() {
    echo ""
    read -rp "Enter the path to the backup archive (.tar.gz or .tar.gz.gpg): " archive_path

    if [[ ! -f "$archive_path" ]]; then
        log_message "ERROR" "Backup archive not found: $archive_path"
        echo "Archive file not found."
        return
    fi

    read -rp "Enter the destination directory to restore files into: " restore_dest
    mkdir -p "$restore_dest"

    local file_to_extract="$archive_path"

    if [[ "$archive_path" == *.gpg ]]; then
        echo "Encrypted archive detected. Decrypting..."
        local decrypted_path="${archive_path%.gpg}"
        if gpg --decrypt --output "$decrypted_path" "$archive_path"; then
            log_message "INFO" "Successfully decrypted archive: $archive_path"
            file_to_extract="$decrypted_path"
        else
            log_message "ERROR" "Decryption failed."
            echo "Decryption failed."
            return
        fi
    fi

    log_message "INFO" "Restoring '$file_to_extract' to '$restore_dest'..."
    if tar -xzf "$file_to_extract" -C "$restore_dest"; then
        log_message "SUCCESS" "Restore completed successfully to '$restore_dest'."
        echo "Restore completed successfully!"
        
        if [[ "$archive_path" == *.gpg ]]; then
            rm -f "$file_to_extract"
        fi
    else
        log_message "ERROR" "Failed to extract archive."
        echo "Restore failed. Check logs."
    fi
}

# Cleanup Old Backups
cleanup_backups() {
    echo ""
    log_message "INFO" "Scanning '$BACKUP_DEST' for backups older than ${RETENTION_DAYS} days..."
    
    local deleted_files
    deleted_files=$(find "$BACKUP_DEST" -type f \( -name "backup_*.tar.gz" -o -name "backup_*.tar.gz.gpg" \) -mtime +"$RETENTION_DAYS" -print -delete)

    if [[ -n "$deleted_files" ]]; then
        log_message "SUCCESS" "Cleaned up old backups successfully:\n$deleted_files"
        echo "Old backups cleaned up successfully!"
    else
        log_message "INFO" "No backups older than $RETENTION_DAYS days found."
        echo "No matching old backups found to delete."
    fi
}

# Main Menu
main() {
    check_dependencies
    while true; do
        echo ""
        echo "=============================="
        echo "    BASH BACKUP & RESTORE     "
        echo "=============================="
        echo "1. Create Backup"
        echo "2. Restore Backup"
        echo "3. Cleanup Old Backups"
        echo "4. View Logs"
        echo "5. Exit"
        echo "=============================="
        read -rp "Select an option [1-5]: " choice

        case "$choice" in
            1) perform_backup ;;
            2) perform_restore ;;
            3) cleanup_backups ;;
            4) 
               if [[ -f "$LOG_FILE" ]]; then
                   cat "$LOG_FILE"
               else
                   echo "No logs found yet."
               fi
               ;;
            5) echo "Exiting. Goodbye!"; exit 0 ;;
            *) echo "Invalid option. Please choose between 1 and 5." ;;
        esac
    done
}

main
