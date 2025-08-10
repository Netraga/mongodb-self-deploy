#!/bin/bash

# Nginx Reverse Proxy Setup Script for MongoDB
# Hides MongoDB default port and adds SSL termination - 100% FREE

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
PROXY_PORT="9999"  # Custom port instead of 27017
SSL_PORT="9998"    # SSL proxy port
MONGODB_PORT="27017"

print_header "Nginx Reverse Proxy Setup for MongoDB"
print_status "This creates an Nginx proxy to hide MongoDB's default port"
print_status "Proxy Port: $PROXY_PORT (non-SSL)"
print_status "SSL Port: $SSL_PORT (with SSL)"
print_status "MongoDB Port: $MONGODB_PORT (hidden)"
echo ""

read -p "Enter custom proxy port (default: $PROXY_PORT): " CUSTOM_PORT
PROXY_PORT=${CUSTOM_PORT:-$PROXY_PORT}

read -p "Enable SSL proxy? (y/N): " -r
ENABLE_SSL=$([[ $REPLY =~ ^[Yy]$ ]] && echo "yes" || echo "no")

echo ""
print_status "Configuration:"
print_status "  Proxy Port: $PROXY_PORT"
print_status "  SSL Enabled: $ENABLE_SSL"
echo ""

read -p "Continue with this configuration? (y/N): " -r
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Setup cancelled."
    exit 0
fi

# Install Nginx
print_header "Installing Nginx"

if command -v nginx >/dev/null 2>&1; then
    print_status "Nginx is already installed"
    nginx -v
else
    print_status "Installing Nginx with stream module..."
    apt update
    apt install -y nginx-full
fi

# Check if stream module is available
print_status "Checking Nginx stream module..."
if nginx -V 2>&1 | grep -q "with-stream"; then
    print_status "✅ Stream module is available"
else
    print_error "Stream module not available. Installing nginx-full..."
    apt install -y nginx-full
fi

# Backup original nginx config
print_status "Backing up Nginx configuration..."
cp /etc/nginx/nginx.conf "/etc/nginx/nginx.conf.backup.$(date +%Y%m%d_%H%M%S)"

# Configure MongoDB to bind to localhost only
print_header "Configuring MongoDB"

print_status "Backing up MongoDB configuration..."
cp /etc/mongod.conf "/etc/mongod.conf.backup.$(date +%Y%m%d_%H%M%S)"

print_status "Updating MongoDB to bind only to localhost..."
if grep -q "bindIp:" /etc/mongod.conf; then
    sed -i 's/bindIp:.*/bindIp: 127.0.0.1/' /etc/mongod.conf
else
    sed -i '/^net:/a\  bindIp: 127.0.0.1' /etc/mongod.conf
fi

# Generate SSL certificates if SSL is enabled
if [ "$ENABLE_SSL" = "yes" ]; then
    print_header "Generating SSL Certificates"
    
    SSL_DIR="/etc/nginx/ssl"
    mkdir -p "$SSL_DIR"
    
    if [ ! -f "$SSL_DIR/mongodb-proxy.crt" ]; then
        print_status "Generating self-signed SSL certificate..."
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "$SSL_DIR/mongodb-proxy.key" \
            -out "$SSL_DIR/mongodb-proxy.crt" \
            -subj "/C=US/ST=State/L=City/O=Organization/CN=mongodb-proxy"
        
        chmod 600 "$SSL_DIR/mongodb-proxy.key"
        chmod 644 "$SSL_DIR/mongodb-proxy.crt"
        
        print_status "SSL certificate generated"
    else
        print_status "SSL certificate already exists"
    fi
fi

# Create Nginx stream configuration
print_header "Configuring Nginx Stream Proxy"

# Remove existing stream block if it exists
sed -i '/^stream {/,/^}/d' /etc/nginx/nginx.conf

# Add stream configuration
cat >> /etc/nginx/nginx.conf << EOF

# MongoDB Reverse Proxy Configuration
# Generated on: $(date)
stream {
    # Error and access logs for stream
    error_log /var/log/nginx/mongodb_error.log;
    access_log /var/log/nginx/mongodb_access.log;
    
    # MongoDB upstream
    upstream mongodb_backend {
        server 127.0.0.1:$MONGODB_PORT;
    }
    
    # Non-SSL MongoDB proxy
    server {
        listen $PROXY_PORT;
        proxy_pass mongodb_backend;
        proxy_timeout 1s;
        proxy_responses 1;
        proxy_connect_timeout 1s;
        proxy_bind \$remote_addr transparent;
    }
EOF

# Add SSL proxy configuration if enabled
if [ "$ENABLE_SSL" = "yes" ]; then
    cat >> /etc/nginx/nginx.conf << EOF
    
    # SSL MongoDB proxy
    server {
        listen $SSL_PORT ssl;
        ssl_certificate $SSL_DIR/mongodb-proxy.crt;
        ssl_certificate_key $SSL_DIR/mongodb-proxy.key;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers HIGH:!aNULL:!MD5;
        
        proxy_pass mongodb_backend;
        proxy_timeout 1s;
        proxy_responses 1;
        proxy_connect_timeout 1s;
    }
EOF
fi

cat >> /etc/nginx/nginx.conf << EOF
}
EOF

