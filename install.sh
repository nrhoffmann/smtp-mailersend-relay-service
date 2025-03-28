#!/bin/bash

# Installation script for SMTP to MailerSend Relay Service
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
SERVICE_USER="mailrelay"  # Dedicated user for the service

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SERVICE_SOURCE_DIR="$SCRIPT_DIR/service"

# Check if service directory exists
if [ ! -d "$SERVICE_SOURCE_DIR" ]; then
  echo "ERROR: Service directory not found at $SERVICE_SOURCE_DIR"
  echo "Make sure you're running this script from the root of the repository and the 'service' folder exists."
  exit 1
fi

# Check for required files before proceeding
if [ ! -f "$SERVICE_SOURCE_DIR/index.js" ]; then
  echo "ERROR: Required file index.js not found in $SERVICE_SOURCE_DIR"
  exit 1
fi

if [ ! -f "$SERVICE_SOURCE_DIR/package.json" ]; then
  echo "ERROR: Required file package.json not found in $SERVICE_SOURCE_DIR"
  exit 1
fi

if [ ! -f "$SERVICE_SOURCE_DIR/.env.example" ]; then
  echo "ERROR: Required file .env.example not found in $SERVICE_SOURCE_DIR"
  exit 1
fi

if [ ! -f "$SERVICE_SOURCE_DIR/$SERVICE_NAME" ]; then
  echo "ERROR: Required service file $SERVICE_NAME not found in $SERVICE_SOURCE_DIR"
  exit 1
fi

# All required files are present, proceed with installation
echo "All required files found, proceeding with installation..."

# Create dedicated service user if it doesn't exist
if ! id "$SERVICE_USER" &>/dev/null; then
  echo "Creating dedicated service user $SERVICE_USER..."
  useradd -r -s /bin/false -m -d "/home/$SERVICE_USER" "$SERVICE_USER"
  echo "User $SERVICE_USER created successfully"
fi

# Install Node.js if not already installed
if ! command -v node &> /dev/null; then
  echo "Installing Node.js..."
  curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
  apt-get install -y nodejs
fi

# Create installation directory
echo "Creating installation directory..."
mkdir -p "$INSTALL_DIR"
chown "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR"

# Copy all files from service directory to installation directory
echo "Copying service files from $SERVICE_SOURCE_DIR to $INSTALL_DIR..."
cp -r "$SERVICE_SOURCE_DIR"/* "$INSTALL_DIR"/

# Copy hidden files (like .env.example) - they're not included with * glob
echo "Copying hidden files..."
cp "$SERVICE_SOURCE_DIR"/.env* "$INSTALL_DIR"/ 2>/dev/null || true

# Set correct ownership for all copied files
chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR"

# Install dependencies
echo "Installing dependencies..."
cd "$INSTALL_DIR"
sudo -u "$SERVICE_USER" npm install --production

# Create attachment directory
mkdir -p "$INSTALL_DIR/attachments"
chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR/attachments"

# Copy .env file from example if it doesn't exist
if [ ! -f "$INSTALL_DIR/.env" ]; then
  echo "Creating .env file from example..."
  cp "$INSTALL_DIR/.env.example" "$INSTALL_DIR/.env"
  chown "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR/.env"
  echo "Please edit $INSTALL_DIR/.env to add your MailerSend API key."
fi

# Create or update systemd service file
echo "Creating systemd service file..."
cp "$INSTALL_DIR/$SERVICE_NAME" /etc/systemd/system/
# Ensure service file uses the correct service user
sed -i "s/User=.*/User=$SERVICE_USER/" /etc/systemd/system/$SERVICE_NAME
sed -i "s/Group=.*/Group=$SERVICE_USER/" /etc/systemd/system/$SERVICE_NAME

# Make scripts executable
if [ -f "$INSTALL_DIR/update.sh" ]; then
  chmod +x "$INSTALL_DIR/update.sh"
fi
if [ -f "$INSTALL_DIR/install.sh" ]; then
  chmod +x "$INSTALL_DIR/install.sh"
fi

# Update user in update script if it exists
if [ -f "$INSTALL_DIR/update.sh" ]; then
  sed -i "s/SERVICE_USER=\"[^\"]*\"/SERVICE_USER=\"$SERVICE_USER\"/" "$INSTALL_DIR/update.sh"
fi

# Reload systemd, enable and start service
systemctl daemon-reload
systemctl enable $SERVICE_NAME

echo ""
echo "==============================================="
echo "Installation complete!"
echo "Service user: $SERVICE_USER"
echo "Installation directory: $INSTALL_DIR"
echo ""
echo "IMPORTANT: Edit your .env file before starting the service:"
echo "  sudo nano $INSTALL_DIR/.env"
echo ""
echo "Start the service with:"
echo "  sudo systemctl start $SERVICE_NAME"
echo ""
echo "Check status with:"
echo "  sudo systemctl status $SERVICE_NAME"
echo "==============================================="