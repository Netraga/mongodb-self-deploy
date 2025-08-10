#!/bin/bash

# MongoDB Firewall Configuration Script
# Sets up UFW firewall rules for MongoDB

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

print_status "Configuring firewall for MongoDB..."

# Install UFW if not already installed
if ! command -v ufw &> /dev/null; then
    print_status "Installing UFW..."
    apt-get update
    apt-get install -y ufw
fi

# Enable UFW
print_status "Enabling UFW..."
ufw --force enable

# Allow SSH (important to not lock yourself out!)
print_status "Allowing SSH access..."
ufw allow 22/tcp

# Allow HTTP and HTTPS (if needed for web applications)
print_status "Allowing HTTP/HTTPS access..."
ufw allow 80/tcp
ufw allow 443/tcp

# Configure MongoDB port 27017
print_status "Configuring MongoDB firewall rules..."

# Allow localhost
ufw allow from 127.0.0.1 to any port 27017

# IMPORTANT: By default, MongoDB port 27017 is NOT open to external connections
# This is for security. You must explicitly allow specific IPs.

# Example: Allow specific IP addresses (replace with your application servers)
# ufw allow from 192.168.1.100 to any port 27017
# ufw allow from 10.0.0.0/24 to any port 27017

# For testing, you might temporarily allow your office IP
# WARNING: Never leave MongoDB open to all IPs (0.0.0.0/0) in production!
# ufw allow from YOUR_OFFICE_IP to any port 27017

print_warning "IMPORTANT: MongoDB port 27017 is currently only accessible from localhost!"
print_warning "To allow external connections, use: mongodb-allow-ip.sh <IP_ADDRESS>"
print_warning "NEVER open MongoDB to all IPs (0.0.0.0/0) in production!"

# Create a script to easily add allowed IPs
cat > /usr/local/bin/mongodb-allow-ip.sh << 'EOF'
#!/bin/bash
# Script to add IP to MongoDB firewall whitelist

if [ $# -eq 0 ]; then
    echo "Usage: $0 <IP_ADDRESS or SUBNET>"
    echo "Example: $0 192.168.1.100"
    echo "Example: $0 10.0.0.0/24"
    exit 1
fi

IP=$1
echo "Adding $IP to MongoDB firewall whitelist..."
ufw allow from $IP to any port 27017
ufw status
EOF

chmod +x /usr/local/bin/mongodb-allow-ip.sh

# Show current firewall status
print_status "Current firewall status:"
ufw status verbose

# Create documentation for firewall rules
cat > /etc/mongodb-firewall-rules.txt << EOF
MongoDB Firewall Configuration
==============================

MongoDB Port: 27017
Allowed connections:
- Localhost (127.0.0.1)

To add new IP addresses to the whitelist:
  mongodb-allow-ip.sh <IP_ADDRESS>

Example:
  mongodb-allow-ip.sh 192.168.1.100
  mongodb-allow-ip.sh 10.0.0.0/24

To check firewall status:
  ufw status verbose

To remove a rule:
  ufw delete allow from <IP> to any port 27017

Security Notes:
- Only allow specific IPs that need MongoDB access
- Never allow 0.0.0.0/0 (all IPs) for MongoDB
- Regularly review and audit firewall rules
- Consider using VPN for remote access
EOF

print_status "Firewall configuration completed!"
print_status "MongoDB is currently only accessible from localhost."
print_warning "To allow remote connections, use: mongodb-allow-ip.sh <IP_ADDRESS>"
print_status "Firewall rules documented in: /etc/mongodb-firewall-rules.txt"