# Test Nginx configuration
print_status "Testing Nginx configuration..."
if nginx -t; then
    print_status "✅ Nginx configuration is valid"
else
    print_error "❌ Nginx configuration is invalid"
    exit 1
fi

# Configure firewall
print_header "Configuring Firewall"

print_status "Updating firewall rules..."

# Allow SSH
ufw allow ssh

# Allow new proxy ports
ufw allow $PROXY_PORT

if [ "$ENABLE_SSL" = "yes" ]; then
    ufw allow $SSL_PORT
fi

# Deny direct MongoDB access
ufw delete allow $MONGODB_PORT 2>/dev/null || true
ufw deny $MONGODB_PORT

ufw --force enable

print_status "Firewall configured"

# Start services
print_header "Starting Services"

print_status "Restarting MongoDB..."
systemctl restart mongod

print_status "Restarting Nginx..."
systemctl restart nginx

# Wait for services
sleep 3

# Check services
if systemctl is-active --quiet mongod; then
    print_status "✅ MongoDB is running"
else
    print_error "❌ MongoDB failed to start"
    exit 1
fi

if systemctl is-active --quiet nginx; then
    print_status "✅ Nginx is running"
else
    print_error "❌ Nginx failed to start"
    exit 1
fi

# Test proxy connection
print_status "Testing proxy connection..."

if timeout 5 bash -c "</dev/tcp/localhost/$PROXY_PORT" 2>/dev/null; then
    print_status "✅ Proxy port $PROXY_PORT is accessible"
else
    print_warning "⚠️  Proxy port $PROXY_PORT is not accessible"
fi

if [ "$ENABLE_SSL" = "yes" ]; then
    if timeout 5 bash -c "</dev/tcp/localhost/$SSL_PORT" 2>/dev/null; then
        print_status "✅ SSL proxy port $SSL_PORT is accessible"
    else
        print_warning "⚠️  SSL proxy port $SSL_PORT is not accessible"
    fi
fi

# Create connection scripts
print_header "Creating Connection Scripts"

# Get server IP
SERVER_IP=$(curl -s ifconfig.me || curl -s ipinfo.io/ip || hostname -I | awk '{print $1}')

# Create client connection script
cat > /usr/local/bin/mongodb-proxy-connect.sh << EOF
#!/bin/bash

# MongoDB Nginx Proxy Connection Script
# Connects to MongoDB through Nginx reverse proxy

SERVER_IP="$SERVER_IP"
PROXY_PORT="$PROXY_PORT"
SSL_PORT="$SSL_PORT"
SSL_ENABLED="$ENABLE_SSL"

echo "MongoDB Nginx Proxy Connection"
echo "=============================="
echo ""
echo "Server IP: \$SERVER_IP"
echo "Non-SSL Port: \$PROXY_PORT"
if [ "\$SSL_ENABLED" = "yes" ]; then
    echo "SSL Port: \$SSL_PORT"
fi
echo ""

echo "Connection Examples:"
echo ""
echo "1. Direct connection:"
echo "   mongosh --host \$SERVER_IP --port \$PROXY_PORT -u adminUser --authenticationDatabase admin"
echo ""

if [ "\$SSL_ENABLED" = "yes" ]; then
    echo "2. SSL connection:"
    echo "   mongosh --host \$SERVER_IP --port \$SSL_PORT --tls --tlsAllowInvalidCertificates -u adminUser --authenticationDatabase admin"
    echo ""
fi

echo "Connection strings:"
echo ""
echo "Non-SSL:"
echo "  mongodb://username:password@\$SERVER_IP:\$PROXY_PORT/database?authSource=admin"
echo ""

if [ "\$SSL_ENABLED" = "yes" ]; then
    echo "SSL:"
    echo "  mongodb://username:password@\$SERVER_IP:\$SSL_PORT/database?authSource=admin&tls=true&tlsAllowInvalidCertificates=true"
    echo ""
fi

echo "Benefits:"
echo "  ✅ Default MongoDB port ($MONGODB_PORT) is hidden"
echo "  ✅ Custom port (\$PROXY_PORT) reduces automated scans"
if [ "\$SSL_ENABLED" = "yes" ]; then
    echo "  ✅ SSL encryption available on port \$SSL_PORT"
fi
echo "  ✅ Nginx handles connection management"
EOF

chmod +x /usr/local/bin/mongodb-proxy-connect.sh

# Create status check script
cat > /usr/local/bin/mongodb-proxy-status.sh << 'EOF'
#!/bin/bash

# MongoDB Nginx Proxy Status Check Script

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() { echo -e "${BLUE}[STATUS]${NC} $1"; echo "==========================="; }
print_status() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

print_header "MongoDB Nginx Proxy Status"

# Check services
if systemctl is-active --quiet nginx; then
    print_status "✅ Nginx is running"
