#!/bin/bash

# Update script for SMTP to MailerSend Relay Service
# Run this script as root or with sudo

# Exit on any error
set -e

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root or with sudo"
  exit 1
fi

# Configuration
APP_NAME="smtp-mailersend-relay"
INSTALL_DIR="/opt/$APP_NAME"
SERVICE_NAME="smtp-mailersend.service"
SERVICE_USER="mailrelay"  # Dedicated service user

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SERVICE_SOURCE_DIR="$SCRIPT_DIR/service"

# Check if the service directory exists
if [ ! -d "$SERVICE_SOURCE_DIR" ]; then
  echo "ERROR: Service directory not found at $SERVICE_SOURCE_DIR"
  echo "Make sure you're running this script from the root of the repository and the 'service' folder exists."
  exit 1
fi

# Check if the service is installed
if [ ! -d "$INSTALL_DIR" ]; then
  echo "Error: Installation directory $INSTALL_DIR not found."
  echo "Please run the install script first."
  exit 1
fi

# Stop the service before updating
echo "Stopping service..."
systemctl stop $SERVICE_NAME

# Securely backup the .env file
ENV_BACKUP=""
if [ -f "$INSTALL_DIR/.env" ]; then
  echo "Securely backing up .env file..."
  # Create a secure backup file with timestamp in the installation directory
  TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
  ENV_BACKUP="$INSTALL_DIR/.env.backup.$TIMESTAMP"
  touch "$ENV_BACKUP"
  cp "$INSTALL_DIR/.env" "$ENV_BACKUP"
  chown "$SERVICE_USER:$SERVICE_USER" "$ENV_BACKUP"
  chmod 600 "$ENV_BACKUP"
  echo "Backed up to $ENV_BACKUP"
fi

# Copy all files from service directory to installation directory
echo "Copying service files from $SERVICE_SOURCE_DIR to $INSTALL_DIR..."
cp -r "$SERVICE_SOURCE_DIR"/* "$INSTALL_DIR"/

# Copy hidden files (like .env.example) - they're not included with * glob
echo "Copying hidden files..."
cp "$SERVICE_SOURCE_DIR"/.env* "$INSTALL_DIR"/ 2>/dev/null || true

# Set correct ownership for all copied files
chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR"

# Restore the .env file from secure backup
if [ ! -z "$ENV_BACKUP" ] && [ -f "$ENV_BACKUP" ]; then
  echo "Restoring .env file from secure backup..."
  cp "$ENV_BACKUP" "$INSTALL_DIR/.env"
  chown "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR/.env"
  echo "Env file restored successfully."
fi

# Update dependencies
echo "Updating dependencies..."
cd "$INSTALL_DIR"
sudo -u "$SERVICE_USER" npm install --production

# Ensure correct permissions
echo "Setting permissions..."
chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR"
if [ -f "$INSTALL_DIR/update.sh" ]; then
  chmod +x "$INSTALL_DIR/update.sh"
fi
if [ -f "$INSTALL_DIR/install.sh" ]; then
  chmod +x "$INSTALL_DIR/install.sh"
fi

# Copy the service file to systemd directory
if [ -f "$INSTALL_DIR/$SERVICE_NAME" ]; then
  echo "Updating systemd service file..."
  cp "$INSTALL_DIR/$SERVICE_NAME" /etc/systemd/system/
  # Ensure service file uses the correct service user
  sed -i "s/User=.*/User=$SERVICE_USER/" /etc/systemd/system/$SERVICE_NAME
  sed -i "s/Group=.*/Group=$SERVICE_USER/" /etc/systemd/system/$SERVICE_NAME
  # Reload systemd in case service file changed
  systemctl daemon-reload
fi

# Restart the service
echo "Starting service..."
systemctl start $SERVICE_NAME

# Check service status
echo "Service update complete. Current status:"
systemctl status $SERVICE_NAME --no-pager

echo ""
echo "======================================================"
echo "Update complete! The service has been restarted with the latest code."
echo "If you need to make any configuration changes, edit $INSTALL_DIR/.env"
echo "Check logs with: sudo journalctl -u $SERVICE_NAME -f"
echo "======================================================"