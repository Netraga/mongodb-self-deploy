#!/bin/bash

# MongoDB SSL/TLS Configuration Script
# Sets up SSL/TLS encryption for MongoDB connections

set -euo pipefail

# Configuration
SSL_DIR="/etc/mongodb/ssl"
FQDN="${MONGODB_HOST:-YOUR_DOMAIN.example.com}"
VALIDITY_DAYS=365

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

print_status "Setting up SSL/TLS for MongoDB..."

# Create SSL directory
print_status "Creating SSL directory..."
mkdir -p "$SSL_DIR"
chmod 755 "$SSL_DIR"

# Generate Certificate Authority (CA)
print_status "Generating Certificate Authority..."
openssl req -x509 -new -nodes -days 3650 -newkey rsa:4096 \
    -keyout "$SSL_DIR/ca.key" \
    -out "$SSL_DIR/ca.crt" \
    -subj "/C=IN/ST=State/L=City/O=Organization/CN=MongoDB-CA"

# Generate server private key
print_status "Generating server private key..."
openssl genrsa -out "$SSL_DIR/mongodb.key" 4096

# Generate certificate signing request
print_status "Generating certificate signing request..."
openssl req -new -key "$SSL_DIR/mongodb.key" \
    -out "$SSL_DIR/mongodb.csr" \
    -subj "/C=IN/ST=State/L=City/O=Organization/CN=$FQDN"

# Create extensions file for SAN
cat > "$SSL_DIR/mongodb.ext" << EOF
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = $FQDN
DNS.2 = localhost
IP.1 = 127.0.0.1
EOF

# Generate server certificate
print_status "Generating server certificate..."
openssl x509 -req -in "$SSL_DIR/mongodb.csr" \
    -CA "$SSL_DIR/ca.crt" \
    -CAkey "$SSL_DIR/ca.key" \
    -CAcreateserial \
    -out "$SSL_DIR/mongodb.crt" \
    -days $VALIDITY_DAYS \
    -sha256 \
    -extfile "$SSL_DIR/mongodb.ext"

# Combine key and certificate for MongoDB
print_status "Creating MongoDB PEM file..."
cat "$SSL_DIR/mongodb.key" "$SSL_DIR/mongodb.crt" > "$SSL_DIR/mongodb.pem"

# Set proper permissions
print_status "Setting file permissions..."
chmod 600 "$SSL_DIR"/*.key "$SSL_DIR"/*.pem
chmod 644 "$SSL_DIR"/*.crt
chown -R mongodb:mongodb "$SSL_DIR"

# Create SSL-enabled MongoDB configuration
print_status "Creating SSL-enabled MongoDB configuration..."
cat > /etc/mongod-ssl.conf << EOF
# MongoDB configuration file with SSL/TLS enabled
# Configured for FQDN: $FQDN

# Where and how to store data
storage:
  dbPath: /var/lib/mongodb
  journal:
    enabled: true
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

# Network interfaces
net:
  port: 27017
  bindIp: 127.0.0.1,$FQDN
  maxIncomingConnections: 65536
  tls:
    mode: requireTLS
    certificateKeyFile: $SSL_DIR/mongodb.pem
    CAFile: $SSL_DIR/ca.crt
    allowConnectionsWithoutCertificates: true
    allowInvalidHostnames: false
    disabledProtocols: TLS1_0,TLS1_1
  
# Process management
processManagement:
  timeZoneInfo: /usr/share/zoneinfo
  fork: true
  pidFilePath: /var/run/mongodb/mongod.pid

# Security
security:
  authorization: enabled
  javascriptEnabled: true

# Operation profiling
operationProfiling:
  mode: off
  slowOpThresholdMs: 100

# Set parameter options
setParameter:
  enableLocalhostAuthBypass: false
  authenticationMechanisms: SCRAM-SHA-256
EOF

# Create client connection script
print_status "Creating client connection helper..."
cat > /usr/local/bin/mongodb-connect-ssl.sh << EOF
#!/bin/bash
# MongoDB SSL connection helper

USER=\${1:-adminUser}
DB=\${2:-admin}

echo "Connecting to MongoDB with SSL..."
echo "User: \$USER"
echo "Database: \$DB"

mongosh --tls \\
    --tlsCAFile $SSL_DIR/ca.crt \\
    --host $FQDN \\
    --port 27017 \\
    -u "\$USER" \\
    --authenticationDatabase admin \\
    "\$DB"
EOF

chmod +x /usr/local/bin/mongodb-connect-ssl.sh

# Create application connection string examples
print_status "Creating connection string examples..."
cat > "$SSL_DIR/connection-strings.txt" << EOF
MongoDB SSL/TLS Connection Strings
==================================

For Node.js/Python/Java applications:
mongodb://username:password@$FQDN:27017/database?authSource=admin&tls=true&tlsCAFile=/path/to/ca.crt

For applications without CA validation (development only):
mongodb://username:password@$FQDN:27017/database?authSource=admin&tls=true&tlsAllowInvalidCertificates=true

For mongosh command line:
mongosh --tls --tlsCAFile $SSL_DIR/ca.crt --host $FQDN --port 27017 -u username --authenticationDatabase admin

For MongoDB Compass:
1. Hostname: $FQDN
2. Port: 27017
3. Authentication: Username/Password
4. SSL: On
5. Certificate Authority: Upload ca.crt file

Copy CA certificate to client:
scp root@$FQDN:$SSL_DIR/ca.crt ./mongodb-ca.crt
EOF

# Create SSL test script
print_status "Creating SSL test script..."
cat > /usr/local/bin/test-mongodb-ssl.sh << 'EOF'
#!/bin/bash

echo "Testing MongoDB SSL/TLS connection..."

# Test TLS handshake
echo "1. Testing TLS handshake..."
timeout 5 openssl s_client -connect "$FQDN":27017 -CAfile /etc/mongodb/ssl/ca.crt < /dev/null

if [ $? -eq 0 ]; then
    echo "✓ TLS handshake successful"
else
    echo "✗ TLS handshake failed"
fi

# Test certificate validity
echo ""
echo "2. Checking certificate validity..."
openssl x509 -in /etc/mongodb/ssl/mongodb.crt -noout -dates

# Test MongoDB connection
echo ""
echo "3. Testing MongoDB connection..."
echo 'db.adminCommand({ping: 1})' | mongosh --tls --tlsCAFile /etc/mongodb/ssl/ca.crt --host "$FQDN" --quiet
EOF

chmod +x /usr/local/bin/test-mongodb-ssl.sh

print_status "SSL/TLS setup completed!"
print_status "Certificate files created in: $SSL_DIR"
print_status ""
print_warning "To enable SSL/TLS:"
print_warning "1. Stop MongoDB: systemctl stop mongod"
print_warning "2. Copy SSL config: cp /etc/mongod-ssl.conf /etc/mongod.conf"
print_warning "3. Start MongoDB: systemctl start mongod"
print_warning "4. Test SSL: test-mongodb-ssl.sh"
print_warning ""
print_status "CA certificate for clients: $SSL_DIR/ca.crt"
print_status "Connection helper: mongodb-connect-ssl.sh"