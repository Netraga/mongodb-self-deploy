#!/bin/bash

# MongoDB Security Configuration Script
# Enables authentication and configures security settings

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

print_status "Configuring MongoDB security..."

# Create MongoDB configuration with authentication enabled
print_status "Creating secure MongoDB configuration..."
cat > /etc/mongod.conf << 'EOF'
# MongoDB configuration file for production use with authentication
# Replace YOUR_DOMAIN with your actual FQDN

# Where and how to store data
storage:
  dbPath: /var/lib/mongodb
  engine: wiredTiger
  wiredTiger:
    engineConfig:
      cacheSizeGB: 2

# Where to write logging data
systemLog:
  destination: file
  logAppend: true
  path: /var/log/mongodb/mongod.log
  logRotate: reopen
  verbosity: 0
  quiet: false
  component:
    accessControl:
      verbosity: 0
    command:
      verbosity: 0

# Network interfaces
net:
  port: 27017
  bindIp: 127.0.0.1
  maxIncomingConnections: 65536
  
# Process management
processManagement:
  timeZoneInfo: /usr/share/zoneinfo
  fork: true

# Security - ENABLED
security:
  authorization: enabled
  javascriptEnabled: true

# Operation profiling
operationProfiling:
  mode: off
  slowOpThresholdMs: 100

# Audit logging (requires MongoDB Enterprise)
#auditLog:
#  destination: file
#  format: JSON
#  path: /var/log/mongodb/audit.json

# Set parameter options
setParameter:
  enableLocalhostAuthBypass: false
  authenticationMechanisms: SCRAM-SHA-256
EOF

# Restart MongoDB with authentication enabled
print_status "Restarting MongoDB with authentication enabled..."
systemctl restart mongod

# Wait for MongoDB to restart
print_status "Waiting for MongoDB to restart..."
sleep 10

# Check if MongoDB is running
if systemctl is-active --quiet mongod; then
    print_status "MongoDB is running with authentication enabled!"
else
    print_error "MongoDB failed to start. Check logs: journalctl -u mongod"
    exit 1
fi

# Create keyfile for replica set authentication (if needed)
print_status "Creating keyfile for replica set authentication..."
openssl rand -base64 756 > /etc/mongodb-keyfile
chmod 400 /etc/mongodb-keyfile
chown mongodb:mongodb /etc/mongodb-keyfile

print_status "Security configuration completed!"
print_status "MongoDB is now running with authentication enabled."
print_warning "From now on, you must authenticate to access MongoDB."
print_status "Connection example:"
print_status "  mongosh -u adminUser -p '<password-from-.env>' --authenticationDatabase admin"
print_status ""
print_status "For application connections:"
print_status "  mongodb://username:password@YOUR_DOMAIN:27017/database?authSource=admin"