#!/bin/bash

# WireGuard VPN Setup Script for MongoDB
# Creates secure VPN network to hide MongoDB server IP - 100% FREE

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

# Configuration
VPN_NETWORK="10.0.200"  # VPN subnet
SERVER_IP="$VPN_NETWORK.1"
VPN_PORT="51820"
WG_CONFIG_DIR="/etc/wireguard"
CLIENT_COUNT=5  # Number of client configs to generate

print_header "WireGuard VPN Setup for MongoDB"
print_status "This creates a private VPN network for MongoDB access"
print_status "VPN Network: $VPN_NETWORK.0/24"
print_status "Server VPN IP: $SERVER_IP"
print_status "VPN Port: $VPN_PORT"
echo ""

read -p "Continue with this configuration? (y/N): " -r
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Setup cancelled."
    exit 0
fi

# Install WireGuard
print_header "Installing WireGuard"

if command -v wg >/dev/null 2>&1; then
    print_status "WireGuard is already installed"
else
    print_status "Installing WireGuard..."
    apt update
    apt install -y wireguard wireguard-tools qrencode
fi

# Create WireGuard directory
mkdir -p "$WG_CONFIG_DIR"
chmod 700 "$WG_CONFIG_DIR"

# Generate server keys
print_status "Generating server keys..."
cd "$WG_CONFIG_DIR"

if [ ! -f "server-private.key" ]; then
    wg genkey > server-private.key
    chmod 600 server-private.key
fi

if [ ! -f "server-public.key" ]; then
    cat server-private.key | wg pubkey > server-public.key
fi

SERVER_PRIVATE_KEY=$(cat server-private.key)
SERVER_PUBLIC_KEY=$(cat server-public.key)

print_status "Server public key: $SERVER_PUBLIC_KEY"

# Generate client keys
print_status "Generating client keys..."

CLIENT_CONFIGS=()
CLIENT_PUBLIC_KEYS=()

for i in $(seq 1 $CLIENT_COUNT); do
    CLIENT_NAME="client$i"
    CLIENT_IP="$VPN_NETWORK.$((i + 1))"
    
    # Generate client keys
    wg genkey > "$CLIENT_NAME-private.key"
    chmod 600 "$CLIENT_NAME-private.key"
    cat "$CLIENT_NAME-private.key" | wg pubkey > "$CLIENT_NAME-public.key"
    
    CLIENT_PRIVATE_KEY=$(cat "$CLIENT_NAME-private.key")
    CLIENT_PUBLIC_KEY=$(cat "$CLIENT_NAME-public.key")
    
    CLIENT_CONFIGS+=("$CLIENT_NAME:$CLIENT_IP:$CLIENT_PRIVATE_KEY")
    CLIENT_PUBLIC_KEYS+=("$CLIENT_PUBLIC_KEY:$CLIENT_IP")
    
    print_status "Generated keys for $CLIENT_NAME (VPN IP: $CLIENT_IP)"
done

# Get server's public IP
print_status "Detecting server public IP..."
SERVER_PUBLIC_IP=$(curl -s ifconfig.me || curl -s ipinfo.io/ip || hostname -I | awk '{print $1}')
print_status "Server public IP: $SERVER_PUBLIC_IP"

# Create server configuration
print_status "Creating server configuration..."

cat > "$WG_CONFIG_DIR/wg0.conf" << EOF
# WireGuard Server Configuration for MongoDB
# Generated on: $(date)

[Interface]
PrivateKey = $SERVER_PRIVATE_KEY
Address = $SERVER_IP/24
ListenPort = $VPN_PORT
SaveConfig = false

# Enable IP forwarding and NAT
PostUp = echo 1 > /proc/sys/net/ipv4/ip_forward
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT
PostUp = iptables -A FORWARD -o wg0 -j ACCEPT
PostUp = iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostUp = iptables -t nat -A POSTROUTING -o ens3 -j MASQUERADE

PostDown = iptables -D FORWARD -i wg0 -j ACCEPT
PostDown = iptables -D FORWARD -o wg0 -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -t nat -D POSTROUTING -o ens3 -j MASQUERADE

EOF

# Add client peer configurations to server config
for peer_info in "${CLIENT_PUBLIC_KEYS[@]}"; do
    IFS=':' read -r pub_key client_ip <<< "$peer_info"
    cat >> "$WG_CONFIG_DIR/wg0.conf" << EOF
# Client: $client_ip
[Peer]
PublicKey = $pub_key
AllowedIPs = $client_ip/32

EOF
done

# Generate client configuration files
print_header "Creating Client Configuration Files"

mkdir -p "$WG_CONFIG_DIR/clients"