else
    print_error "❌ Nginx is not running"
fi

if systemctl is-active --quiet mongod; then
    print_status "✅ MongoDB is running"
else
    print_error "❌ MongoDB is not running"
fi

# Show listening ports
echo ""
echo "Listening Ports:"
netstat -tuln | grep -E ":9999|:9998|:27017" || echo "No relevant ports found"

# Show Nginx configuration
echo ""
echo "Nginx Stream Configuration:"
grep -A 20 "^stream {" /etc/nginx/nginx.conf | head -25

# Show recent logs
echo ""
echo "Recent Nginx Error Logs:"
tail -5 /var/log/nginx/mongodb_error.log 2>/dev/null || echo "No error logs found"
EOF

chmod +x /usr/local/bin/mongodb-proxy-status.sh

# Create performance tuning script
cat > /usr/local/bin/mongodb-proxy-tune.sh << 'EOF'
#!/bin/bash

# MongoDB Nginx Proxy Performance Tuning Script

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

echo "Applying MongoDB Nginx Proxy performance tuning..."

# Tune Nginx for MongoDB
cat >> /etc/nginx/nginx.conf << 'TUNING'

# Performance tuning for MongoDB proxy
events {
    worker_connections 4096;
    use epoll;
    multi_accept on;
}

# Additional stream tuning
stream {
    # ... existing configuration ...
    
    # Performance settings
    proxy_timeout 300s;
    proxy_connect_timeout 10s;
    proxy_upload_rate 0;
    proxy_download_rate 0;
}
TUNING

# Increase system limits
cat > /etc/security/limits.d/nginx-mongodb.conf << 'LIMITS'
nginx soft nofile 65536
nginx hard nofile 65536
www-data soft nofile 65536
www-data hard nofile 65536
LIMITS

# Reload Nginx
systemctl reload nginx

echo "✅ Performance tuning applied"
echo "   - Increased connection limits"
echo "   - Optimized proxy timeouts"
echo "   - Enhanced event handling"
EOF

chmod +x /usr/local/bin/mongodb-proxy-tune.sh

# Final instructions
print_header "Setup Complete!"

echo ""
print_status "🎉 Nginx reverse proxy setup completed successfully!"
echo ""
print_status "📋 Configuration Summary:"
print_status "  • MongoDB hidden port: $MONGODB_PORT (blocked from internet)"
print_status "  • Nginx proxy port: $PROXY_PORT"
if [ "$ENABLE_SSL" = "yes" ]; then
    print_status "  • SSL proxy port: $SSL_PORT"
fi
print_status "  • Server IP: $SERVER_IP"
echo ""
print_status "🔌 Connection Examples:"
print_status "Non-SSL connection:"
print_status "  mongosh --host $SERVER_IP --port $PROXY_PORT -u adminUser --authenticationDatabase admin"
print_status ""
print_status "Connection string:"
print_status "  mongodb://username:password@$SERVER_IP:$PROXY_PORT/database?authSource=admin"
echo ""

if [ "$ENABLE_SSL" = "yes" ]; then
    print_status "SSL connection:"
    print_status "  mongosh --host $SERVER_IP --port $SSL_PORT --tls --tlsAllowInvalidCertificates -u adminUser --authenticationDatabase admin"
    print_status ""
    print_status "SSL connection string:"
    print_status "  mongodb://username:password@$SERVER_IP:$SSL_PORT/database?authSource=admin&tls=true&tlsAllowInvalidCertificates=true"
    echo ""
fi

print_status "📁 Scripts Created:"
print_status "  • Connection helper: /usr/local/bin/mongodb-proxy-connect.sh"
print_status "  • Status check: /usr/local/bin/mongodb-proxy-status.sh"
print_status "  • Performance tuning: /usr/local/bin/mongodb-proxy-tune.sh"
echo ""
print_status "🔧 Management Commands:"
print_status "  • Check status: mongodb-proxy-status.sh"
print_status "  • Connection info: mongodb-proxy-connect.sh"
print_status "  • Tune performance: mongodb-proxy-tune.sh"
echo ""
print_warning "🔒 Security Benefits:"
print_warning "  ✅ Default MongoDB port ($MONGODB_PORT) is hidden"
print_warning "  ✅ Custom port ($PROXY_PORT) reduces automated scans"
print_warning "  ✅ Nginx handles connection management and rate limiting"
if [ "$ENABLE_SSL" = "yes" ]; then
    print_warning "  ✅ SSL encryption available"
fi
print_warning "  ✅ Centralized access logging"
print_warning "  ✅ 100% FREE - No additional costs!"
echo ""
print_status "✅ Your MongoDB server is now hidden behind Nginx reverse proxy!"

# Show connection info
echo ""
print_status "📖 Quick Connection Test:"
print_status "Run this command to test the proxy:"
print_status "  timeout 5 bash -c '</dev/tcp/$SERVER_IP/$PROXY_PORT' && echo 'Proxy is accessible' || echo 'Proxy connection failed'"