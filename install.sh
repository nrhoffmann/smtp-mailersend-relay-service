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
NODE_VERSION="18"  # Node.js version to install

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
  useradd -r -s /bin/bash -m -d "/home/$SERVICE_USER" "$SERVICE_USER"
  echo "User $SERVICE_USER created successfully"
fi

# Install NVM for the service user
echo "Installing NVM and Node.js..."
# Make sure curl is installed
apt-get update
apt-get install -y curl

# Install NVM for the service user
sudo -u "$SERVICE_USER" bash -c "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash"

# Setup NVM in service user's .bashrc if not already there
if ! grep -q "NVM_DIR" /home/$SERVICE_USER/.bashrc; then
  cat >> /home/$SERVICE_USER/.bashrc << 'EOF'
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion
EOF
fi

# Source the updated .bashrc
echo "Installing Node.js using NVM..."
sudo -u "$SERVICE_USER" bash -c "source /home/$SERVICE_USER/.nvm/nvm.sh && nvm install $NODE_VERSION && nvm alias default $NODE_VERSION"

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
sudo -u "$SERVICE_USER" bash -c "source /home/$SERVICE_USER/.nvm/nvm.sh && cd $INSTALL_DIR && npm install --production"

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

# Update the systemd service file to use the NVM-installed Node.js
NODE_EXEC_PATH=$(sudo -u "$SERVICE_USER" bash -c "source /home/$SERVICE_USER/.nvm/nvm.sh && which node")
echo "Node.js path: $NODE_EXEC_PATH"

# Create or update systemd service file with the correct Node.js path
echo "Creating systemd service file..."
cat > /etc/systemd/system/$SERVICE_NAME << EOF
[Unit]
Description=SMTP to MailerSend Relay Service
After=network.target

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_USER
WorkingDirectory=$INSTALL_DIR
ExecStart=$NODE_EXEC_PATH $INSTALL_DIR/index.js
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=smtp-mailersend
Environment=NODE_ENV=production

# Ensure the service has enough file descriptors
LimitNOFILE=65536

# Security measures
PrivateTmp=true
NoNewPrivileges=true
ProtectSystem=full
ProtectHome=true

[Install]
WantedBy=multi-user.target
EOF

# Make scripts executable
if [ -f "$INSTALL_DIR/update-service.sh" ]; then
  chmod +x "$INSTALL_DIR/update-service.sh"
fi
if [ -f "$INSTALL_DIR/install-service.sh" ]; then
  chmod +x "$INSTALL_DIR/install-service.sh"
fi

# Update user in update script if it exists
if [ -f "$INSTALL_DIR/update-service.sh" ]; then
  sed -i "s/SERVICE_USER=\"[^\"]*\"/SERVICE_USER=\"$SERVICE_USER\"/" "$INSTALL_DIR/update-service.sh"
fi

# Reload systemd, enable and start service
systemctl daemon-reload
systemctl enable $SERVICE_NAME

echo ""
echo "==============================================="
echo "Installation complete!"
echo "Service user: $SERVICE_USER"
echo "Installation directory: $INSTALL_DIR"
echo "Node.js installed via NVM: $NODE_EXEC_PATH"
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