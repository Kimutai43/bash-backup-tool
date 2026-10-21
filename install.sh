#!/usr/bin/env bash
set -Eeuo pipefail

echo "=========================================="
echo "  Installing Enterprise Backup & Restore  "
echo "=========================================="

INSTALL_DIR="/opt/bash-backup-tool"
USER_HOME="$HOME"

# 1. Create system directories
echo "[*] Creating directory structure..."
sudo mkdir -p "$INSTALL_DIR/bin" "$INSTALL_DIR/logs" "$INSTALL_DIR/backups" "$INSTALL_DIR/config"

# 2. Copy files over
echo "[*] Copying project files..."
sudo cp ./bin/backup_manager.sh "$INSTALL_DIR/bin/backup_manager.sh"
sudo cp ./config/settings.env "$INSTALL_DIR/config/settings.env"

# 3. Set secure permissions
echo "[*] Setting permissions..."
sudo chmod +x "$INSTALL_DIR/bin/backup_manager.sh"
sudo chown -R $USER:$USER "$INSTALL_DIR"

# 4. Create a global symlink so user can type 'backup-tool' anywhere
echo "[*] Creating global command 'backup-tool'..."
sudo ln -sf "$INSTALL_DIR/bin/backup_manager.sh" /usr/local/bin/backup-tool

echo "=========================================="
echo "✅ Installation Complete!"
echo "You can now run your tool from anywhere by typing:"
echo "  backup-tool"
echo "=========================================="