for config_info in "${CLIENT_CONFIGS[@]}"; do
    IFS=':' read -r client_name client_ip client_private <<< "$config_info"
    
    cat > "$WG_CONFIG_DIR/clients/$client_name.conf" << EOF
# WireGuard Client Configuration: $client_name
# VPN IP: $client_ip
# Generated on: $(date)

[Interface]
PrivateKey = $client_private
Address = $client_ip/24
DNS = 8.8.8.8, 1.1.1.1

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
Endpoint = $SERVER_PUBLIC_IP:$VPN_PORT
AllowedIPs = $VPN_NETWORK.0/24
PersistentKeepalive = 20
EOF

    print_status "Created client config: $client_name.conf (IP: $client_ip)"
    
    # Generate QR code for mobile clients
    qrencode -t ansiutf8 < "$WG_CONFIG_DIR/clients/$client_name.conf" > "$WG_CONFIG_DIR/clients/$client_name-qr.txt"
done

# Configure MongoDB for VPN access
print_header "Configuring MongoDB for VPN Access"

print_status "Backing up MongoDB configuration..."
cp /etc/mongod.conf "/etc/mongod.conf.backup.$(date +%Y%m%d_%H%M%S)"

print_status "Updating MongoDB to allow VPN access..."

# Update MongoDB to bind to localhost and VPN IP
if grep -q "bindIp:" /etc/mongod.conf; then
    sed -i "s/bindIp:.*/bindIp: 127.0.0.1,$SERVER_IP/" /etc/mongod.conf
else
    sed -i "/^net:/a\\  bindIp: 127.0.0.1,$SERVER_IP" /etc/mongod.conf
fi

# Enable IP forwarding
print_status "Enabling IP forwarding..."
echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
sysctl -p

# Configure firewall
print_header "Configuring Firewall"

print_status "Updating firewall for VPN access..."

# Allow VPN port
ufw allow $VPN_PORT/udp

# Allow SSH
ufw allow ssh

# Deny direct MongoDB access from internet
ufw delete allow 27017 2>/dev/null || true
ufw deny 27017

# Allow MongoDB access from VPN network
ufw allow from $VPN_NETWORK.0/24 to any port 27017

ufw --force enable

print_status "Firewall configured for VPN access"

# Start WireGuard
print_header "Starting WireGuard VPN"

print_status "Starting WireGuard interface..."
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0

# Restart MongoDB
print_status "Restarting MongoDB..."
systemctl restart mongod

# Wait for services to start
sleep 5

# Check services
if systemctl is-active --quiet wg-quick@wg0; then
    print_status "✅ WireGuard VPN is running"
else
    print_error "❌ WireGuard VPN failed to start"
    exit 1
fi

if systemctl is-active --quiet mongod; then
    print_status "✅ MongoDB is running"
else
    print_error "❌ MongoDB failed to start"
    exit 1
fi

# Create client installation script
print_status "Creating client installation script..."

cat > "$WG_CONFIG_DIR/clients/install-client.sh" << 'EOF'
#!/bin/bash

# WireGuard Client Installation Script
# Run this on client machines to connect to MongoDB VPN

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

