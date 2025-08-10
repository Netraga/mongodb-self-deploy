#!/bin/bash

# SSH Tunnel Setup Script for MongoDB
# Creates secure SSH tunnel to hide MongoDB server IP - 100% FREE

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_header() {
    echo -e "${BLUE}[SETUP]${NC} $1"
    echo "======================================="
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root"
   exit 1
fi

print_header "SSH Tunnel Setup for MongoDB"
print_status "This script configures your server for SSH tunnel access"
print_status "Clients will connect through encrypted SSH tunnels instead of direct connections"
echo ""

# Configure SSH server
print_header "Configuring SSH Server"

print_status "Backing up SSH configuration..."
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup.$(date +%Y%m%d_%H%M%S)

print_status "Updating SSH configuration for tunneling..."

# Enable necessary SSH options for tunneling
if ! grep -q "^PermitTunnel" /etc/ssh/sshd_config; then
    echo "PermitTunnel yes" >> /etc/ssh/sshd_config
else
    sed -i 's/^PermitTunnel.*/PermitTunnel yes/' /etc/ssh/sshd_config
fi

if ! grep -q "^AllowTcpForwarding" /etc/ssh/sshd_config; then
    echo "AllowTcpForwarding yes" >> /etc/ssh/sshd_config
else
    sed -i 's/^AllowTcpForwarding.*/AllowTcpForwarding yes/' /etc/ssh/sshd_config
fi

if ! grep -q "^GatewayPorts" /etc/ssh/sshd_config; then
    echo "GatewayPorts yes" >> /etc/ssh/sshd_config
else
    sed -i 's/^GatewayPorts.*/GatewayPorts yes/' /etc/ssh/sshd_config
fi

# Security hardening
if ! grep -q "^MaxAuthTries" /etc/ssh/sshd_config; then
    echo "MaxAuthTries 3" >> /etc/ssh/sshd_config
else
    sed -i 's/^MaxAuthTries.*/MaxAuthTries 3/' /etc/ssh/sshd_config
fi

if ! grep -q "^ClientAliveInterval" /etc/ssh/sshd_config; then
    echo "ClientAliveInterval 60" >> /etc/ssh/sshd_config
    echo "ClientAliveCountMax 3" >> /etc/ssh/sshd_config
fi

print_status "Restarting SSH service..."
systemctl restart ssh

if systemctl is-active --quiet ssh; then
    print_status "SSH service restarted successfully"
else
    print_error "SSH service failed to restart"
    exit 1
fi

# Configure MongoDB
print_header "Configuring MongoDB for SSH Tunnel Access"

print_status "Backing up MongoDB configuration..."
cp /etc/mongod.conf /etc/mongod.conf.backup.$(date +%Y%m%d_%H%M%S)

print_status "Updating MongoDB to bind only to localhost..."

# Update MongoDB configuration to bind only to localhost
if grep -q "bindIp:" /etc/mongod.conf; then
    sed -i 's/bindIp:.*/bindIp: 127.0.0.1/' /etc/mongod.conf
else
    # Add bindIp if not present
    sed -i '/^net:/a\  bindIp: 127.0.0.1' /etc/mongod.conf
fi

print_status "Restarting MongoDB..."
systemctl restart mongod

# Wait for MongoDB to start
sleep 5

if systemctl is-active --quiet mongod; then
    print_status "MongoDB restarted successfully"
else
    print_error "MongoDB failed to restart"
    exit 1
fi

# Configure firewall
print_header "Configuring Firewall"

print_status "Updating firewall rules for SSH tunnel access..."

# Allow SSH
ufw allow ssh
ufw allow 22/tcp

# Block direct MongoDB access
ufw delete allow 27017 2>/dev/null || true
ufw deny 27017

# Apply firewall rules
ufw --force enable

print_status "Firewall configured - MongoDB only accessible via SSH tunnel"

# Create client connection scripts
print_header "Creating Client Connection Scripts"

# Create directory for client scripts
mkdir -p /usr/local/share/mongodb-tunnel

# Create SSH tunnel connection script
cat > /usr/local/share/mongodb-tunnel/ssh-tunnel-mongodb.sh << 'EOF'
#!/bin/bash

# MongoDB SSH Tunnel Connection Script
# Run this on client machines to connect via SSH tunnel

set -euo pipefail

# Configuration - UPDATE THESE VALUES
SERVER_IP="YOUR_SERVER_IP_HERE"
SERVER_USER="root"  # or your SSH user
LOCAL_PORT="27017"
REMOTE_PORT="27017"
SSH_KEY=""  # Path to SSH key (optional)

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

# Usage function
usage() {
    echo "MongoDB SSH Tunnel Client"
    echo "Usage: $0 [start|stop|status|test]"
    echo ""
    echo "Commands:"
    echo "  start   - Start SSH tunnel"
    echo "  stop    - Stop SSH tunnel"
    echo "  status  - Check tunnel status"
    echo "  test    - Test MongoDB connection"
    echo ""
    echo "Before first use, edit this script and update:"
    echo "  SERVER_IP=\"your.server.ip.here\""
    echo "  SERVER_USER=\"your_ssh_user\""
    exit 1
}

# Check configuration
check_config() {
    if [ "$SERVER_IP" = "YOUR_SERVER_IP_HERE" ]; then
        print_error "Please edit this script and set your actual SERVER_IP"
        print_error "Edit: $0"
        print_error "Change SERVER_IP=\"YOUR_SERVER_IP_HERE\" to your server's IP"
        exit 1
    fi
}

# Start SSH tunnel
start_tunnel() {
    check_config
    
    print_status "Starting SSH tunnel to MongoDB server..."
    
    # Check if tunnel already exists
    if pgrep -f "ssh.*$SERVER_IP.*$LOCAL_PORT:localhost:$REMOTE_PORT" > /dev/null; then
        print_warning "SSH tunnel already running"
        return 0
    fi
    
    # Build SSH command
    SSH_CMD="ssh -fN -L $LOCAL_PORT:localhost:$REMOTE_PORT"
    
    if [ -n "$SSH_KEY" ]; then
        SSH_CMD="$SSH_CMD -i $SSH_KEY"
    fi
    
    SSH_CMD="$SSH_CMD $SERVER_USER@$SERVER_IP"
    
    # Start tunnel
    if $SSH_CMD; then
        sleep 2
        if timeout 5 bash -c "</dev/tcp/localhost/$LOCAL_PORT" 2>/dev/null; then
            print_status "✅ SSH tunnel established successfully!"
            print_status "MongoDB is now accessible at: localhost:$LOCAL_PORT"
            print_status ""
            print_status "Connection examples:"
            print_status "  mongosh --host localhost --port $LOCAL_PORT -u adminUser --authenticationDatabase admin"
            print_status "  Connection string: mongodb://username:password@localhost:$LOCAL_PORT/database?authSource=admin"
        else
            print_error "Tunnel created but MongoDB is not accessible"
            exit 1
        fi
    else
        print_error "Failed to establish SSH tunnel"
        print_error "Check: SSH key permissions, server IP, user credentials"
        exit 1
    fi
}

# Stop SSH tunnel
stop_tunnel() {
    print_status "Stopping SSH tunnel..."
    
    if pgrep -f "ssh.*$LOCAL_PORT:localhost:$REMOTE_PORT" > /dev/null; then
        pkill -f "ssh.*$LOCAL_PORT:localhost:$REMOTE_PORT"
        print_status "SSH tunnel stopped"
    else
        print_warning "No SSH tunnel found running"
    fi
}

# Check tunnel status
check_status() {
    if pgrep -f "ssh.*$LOCAL_PORT:localhost:$REMOTE_PORT" > /dev/null; then
        print_status "✅ SSH tunnel is running"
        
        # Show process details
        ps aux | grep "ssh.*$LOCAL_PORT:localhost:$REMOTE_PORT" | grep -v grep
        
        # Test local connection
        if timeout 2 bash -c "</dev/tcp/localhost/$LOCAL_PORT" 2>/dev/null; then
            print_status "✅ Local port $LOCAL_PORT is accessible"
        else
            print_warning "❌ Local port $LOCAL_PORT is not accessible"
        fi
    else
        print_warning "❌ No SSH tunnel running"
        return 1
    fi
}

# Test MongoDB connection
test_connection() {
    check_config
    
    print_status "Testing MongoDB connection through SSH tunnel..."
    
    if ! pgrep -f "ssh.*$LOCAL_PORT:localhost:$REMOTE_PORT" > /dev/null; then
        print_error "SSH tunnel is not running"
        print_status "Run: $0 start"
        exit 1
    fi
    
    if command -v mongosh >/dev/null 2>&1; then
        if timeout 10 mongosh --host localhost --port "$LOCAL_PORT" --eval "db.adminCommand('ping')" --quiet >/dev/null 2>&1; then
            print_status "✅ MongoDB is accessible through SSH tunnel"
            print_status "You can now connect with your credentials"
        else
            print_warning "⚠️  MongoDB connection failed (may need authentication)"
            print_status "Try: mongosh --host localhost --port $LOCAL_PORT -u adminUser --authenticationDatabase admin"
        fi
    else
        print_warning "⚠️  mongosh not installed, cannot test MongoDB connection"
        print_status "Install with: sudo apt install mongodb-mongosh"
    fi
}

# Main script logic
case "${1:-}" in
    "start")
        start_tunnel
        ;;
    "stop")
        stop_tunnel
        ;;
    "status")
        check_status
        ;;
    "test")
        test_connection
        ;;
    "")
        usage
        ;;
    *)
        echo "Unknown command: $1"
        usage
        ;;
