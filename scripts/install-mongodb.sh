#!/bin/bash

# MongoDB Installation Script for Ubuntu 24.04
# This script installs MongoDB 7.0 and configures it for production use

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root"
   exit 1
fi

print_status "Starting MongoDB installation..."

# Update system packages
print_status "Updating system packages..."
apt-get update
apt-get upgrade -y

# Install required packages
print_status "Installing required packages..."
apt-get install -y gnupg curl

# Import MongoDB public GPG key
print_status "Importing MongoDB GPG key..."
curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | gpg --dearmor -o /usr/share/keyrings/mongodb-server-7.0.gpg

# Create MongoDB source list file
print_status "Adding MongoDB repository..."
echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-7.0.list

# Update package database
print_status "Updating package database..."
apt-get update

# Install MongoDB
print_status "Installing MongoDB..."
apt-get install -y mongodb-org

# Hold MongoDB packages to prevent unintended upgrades
print_status "Preventing automatic MongoDB upgrades..."
echo "mongodb-org hold" | dpkg --set-selections
echo "mongodb-org-database hold" | dpkg --set-selections
echo "mongodb-org-server hold" | dpkg --set-selections
echo "mongodb-mongosh hold" | dpkg --set-selections
echo "mongodb-org-mongos hold" | dpkg --set-selections
echo "mongodb-org-tools hold" | dpkg --set-selections

# Create MongoDB user if it doesn't exist
print_status "Creating MongoDB user..."
if ! id mongodb &>/dev/null; then
    useradd --system --no-create-home --shell /bin/false mongodb
fi

# Create MongoDB data and log directories
print_status "Creating MongoDB directories..."
mkdir -p /var/lib/mongodb
mkdir -p /var/log/mongodb
chown -R mongodb:mongodb /var/lib/mongodb
chown -R mongodb:mongodb /var/log/mongodb

# Copy custom configuration file
print_status "Copying MongoDB configuration..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cp "$SCRIPT_DIR/configs/mongod.conf" /etc/mongod.conf
chown root:root /etc/mongod.conf
chmod 644 /etc/mongod.conf

# Enable and start MongoDB
print_status "Starting MongoDB service..."
systemctl daemon-reload
systemctl enable mongod
systemctl start mongod

# Wait for MongoDB to start
print_status "Waiting for MongoDB to start..."
sleep 5

# Check MongoDB status
if systemctl is-active --quiet mongod; then
    print_status "MongoDB is running successfully!"
else
    print_error "MongoDB failed to start. Check logs: journalctl -u mongod"
    exit 1
fi

print_status "MongoDB installation completed!"
print_status "Next steps:"
print_status "1. Run ./configure-security.sh to set up authentication"
print_status "2. Run ./create-users.sh to create database users"
print_status "3. Run ./setup-firewall.sh to configure firewall rules"