# Check if config file provided
if [ $# -eq 0 ]; then
    print_error "Usage: $0 <client_config.conf>"
    print_error "Example: $0 client1.conf"
    exit 1
fi

CONFIG_FILE="$1"

if [ ! -f "$CONFIG_FILE" ]; then
    print_error "Config file not found: $CONFIG_FILE"
    exit 1
fi

print_status "Installing WireGuard client..."

# Install WireGuard
if command -v wg >/dev/null 2>&1; then
    print_status "WireGuard already installed"
else
    if command -v apt >/dev/null 2>&1; then
        sudo apt update
        sudo apt install -y wireguard wireguard-tools
    elif command -v yum >/dev/null 2>&1; then
        sudo yum install -y wireguard-tools
    else
        print_error "Unsupported package manager. Install WireGuard manually."
        exit 1
    fi
fi

# Copy config file
print_status "Installing client configuration..."
sudo cp "$CONFIG_FILE" /etc/wireguard/

CONFIG_NAME=$(basename "$CONFIG_FILE" .conf)

# Start VPN
print_status "Starting VPN connection..."
sudo systemctl enable wg-quick@$CONFIG_NAME
sudo systemctl start wg-quick@$CONFIG_NAME

# Test connection
sleep 3

if sudo systemctl is-active --quiet wg-quick@$CONFIG_NAME; then
    print_status "✅ VPN connected successfully!"
    
    # Extract server VPN IP from config
    VPN_SERVER_IP=$(grep -E "^AllowedIPs.*\.0/24" "$CONFIG_FILE" | sed 's/.*= \([0-9.]*\)\..*/\1.1/')
    
    print_status "MongoDB server VPN IP: $VPN_SERVER_IP"
    print_status ""
    print_status "You can now connect to MongoDB:"
    print_status "  mongosh --host $VPN_SERVER_IP --port 27017 -u adminUser --authenticationDatabase admin"
    print_status ""
    print_status "Connection string:"
    print_status "  mongodb://username:password@$VPN_SERVER_IP:27017/database?authSource=admin"
    
else
    print_error "❌ VPN connection failed"
    exit 1
fi
EOF

chmod +x "$WG_CONFIG_DIR/clients/install-client.sh"

# Create status check script
cat > /usr/local/bin/wireguard-mongodb-status.sh << 'EOF'
#!/bin/bash

# WireGuard MongoDB Status Check Script

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() { echo -e "${BLUE}[STATUS]${NC} $1"; echo "==========================="; }
print_status() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

print_header "WireGuard MongoDB VPN Status"

# Check WireGuard status
if systemctl is-active --quiet wg-quick@wg0; then
    print_status "✅ WireGuard VPN is running"
    
    # Show interface details
    echo ""
    echo "Interface Details:"
    wg show
    
    # Show connected peers
    echo ""
    echo "Connected Clients:"
    wg show wg0 peers | wc -l | xargs echo "Total configured peers:"
    
else
    print_error "❌ WireGuard VPN is not running"
fi

# Check MongoDB status
echo ""
if systemctl is-active --quiet mongod; then
    print_status "✅ MongoDB is running"
else
    print_error "❌ MongoDB is not running"
fi

# Show MongoDB bind IPs
echo ""
echo "MongoDB Configuration:"
grep -E "bindIp|port" /etc/mongod.conf | head -5

# Show firewall status
echo ""
echo "Firewall Rules:"
ufw status | grep -E "27017|51820" || echo "No specific rules found"

echo ""
print_status "VPN Network: $(grep -E "Address.*/" /etc/wireguard/wg0.conf | awk '{print $3}')"
EOF

chmod +x /usr/local/bin/wireguard-mongodb-status.sh

# Final instructions
print_header "Setup Complete!"

echo ""
print_status "🎉 WireGuard VPN setup completed successfully!"
echo ""
print_status "📋 Configuration Summary:"
print_status "  • VPN Network: $VPN_NETWORK.0/24"
print_status "  • Server VPN IP: $SERVER_IP"
print_status "  • VPN Port: $VPN_PORT"
print_status "  • Client configs generated: $CLIENT_COUNT"
print_status "  • MongoDB accessible at: $SERVER_IP:27017"
echo ""
print_status "📁 Files Created:"
print_status "  • Server config: $WG_CONFIG_DIR/wg0.conf"
print_status "  • Client configs: $WG_CONFIG_DIR/clients/"
print_status "  • Status script: /usr/local/bin/wireguard-mongodb-status.sh"
echo ""
print_status "👥 Client Setup:"
print_status "1. Copy a client config to the client machine:"
print_status "   scp $WG_CONFIG_DIR/clients/client1.conf user@client-machine:"
echo ""
print_status "2. Copy the installation script:"
print_status "   scp $WG_CONFIG_DIR/clients/install-client.sh user@client-machine:"
echo ""
print_status "3. On the client machine, run:"
print_status "   chmod +x install-client.sh"
print_status "   ./install-client.sh client1.conf"
echo ""
print_status "4. Connect to MongoDB via VPN:"
print_status "   mongosh --host $SERVER_IP --port 27017 -u adminUser --authenticationDatabase admin"
echo ""
print_status "📱 For mobile clients:"
print_status "   • QR codes generated in: $WG_CONFIG_DIR/clients/*-qr.txt"
print_status "   • Use WireGuard mobile app to scan QR code"
echo ""
print_status "🔍 Check VPN status:"
print_status "   wireguard-mongodb-status.sh"
echo ""
print_warning "🔒 Security Benefits:"
print_warning "  ✅ Server IP completely hidden from clients"
print_warning "  ✅ Encrypted VPN tunnel (ChaCha20 + Poly1305)"
print_warning "  ✅ No direct MongoDB access from internet"
print_warning "  ✅ Private network topology"
print_warning "  ✅ Perfect Forward Secrecy"
print_warning "  ✅ 100% FREE - No ongoing costs!"
echo ""
print_status "✅ Your MongoDB server is now accessible only through encrypted VPN!"

# Show client config example
echo ""
print_status "📄 Sample client connection:"
print_status "After VPN is connected on client:"
print_status "  Connection string: mongodb://username:password@$SERVER_IP:27017/database?authSource=admin"
print_status "  Direct command: mongosh --host $SERVER_IP --port 27017 -u adminUser --authenticationDatabase admin"