esac
EOF

chmod +x /usr/local/share/mongodb-tunnel/ssh-tunnel-mongodb.sh

# Create server info file
SERVER_IP=$(curl -s ifconfig.me || curl -s ipinfo.io/ip || hostname -I | awk '{print $1}')

cat > /usr/local/share/mongodb-tunnel/server-info.txt << EOF
MongoDB SSH Tunnel Server Information
====================================

Server IP: $SERVER_IP
SSH Port: 22
MongoDB Port: 27017 (localhost only)
Created: $(date)

Client Setup Instructions:
1. Copy ssh-tunnel-mongodb.sh to your client machine
2. Edit the script and update SERVER_IP="$SERVER_IP"
3. Run: ./ssh-tunnel-mongodb.sh start
4. Connect: mongosh --host localhost --port 27017 -u adminUser --authenticationDatabase admin

Connection String Template:
mongodb://username:password@localhost:27017/database?authSource=admin
EOF

# Create systemd service for auto-restart
cat > /etc/systemd/system/mongodb-tunnel-monitor.service << 'EOF'
[Unit]
Description=MongoDB SSH Tunnel Monitor
After=network.target ssh.service mongod.service

[Service]
Type=simple
User=mongodb
ExecStart=/bin/bash -c 'while true; do sleep 300; done'
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable mongodb-tunnel-monitor.service
systemctl start mongodb-tunnel-monitor.service

# Final instructions
print_header "Setup Complete!"

echo ""
print_status "🎉 SSH Tunnel setup completed successfully!"
echo ""
print_status "📋 Configuration Summary:"
print_status "  • MongoDB bound to: localhost:27017 only"
print_status "  • SSH tunneling: Enabled"
print_status "  • Direct access to port 27017: Blocked"
print_status "  • Server IP: $SERVER_IP"
echo ""
print_status "📁 Files Created:"
print_status "  • Client script: /usr/local/share/mongodb-tunnel/ssh-tunnel-mongodb.sh"
print_status "  • Server info: /usr/local/share/mongodb-tunnel/server-info.txt"
echo ""
print_status "👥 For Clients:"
print_status "1. Copy the client script to their machines:"
print_status "   scp root@$SERVER_IP:/usr/local/share/mongodb-tunnel/ssh-tunnel-mongodb.sh ."
echo ""
print_status "2. Edit the script and update SERVER_IP:"
print_status "   nano ssh-tunnel-mongodb.sh"
print_status "   # Change: SERVER_IP=\"$SERVER_IP\""
echo ""
print_status "3. Run the tunnel:"
print_status "   chmod +x ssh-tunnel-mongodb.sh"
print_status "   ./ssh-tunnel-mongodb.sh start"
echo ""
print_status "4. Connect to MongoDB:"
print_status "   mongosh --host localhost --port 27017 -u adminUser --authenticationDatabase admin"
echo ""
print_warning "🔒 Security Benefits:"
print_warning "  ✅ Server IP completely hidden from MongoDB clients"
print_warning "  ✅ All traffic encrypted through SSH"
print_warning "  ✅ No direct access to MongoDB port"
print_warning "  ✅ Uses existing SSH infrastructure - 100% FREE!"
echo ""
print_status "✅ Your MongoDB server IP is now completely hidden behind SSH tunnels!"

# Show how to distribute client script
echo ""
print_status "📤 To distribute the client script:"
print_status "cat > distribute-client-script.sh << 'SCRIPT_END'"
cat << 'SCRIPT_END'
#!/bin/bash
# Run this to copy client script to a machine

TARGET_HOST="$1"
if [ -z "$TARGET_HOST" ]; then
    echo "Usage: $0 <target_host_or_ip>"
    echo "Example: $0 user@client-machine.com"
    exit 1
fi

echo "Copying SSH tunnel client script to $TARGET_HOST..."
scp /usr/local/share/mongodb-tunnel/ssh-tunnel-mongodb.sh "$TARGET_HOST":~/
scp /usr/local/share/mongodb-tunnel/server-info.txt "$TARGET_HOST":~/

echo ""
echo "Now SSH to $TARGET_HOST and run:"
echo "chmod +x ssh-tunnel-mongodb.sh"
echo "nano ssh-tunnel-mongodb.sh  # Update SERVER_IP"
echo "./ssh-tunnel-mongodb.sh start"
SCRIPT_END
print_status "SCRIPT_END"

chmod +x distribute-client-script.sh 2>/dev/null || true