# Complete MongoDB Production Setup Guide with Automated Server Management

## Table of Contents

1. [Initial VPS Setup](#1-initial-vps-setup)
2. [MongoDB Installation & Configuration](#2-mongodb-installation--configuration)
3. [Automated Server Whitelist Management](#3-automated-server-whitelist-management)
4. [Security Hardening](#4-security-hardening)
5. [VPN Setup (Optional but Recommended)](#5-vpn-setup-optional-but-recommended)
6. [Data Migration](#6-data-migration)
7. [Monitoring & Alerting](#7-monitoring--alerting)
8. [Backup & Recovery](#8-backup--recovery)
9. [Performance Optimization](#9-performance-optimization)
10. [Maintenance & Troubleshooting](#10-maintenance--troubleshooting)

---

## 1. Initial VPS Setup

### 1.1 VPS Requirements

- **Minimum**: KVM 2 (4GB RAM, 2 vCPU, 80GB SSD)
- **Recommended**: KVM 4 (8GB RAM, 4 vCPU, 160GB SSD)
- **OS**: Ubuntu 22.04 LTS

### 1.2 Basic System Setup

```bash
# Login as root
ssh root@your-mongodb-vps-ip

# Update system
apt update && apt upgrade -y

# Set timezone
timedatectl set-timezone Your/Timezone

# Create administrative user
adduser mongodbadmin
usermod -aG sudo mongodbadmin

# Set up SSH key authentication for the new user
su - mongodbadmin
mkdir ~/.ssh
chmod 700 ~/.ssh
# Add your public key to:
nano ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
exit

# Disable root login and password authentication
nano /etc/ssh/sshd_config
# Set: PermitRootLogin no
# Set: PasswordAuthentication no
systemctl restart sshd

# Install essential packages
apt install -y curl wget gnupg lsb-release software-properties-common \
  htop iotop nethogs fail2ban ufw git build-essential python3-pip jq
```

### 1.3 System Optimization

```bash
# Create swap file (important for KVM 2)
fallocate -l 4G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab

# Optimize system limits
cat >> /etc/security/limits.conf << 'EOF'
* soft nofile 64000
* hard nofile 64000
* soft nproc 32000
* hard nproc 32000
mongodb soft nofile 64000
mongodb hard nofile 64000
mongodb soft nproc 32000
mongodb hard nproc 32000
EOF

# Kernel optimization for MongoDB
cat >> /etc/sysctl.conf << 'EOF'
# MongoDB Optimizations
vm.swappiness = 1
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
net.core.somaxconn = 4096
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_time = 120
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.tcp_max_tw_buckets = 720000
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_syncookies = 1
EOF

sysctl -p
```

---

## 2. MongoDB Installation & Configuration

### 2.1 Install MongoDB 7.0

```bash
# Import MongoDB GPG key
curl -fsSL https://pgp.mongodb.com/server-7.0.asc | \
   sudo gpg -o /usr/share/keyrings/mongodb-server-7.0.gpg --dearmor

# Add MongoDB repository
echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] \
  https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse" | \
  sudo tee /etc/apt/sources.list.d/mongodb-org-7.0.list

# Install MongoDB
apt update
apt install -y mongodb-org

# Hold packages to prevent accidental updates
echo "mongodb-org hold" | dpkg --set-selections
echo "mongodb-org-database hold" | dpkg --set-selections
echo "mongodb-org-server hold" | dpkg --set-selections
echo "mongodb-mongosh hold" | dpkg --set-selections
echo "mongodb-org-mongos hold" | dpkg --set-selections
echo "mongodb-org-tools hold" | dpkg --set-selections
```

### 2.2 Configure MongoDB

```bash
# Backup original config
cp /etc/mongod.conf /etc/mongod.conf.backup

# Create optimized configuration
cat > /etc/mongod.conf << 'EOF'
# MongoDB Configuration for Production
# Documentation: https://docs.mongodb.com/manual/reference/configuration-options/

# Data storage
storage:
  dbPath: /var/lib/mongodb
  journal:
    enabled: true
  directoryPerDB: true
  engine: wiredTiger
  wiredTiger:
    engineConfig:
      cacheSizeGB: 2.0  # Set to 50% of RAM (adjust based on your VPS)
      journalCompressor: snappy
      directoryForIndexes: false
    collectionConfig:
      blockCompressor: snappy
    indexConfig:
      prefixCompression: true

# Logging
systemLog:
  destination: file
  logAppend: true
  path: /var/log/mongodb/mongod.log
  logRotate: reopen
  verbosity: 0
  component:
    accessControl:
      verbosity: 1
    command:
      verbosity: 1

# Network
net:
  port: 27017
  bindIp: 127.0.0.1  # Will be updated by our script
  maxIncomingConnections: 500
  compression:
    compressors: snappy,zlib,zstd

# Process management
processManagement:
  timeZoneInfo: /usr/share/zoneinfo
  fork: true
  pidFilePath: /var/run/mongodb/mongod.pid

# Security (will be enabled after creating users)
security:
  authorization: disabled

# Operation profiling
operationProfiling:
  mode: slowOp
  slowOpThresholdMs: 100
  slowOpSampleRate: 1.0

# Additional settings
setParameter:
  enableLocalhostAuthBypass: true
EOF

# Start MongoDB
systemctl daemon-reload
systemctl start mongod
systemctl enable mongod
```

### 2.3 Create MongoDB Users

```bash
# Connect to MongoDB
mongosh

# Create admin user
use admin
db.createUser({
  user: "adminUser",
  pwd: passwordPrompt(),  // Will prompt for password
  roles: [
    { role: "userAdminAnyDatabase", db: "admin" },
    { role: "readWriteAnyDatabase", db: "admin" },
    { role: "dbAdminAnyDatabase", db: "admin" },
    { role: "clusterAdmin", db: "admin" },
    { role: "backup", db: "admin" },
    { role: "restore", db: "admin" }
  ]
})

// Create monitoring user
db.createUser({
  user: "monitorUser",
  pwd: passwordPrompt(),
  roles: [
    { role: "clusterMonitor", db: "admin" },
    { role: "read", db: "local" }
  ]
})

// Create backup user
db.createUser({
  user: "backupUser",
  pwd: passwordPrompt(),
  roles: [
    { role: "backup", db: "admin" },
    { role: "restore", db: "admin" }
  ]
})

// Create users for each app
use app1_db
db.createUser({
  user: "app1_user",
  pwd: passwordPrompt(),
  roles: [{ role: "readWrite", db: "app1_db" }]
})

use app2_db
db.createUser({
  user: "app2_user",
  pwd: passwordPrompt(),
  roles: [{ role: "readWrite", db: "app2_db" }]
})

use app3_db
db.createUser({
  user: "app3_user",
  pwd: passwordPrompt(),
  roles: [{ role: "readWrite", db: "app3_db" }]
})

exit
```

### 2.4 Enable Authentication

```bash
# Update MongoDB config to enable auth
sed -i 's/authorization: disabled/authorization: enabled/' /etc/mongod.conf

# Restart MongoDB
systemctl restart mongod
```

---

## 3. Automated Server Whitelist Management

### 3.1 Create Server Management System

```bash
# Create management directory
mkdir -p /opt/mongodb-manager/{scripts,configs,logs}
cd /opt/mongodb-manager

# Create server list file
cat > configs/allowed_servers.json << 'EOF'
{
  "servers": [
    {
      "name": "app1-server",
      "ip": "YOUR_APP1_SERVER_IP",
      "description": "App 1 Production Server",
      "added": "2024-01-01",
      "databases": ["app1_db"]
    },
    {
      "name": "app2-server",
      "ip": "YOUR_APP2_SERVER_IP",
      "description": "App 2 Production Server",
      "added": "2024-01-01",
      "databases": ["app2_db"]
    },
    {
      "name": "app3-server",
      "ip": "YOUR_APP3_SERVER_IP",
      "description": "App 3 Production Server",
      "added": "2024-01-01",
      "databases": ["app3_db"]
    }
  ]
}
EOF
```

### 3.2 Create Server Management Script

```bash
cat > scripts/manage_servers.sh << 'SCRIPT'
#!/bin/bash

# MongoDB Server Access Manager
# This script manages server whitelist for MongoDB access

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../configs/allowed_servers.json"
LOG_FILE="$SCRIPT_DIR/../logs/server_management.log"
MONGODB_IP=$(hostname -I | awk '{print $1}')
BACKUP_DIR="$SCRIPT_DIR/../configs/backups"

# Create necessary directories
mkdir -p "$BACKUP_DIR" "$(dirname "$LOG_FILE")"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Backup current configuration
backup_config() {
    local backup_file="$BACKUP_DIR/allowed_servers_$(date +%Y%m%d_%H%M%S).json"
    cp "$CONFIG_FILE" "$backup_file"
    log "Configuration backed up to $backup_file"
}

# List all allowed servers
list_servers() {
    echo "=== Allowed Servers ==="
    jq -r '.servers[] | "\(.name) | \(.ip) | \(.description) | \(.added)"' "$CONFIG_FILE" | \
        column -t -s '|' -N "NAME,IP,DESCRIPTION,ADDED"
}

# Add a new server
add_server() {
    local name=$1
    local ip=$2
    local description=$3
    local databases=$4
    
    if [[ -z "$name" || -z "$ip" || -z "$description" ]]; then
        echo "Usage: $0 add <name> <ip> <description> [databases]"
        echo "Example: $0 add app4-server 192.168.1.100 'App 4 Server' 'app4_db,shared_db'"
        return 1
    fi
    
    # Validate IP
    if ! [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        echo "Error: Invalid IP address format"
        return 1
    fi
    
    # Check if server already exists
    if jq -e ".servers[] | select(.ip == \"$ip\")" "$CONFIG_FILE" > /dev/null 2>&1; then
        echo "Error: Server with IP $ip already exists"
        return 1
    fi
    
    backup_config
    
    # Prepare databases array
    if [[ -n "$databases" ]]; then
        db_array=$(echo "$databases" | jq -R 'split(",") | map(gsub("^ +| +$";""))')
    else
        db_array='[]'
    fi
    
    # Add server to config
    jq ".servers += [{
        \"name\": \"$name\",
        \"ip\": \"$ip\",
        \"description\": \"$description\",
        \"added\": \"$(date +%Y-%m-%d)\",
        \"databases\": $db_array
    }]" "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    
    log "Added server: $name ($ip)"
    
    # Update firewall
    update_firewall
    
    echo "Server added successfully!"
}

# Remove a server
remove_server() {
    local identifier=$1
    
    if [[ -z "$identifier" ]]; then
        echo "Usage: $0 remove <name|ip>"
        return 1
    fi
    
    backup_config
    
    # Remove by name or IP
    jq "del(.servers[] | select(.name == \"$identifier\" or .ip == \"$identifier\"))" \
        "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    
    log "Removed server: $identifier"
    
    # Update firewall
    update_firewall
    
    echo "Server removed successfully!"
}

# Update firewall rules
update_firewall() {
    log "Updating firewall rules..."
    
    # Reset MongoDB-related rules
    ufw --force reset > /dev/null 2>&1
    
    # Default policies
    ufw default deny incoming > /dev/null 2>&1
    ufw default allow outgoing > /dev/null 2>&1
    
    # Allow SSH (important!)
    ufw allow 22/tcp > /dev/null 2>&1
    
    # Allow MongoDB from each server in the list
    while IFS= read -r ip; do
        ufw allow from "$ip" to any port 27017 > /dev/null 2>&1
        log "Allowed MongoDB access from $ip"
    done < <(jq -r '.servers[].ip' "$CONFIG_FILE")
    
    # Enable firewall
    ufw --force enable > /dev/null 2>&1
    
    # Update MongoDB bind IP
    update_mongodb_config
    
    log "Firewall rules updated"
}

# Update MongoDB configuration
update_mongodb_config() {
    local bind_ips="127.0.0.1,$MONGODB_IP"
    
    # Update MongoDB config file
    sed -i "s/bindIp:.*/bindIp: $bind_ips/" /etc/mongod.conf
    
    # Restart MongoDB
    systemctl restart mongod
    
    log "MongoDB configuration updated with bindIp: $bind_ips"
}

# Generate connection strings for all apps
generate_connection_strings() {
    echo "=== MongoDB Connection Strings ==="
    echo
    echo "MongoDB Host: $MONGODB_IP"
    echo "MongoDB Port: 27017"
    echo
    
    # Get unique databases
    local databases=$(jq -r '.servers[].databases[]?' "$CONFIG_FILE" | sort -u)
    
    if [[ -z "$databases" ]]; then
        databases="app1_db app2_db app3_db"
    fi
    
    for db in $databases; do
        echo "Database: $db"
        echo "Connection String: mongodb://${db%_db}_user:<password>@$MONGODB_IP:27017/$db?authSource=$db"
        echo
    done
}

# Check server access
check_access() {
    local test_ip=$1
    
    if [[ -z "$test_ip" ]]; then
        echo "Usage: $0 check <ip>"
        return 1
    fi
    
    if jq -e ".servers[] | select(.ip == \"$test_ip\")" "$CONFIG_FILE" > /dev/null 2>&1; then
        echo "✓ IP $test_ip is allowed to access MongoDB"
        local server_info=$(jq -r ".servers[] | select(.ip == \"$test_ip\") | \
            \"Name: \(.name)\nDescription: \(.description)\nDatabases: \(.databases | join(\", \"))\"" "$CONFIG_FILE")
        echo "$server_info"
    else
        echo "✗ IP $test_ip is NOT allowed to access MongoDB"
    fi
}

# Export configuration
export_config() {
    local export_file="mongodb_servers_export_$(date +%Y%m%d_%H%M%S).json"
    cp "$CONFIG_FILE" "$export_file"
    echo "Configuration exported to: $export_file"
}

# Import configuration
import_config() {
    local import_file=$1
    
    if [[ -z "$import_file" ]] || [[ ! -f "$import_file" ]]; then
        echo "Usage: $0 import <file>"
        return 1
    fi
    
    # Validate JSON
    if ! jq empty "$import_file" 2>/dev/null; then
        echo "Error: Invalid JSON file"
        return 1
    fi
    
    backup_config
    cp "$import_file" "$CONFIG_FILE"
    update_firewall
    
    echo "Configuration imported successfully!"
}

# Show usage
usage() {
    cat << EOF
MongoDB Server Access Manager

Usage: $0 <command> [arguments]

Commands:
    list                    List all allowed servers
    add <name> <ip> <desc>  Add a new server
    remove <name|ip>        Remove a server
    check <ip>              Check if an IP is allowed
    update                  Update firewall rules
    connections             Show current connections
    export                  Export configuration
    import <file>           Import configuration
    help                    Show this help message

Examples:
    $0 add app4-prod 192.168.1.100 "App 4 Production Server"
    $0 remove app4-prod
    $0 check 192.168.1.100

EOF
}

# Show current connections
show_connections() {
    echo "=== Current MongoDB Connections ==="
    ss -tn state established '( dport = :27017 or sport = :27017 )' | \
        grep -v "127.0.0.1" | awk 'NR>1 {print $4, $5}' | \
        column -t -N "LOCAL,REMOTE"
}

# Main script logic
case "$1" in
    list)
        list_servers
        ;;
    add)
        add_server "$2" "$3" "$4" "$5"
        ;;
    remove)
        remove_server "$2"
        ;;
    check)
        check_access "$2"
        ;;
    update)
        update_firewall
        ;;
    connections)
        show_connections
        ;;
    strings)
        generate_connection_strings
        ;;
    export)
        export_config
        ;;
    import)
        import_config "$2"
        ;;
    help|*)
        usage
        ;;
esac
SCRIPT

chmod +x scripts/manage_servers.sh
```

### 3.3 Create Quick Access Symlink

```bash
ln -s /opt/mongodb-manager/scripts/manage_servers.sh /usr/local/bin/mongodb-servers
```

---

## 4. Security Hardening

### 4.1 Set Up Fail2Ban for MongoDB

```bash
# Create MongoDB filter
cat > /etc/fail2ban/filter.d/mongodb-auth.conf << 'EOF'
[Definition]
failregex = ^.*authentication failed.*client:<HOST>.*$
            ^.*Failed to authenticate.*from client <HOST>.*$
ignoreregex =
EOF

# Create jail configuration
cat > /etc/fail2ban/jail.d/mongodb.conf << 'EOF'
[mongodb-auth]
enabled = true
filter = mongodb-auth
port = 27017
protocol = tcp
logpath = /var/log/mongodb/mongod.log
maxretry = 3
findtime = 600
bantime = 3600
action = iptables-multiport[name=mongodb, port="27017", protocol=tcp]
EOF

systemctl restart fail2ban
```

### 4.2 Enable MongoDB Auditing

```bash
# Add to MongoDB config
cat >> /etc/mongod.conf << 'EOF'

# Auditing
auditLog:
  destination: file
  format: JSON
  path: /var/log/mongodb/audit.json
  filter: '{
    "$or": [
      { "atype": { "$in": ["authenticate", "authCheck"] } },
      { "atype": "clientDisconnect" },
      { "param.command": { "$in": ["find", "insert", "update", "remove", "delete"] } }
    ]
  }'
EOF
```

### 4.3 Set Up Log Rotation

```bash
cat > /etc/logrotate.d/mongodb << 'EOF'
/var/log/mongodb/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 640 mongodb mongodb
    sharedscripts
    postrotate
        /bin/kill -SIGUSR1 $(cat /var/run/mongodb/mongod.pid 2>/dev/null) 2>/dev/null || true
    endscript
}

/var/log/mongodb/audit.json {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 640 mongodb mongodb
}
EOF
```

---

## 5. VPN Setup (Optional but Recommended)

### 5.1 Install WireGuard

```bash
# On MongoDB server and all app servers
apt install wireguard -y

# Generate keys on MongoDB server
cd /etc/wireguard
umask 077
wg genkey | tee mongodb-privatekey | wg pubkey > mongodb-publickey
```

### 5.2 Configure WireGuard on MongoDB Server

```bash
cat > /etc/wireguard/wg0.conf << 'EOF'
[Interface]
Address = 10.0.0.1/24
ListenPort = 51820
PrivateKey = <MONGODB_PRIVATE_KEY>
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

# App Server 1
[Peer]
PublicKey = <APP1_PUBLIC_KEY>
AllowedIPs = 10.0.0.2/32

# App Server 2
[Peer]
PublicKey = <APP2_PUBLIC_KEY>
AllowedIPs = 10.0.0.3/32

# App Server 3
[Peer]
PublicKey = <APP3_PUBLIC_KEY>
AllowedIPs = 10.0.0.4/32
EOF

# Enable and start WireGuard
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0
```

### 5.3 Update MongoDB to Listen on VPN Interface

```bash
# Update MongoDB config to listen on VPN IP
sed -i 's/bindIp:.*/bindIp: 127.0.0.1,10.0.0.1/' /etc/mongod.conf
systemctl restart mongod
```

---

## 6. Data Migration

### 6.1 Migration Script

```bash
cat > /opt/mongodb-manager/scripts/migrate_from_atlas.sh << 'SCRIPT'
#!/bin/bash

# MongoDB Atlas Migration Script

MIGRATION_DIR="/opt/mongodb-migration"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$MIGRATION_DIR/logs/migration_$TIMESTAMP.log"

# Create directories
mkdir -p "$MIGRATION_DIR/"{dumps,logs,configs}

# Logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Migration configuration
cat > "$MIGRATION_DIR/configs/migration_config.json" << 'EOF'
{
  "databases": [
    {
      "name": "app1_db",
      "atlas_uri": "mongodb+srv://user:pass@cluster.mongodb.net/app1_db",
      "local_db": "app1_db"
    },
    {
      "name": "app2_db",
      "atlas_uri": "mongodb+srv://user:pass@cluster.mongodb.net/app2_db",
      "local_db": "app2_db"
    },
    {
      "name": "app3_db",
      "atlas_uri": "mongodb+srv://user:pass@cluster.mongodb.net/app3_db",
      "local_db": "app3_db"
    }
  ]
}
EOF

echo "Please update the Atlas URIs in $MIGRATION_DIR/configs/migration_config.json"
echo "Then run: $0 start"

if [[ "$1" != "start" ]]; then
    exit 0
fi

# Load configuration
DATABASES=$(jq -c '.databases[]' "$MIGRATION_DIR/configs/migration_config.json")

# Perform migration
for db in $DATABASES; do
    name=$(echo "$db" | jq -r '.name')
    atlas_uri=$(echo "$db" | jq -r '.atlas_uri')
    local_db=$(echo "$db" | jq -r '.local_db')
    
    log "Starting migration for $name"
    
    # Create dump
    dump_path="$MIGRATION_DIR/dumps/${name}_$TIMESTAMP"
    log "Dumping from Atlas..."
    
    if mongodump --uri="$atlas_uri" --out="$dump_path" 2>&1 | tee -a "$LOG_FILE"; then
        log "Dump completed for $name"
        
        # Get dump size
        size=$(du -sh "$dump_path" | cut -f1)
        log "Dump size: $size"
        
        # Restore to local
        log "Restoring to local MongoDB..."
        if mongorestore \
            --host=localhost:27017 \
            --username=adminUser \
            --password="$ADMIN_PASSWORD" \
            --authenticationDatabase=admin \
            --db="$local_db" \
            --drop \
            "$dump_path/$name" 2>&1 | tee -a "$LOG_FILE"; then
            
            log "✓ Successfully migrated $name"
            
            # Verify document count
            local_count=$(mongosh --quiet --eval "
                db.getSiblingDB('$local_db').getCollectionNames().forEach(function(c) {
                    var count = db.getSiblingDB('$local_db')[c].countDocuments();
                    print(c + ': ' + count);
                })
            " mongodb://adminUser:$ADMIN_PASSWORD@localhost:27017/admin)
            
            log "Document counts:\n$local_count"
        else
            log "✗ Failed to restore $name"
        fi
    else
        log "✗ Failed to dump $name from Atlas"
    fi
    
    echo "---"
done

log "Migration completed!"
SCRIPT

chmod +x /opt/mongodb-manager/scripts/migrate_from_atlas.sh
```

---

## 7. Monitoring & Alerting

### 7.1 Install Monitoring Stack

```bash
# Install Prometheus Node Exporter
wget https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-amd64.tar.gz
tar xvfz node_exporter-1.7.0.linux-amd64.tar.gz
cp node_exporter-1.7.0.linux-amd64/node_exporter /usr/local/bin/
rm -rf node_exporter-1.7.0.linux-amd64*

# Create systemd service
cat > /etc/systemd/system/node_exporter.service << 'EOF'
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=nobody
Group=nogroup
Type=simple
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
EOF

# Install MongoDB Exporter
wget https://github.com/percona/mongodb_exporter/releases/download/v0.40.0/mongodb_exporter-0.40.0.linux-amd64.tar.gz
tar xvfz mongodb_exporter-0.40.0.linux-amd64.tar.gz
cp mongodb_exporter-0.40.0.linux-amd64/mongodb_exporter /usr/local/bin/
rm -rf mongodb_exporter-0.40.0.linux-amd64*

# Create MongoDB exporter service
cat > /etc/systemd/system/mongodb_exporter.service << 'EOF'
[Unit]
Description=MongoDB Exporter
After=network.target

[Service]
User=nobody
Group=nogroup
Type=simple
Environment="MONGODB_URI=mongodb://monitorUser:<PASSWORD>@localhost:27017/admin"
ExecStart=/usr/local/bin/mongodb_exporter --collect-all

[Install]
WantedBy=multi-user.target
EOF

# Start services
systemctl daemon-reload
systemctl enable --now node_exporter mongodb_exporter
```

### 7.2 Create Monitoring Script

```bash
cat > /opt/mongodb-manager/scripts/monitor.sh << 'SCRIPT'
#!/bin/bash

# MongoDB Health Monitor

# Configuration
WEBHOOK_URL=""  # Add Slack/Discord webhook
EMAIL_TO=""     # Add email for alerts
THRESHOLD_CPU=80
THRESHOLD_MEM=85
THRESHOLD_DISK=80
THRESHOLD_CONNECTIONS=400

# Check functions
check_mongodb_status() {
    if ! systemctl is-active --quiet mongod; then
        alert "CRITICAL: MongoDB is not running!"
        return 1
    fi
    return 0
}

check_disk_usage() {
    local usage=$(df -h /var/lib/mongodb | awk 'NR==2 {print $5}' | sed 's/%//')
    if [[ $usage -gt $THRESHOLD_DISK ]]; then
        alert "WARNING: Disk usage is at ${usage}%"
    fi
}

check_memory_usage() {
    local usage=$(free | grep Mem | awk '{print int($3/$2 * 100)}')
    if [[ $usage -gt $THRESHOLD_MEM ]]; then
        alert "WARNING: Memory usage is at ${usage}%"
    fi
}

check_connections() {
    local connections=$(mongosh --quiet --eval "db.serverStatus().connections.current" \
        mongodb://monitorUser:<PASSWORD>@localhost:27017/admin)
    if [[ $connections -gt $THRESHOLD_CONNECTIONS ]]; then
        alert "WARNING: High connection count: $connections"
    fi
}

check_replication_lag() {
    # If using replica set
    local lag=$(mongosh --quiet --eval "rs.printSlaveReplicationInfo()" \
        mongodb://monitorUser:<PASSWORD>@localhost:27017/admin 2>/dev/null | \
        grep "behind the primary" | awk '{print $1}')
    if [[ -n "$lag" && $lag -gt 10 ]]; then
        alert "WARNING: Replication lag: ${lag} seconds"
    fi
}

# Alert function
alert() {
    local message=$1
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message"
    
    # Send webhook if configured
    if [[ -n "$WEBHOOK_URL" ]]; then
        curl -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\"MongoDB Alert: $message\"}" \
            "$WEBHOOK_URL" 2>/dev/null
    fi
    
    # Send email if configured
    if [[ -n "$EMAIL_TO" ]]; then
        echo "$message" | mail -s "MongoDB Alert" "$EMAIL_TO"
    fi
}

# Performance metrics
get_metrics() {
    mongosh --quiet mongodb://monitorUser:<PASSWORD>@localhost:27017/admin << 'EOF'
    var status = db.serverStatus();
    print("=== MongoDB Metrics ===");
    print("Uptime: " + Math.floor(status.uptime/3600) + " hours");
    print("Connections: " + status.connections.current + "/" + status.connections.available);
    print("Operations/sec: " + JSON.stringify(status.opcounters));
    print("Network I/O: " + Math.round(status.network.bytesIn/1024/1024) + "MB in, " + 
          Math.round(status.network.bytesOut/1024/1024) + "MB out");
    
    // Memory stats
    var mem = status.mem;
    print("Memory: " + mem.resident + "MB resident, " + mem.virtual + "MB virtual");
    
    // Storage stats
    db.getSiblingDB("admin").runCommand({dbStats: 1, scale: 1024*1024}).databases.forEach(function(db) {
        print("Database " + db.name + ": " + Math.round(db.sizeOnDisk) + "MB");
    });
EOF
}

# Run checks
if [[ "$1" == "metrics" ]]; then
    get_metrics
else
    check_mongodb_status && {
        check_disk_usage
        check_memory_usage
        check_connections
        check_replication_lag
    }
fi
SCRIPT

chmod +x /opt/mongodb-manager/scripts/monitor.sh

# Add to crontab
(crontab -l 2>/dev/null; echo "*/5 * * * * /opt/mongodb-manager/scripts/monitor.sh") | crontab -
```

---

## 8. Backup & Recovery

### 8.1 Automated Backup System

```bash
cat > /opt/mongodb-manager/scripts/backup.sh << 'SCRIPT'
#!/bin/bash

# MongoDB Backup Script with Rotation and Encryption

# Configuration
BACKUP_BASE="/opt/mongodb-backups"
BACKUP_RETENTION_DAYS=7
BACKUP_RETENTION_WEEKS=4
BACKUP_RETENTION_MONTHS=3
ENCRYPTION_KEY=""  # Set your encryption key
S3_BUCKET=""       # Optional: S3 bucket for offsite backups
WEBHOOK_URL=""     # Optional: Notification webhook

# Paths
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="$BACKUP_BASE/daily"
BACKUP_PATH="$BACKUP_DIR/mongodb_backup_$TIMESTAMP"
LOG_FILE="$BACKUP_BASE/logs/backup_$(date +%Y%m%d).log"

# Create directories
mkdir -p "$BACKUP_DIR" "$BACKUP_BASE/"{weekly,monthly,logs}

# Logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Start backup
log "Starting MongoDB backup..."

# Backup all databases
if mongodump \
    --host=localhost:27017 \
    --username=backupUser \
    --password="$BACKUP_PASSWORD" \
    --authenticationDatabase=admin \
    --oplog \
    --gzip \
    --out="$BACKUP_PATH" 2>&1 | tee -a "$LOG_FILE"; then
    
    log "Backup completed successfully"
    
    # Get backup size
    SIZE=$(du -sh "$BACKUP_PATH" | cut -f1)
    log "Backup size: $SIZE"
    
    # Create archive
    ARCHIVE_NAME="mongodb_backup_$TIMESTAMP.tar.gz"
    cd "$BACKUP_DIR"
    tar -czf "$ARCHIVE_NAME" "mongodb_backup_$TIMESTAMP"
    rm -rf "mongodb_backup_$TIMESTAMP"
    
    # Encrypt if key is set
    if [[ -n "$ENCRYPTION_KEY" ]]; then
        log "Encrypting backup..."
        openssl enc -aes-256-cbc -salt -k "$ENCRYPTION_KEY" \
            -in "$ARCHIVE_NAME" -out "${ARCHIVE_NAME}.enc"
        rm "$ARCHIVE_NAME"
        ARCHIVE_NAME="${ARCHIVE_NAME}.enc"
    fi
    
    # Copy to weekly/monthly if needed
    DAY_OF_WEEK=$(date +%u)
    DAY_OF_MONTH=$(date +%d)
    
    if [[ $DAY_OF_WEEK -eq 7 ]]; then  # Sunday
        cp "$BACKUP_DIR/$ARCHIVE_NAME" "$BACKUP_BASE/weekly/"
        log "Created weekly backup"
    fi
    
    if [[ $DAY_OF_MONTH -eq 1 ]]; then  # First day of month
        cp "$BACKUP_DIR/$ARCHIVE_NAME" "$BACKUP_BASE/monthly/"
        log "Created monthly backup"
    fi
    
    # Upload to S3 if configured
    if [[ -n "$S3_BUCKET" ]]; then
        log "Uploading to S3..."
        aws s3 cp "$BACKUP_DIR/$ARCHIVE_NAME" "s3://$S3_BUCKET/mongodb-backups/daily/" \
            --storage-class STANDARD_IA
    fi
    
    # Cleanup old backups
    log "Cleaning up old backups..."
    find "$BACKUP_BASE/daily" -name "*.tar.gz*" -mtime +$BACKUP_RETENTION_DAYS -delete
    find "$BACKUP_BASE/weekly" -name "*.tar.gz*" -mtime +$((BACKUP_RETENTION_WEEKS * 7)) -delete
    find "$BACKUP_BASE/monthly" -name "*.tar.gz*" -mtime +$((BACKUP_RETENTION_MONTHS * 30)) -delete
    
    # Success notification
    notify "✅ MongoDB backup completed successfully. Size: $SIZE"
    
else
    log "Backup failed!"
    notify "❌ MongoDB backup failed! Check logs: $LOG_FILE"
    exit 1
fi

# Cleanup logs
find "$BACKUP_BASE/logs" -name "*.log" -mtime +30 -delete

log "Backup process completed"
SCRIPT

chmod +x /opt/mongodb-manager/scripts/backup.sh

# Schedule backups
cat > /etc/cron.d/mongodb-backup << 'EOF'
# Daily backup at 2 AM
0 2 * * * root /opt/mongodb-manager/scripts/backup.sh >> /opt/mongodb-backups/logs/cron.log 2>&1

# Test backup monthly
0 3 1 * * root /opt/mongodb-manager/scripts/restore_test.sh >> /opt/mongodb-backups/logs/restore_test.log 2>&1
EOF
```

### 8.2 Restore Script

```bash
cat > /opt/mongodb-manager/scripts/restore.sh << 'SCRIPT'
#!/bin/bash

# MongoDB Restore Script

BACKUP_BASE="/opt/mongodb-backups"
ENCRYPTION_KEY=""  # Same key used for encryption

# List available backups
list_backups() {
    echo "=== Available Backups ==="
    echo
    echo "Daily backups:"
    ls -lh "$BACKUP_BASE/daily/" | grep -E "\.tar\.gz(\.enc)?$"
    echo
    echo "Weekly backups:"
    ls -lh "$BACKUP_BASE/weekly/" | grep -E "\.tar\.gz(\.enc)?$"
    echo
    echo "Monthly backups:"
    ls -lh "$BACKUP_BASE/monthly/" | grep -E "\.tar\.gz(\.enc)?$"
}

# Restore function
restore_backup() {
    local backup_file=$1
    local target_db=$2
    
    if [[ ! -f "$backup_file" ]]; then
        echo "Error: Backup file not found: $backup_file"
        return 1
    fi
    
    # Create temp directory
    TEMP_DIR="/tmp/mongodb_restore_$$"
    mkdir -p "$TEMP_DIR"
    
    # Copy backup to temp
    cp "$backup_file" "$TEMP_DIR/"
    cd "$TEMP_DIR"
    
    # Decrypt if needed
    if [[ "$backup_file" == *.enc ]]; then
        echo "Decrypting backup..."
        openssl enc -aes-256-cbc -d -k "$ENCRYPTION_KEY" \
            -in "$(basename "$backup_file")" \
            -out "$(basename "$backup_file" .enc)"
        backup_file="$(basename "$backup_file" .enc)"
    else
        backup_file="$(basename "$backup_file")"
    fi
    
    # Extract
    echo "Extracting backup..."
    tar -xzf "$backup_file"
    
    # Find extracted directory
    DUMP_DIR=$(find . -type d -name "mongodb_backup_*" | head -1)
    
    if [[ -z "$DUMP_DIR" ]]; then
        echo "Error: Could not find backup data"
        return 1
    fi
    
    # Restore
    echo "Restoring database..."
    if [[ -n "$target_db" ]]; then
        # Restore specific database
        mongorestore \
            --host=localhost:27017 \
            --username=adminUser \
            --password="$ADMIN_PASSWORD" \
            --authenticationDatabase=admin \
            --db="$target_db" \
            --drop \
            "$DUMP_DIR/$target_db"
    else
        # Restore all databases
        mongorestore \
            --host=localhost:27017 \
            --username=adminUser \
            --password="$ADMIN_PASSWORD" \
            --authenticationDatabase=admin \
            --drop \
            "$DUMP_DIR"
    fi
    
    # Cleanup
    cd /
    rm -rf "$TEMP_DIR"
    
    echo "Restore completed!"
}

# Main logic
case "$1" in
    list)
        list_backups
        ;;
    restore)
        if [[ -z "$2" ]]; then
            echo "Usage: $0 restore <backup_file> [database]"
            exit 1
        fi
        restore_backup "$2" "$3"
        ;;
    *)
        echo "Usage: $0 {list|restore}"
        echo "  list              - List available backups"
        echo "  restore <file>    - Restore from backup file"
        exit 1
        ;;
esac
SCRIPT

chmod +x /opt/mongodb-manager/scripts/restore.sh
```

---

## 9. Performance Optimization

### 9.1 Index Management Script

```bash
cat > /opt/mongodb-manager/scripts/index_manager.sh << 'SCRIPT'
#!/bin/bash

# MongoDB Index Manager

# Analyze indexes
analyze_indexes() {
    mongosh --quiet mongodb://adminUser:$ADMIN_PASSWORD@localhost:27017/admin << 'EOF'
    // Get all databases
    var dbs = db.adminCommand('listDatabases').databases;
    
    dbs.forEach(function(database) {
        if (database.name !== 'local' && database.name !== 'config') {
            print("\n=== Database: " + database.name + " ===");
            var db = db.getSiblingDB(database.name);
            
            // Get all collections
            var collections = db.getCollectionNames();
            
            collections.forEach(function(collection) {
                var coll = db.getCollection(collection);
                var indexes = coll.getIndexes();
                var stats = coll.stats();
                
                print("\nCollection: " + collection);
                print("Document count: " + coll.countDocuments());
                print("Total size: " + (stats.size / 1024 / 1024).toFixed(2) + " MB");
                print("Average document size: " + (stats.avgObjSize / 1024).toFixed(2) + " KB");
                print("\nIndexes:");
                
                indexes.forEach(function(idx) {
                    print("  - " + idx.name + ": " + JSON.stringify(idx.key));
                    
                    // Get index usage stats
                    var indexStats = coll.aggregate([
                        { $indexStats: {} },
                        { $match: { name: idx.name } }
                    ]).toArray();
                    
                    if (indexStats.length > 0) {
                        var usage = indexStats[0].accesses.ops;
                        print("    Usage: " + usage + " operations");
                        if (usage === 0 && idx.name !== "_id_") {
                            print("    ⚠️  WARNING: Unused index");
                        }
                    }
                });
            });
        }
    });
EOF
}

# Suggest missing indexes based on slow queries
suggest_indexes() {
    echo "=== Analyzing slow queries for index suggestions ==="
    
    mongosh --quiet mongodb://adminUser:$ADMIN_PASSWORD@localhost:27017/admin << 'EOF'
    // Enable profiling temporarily
    var dbs = db.adminCommand('listDatabases').databases;
    
    dbs.forEach(function(database) {
        if (database.name !== 'local' && database.name !== 'config') {
            var db = db.getSiblingDB(database.name);
            
            // Get slow queries from system.profile
            var slowQueries = db.system.profile.find({
                millis: { $gt: 100 },
                command: { $exists: true }
            }).limit(100).toArray();
            
            var indexSuggestions = {};
            
            slowQueries.forEach(function(query) {
                if (query.command.filter) {
                    var filter = query.command.filter;
                    var fields = Object.keys(filter);
                    var key = fields.sort().join("_");
                    
                    if (!indexSuggestions[key]) {
                        indexSuggestions[key] = {
                            fields: fields,
                            count: 0,
                            totalTime: 0,
                            collection: query.ns.split('.')[1]
                        };
                    }
                    
                    indexSuggestions[key].count++;
                    indexSuggestions[key].totalTime += query.millis;
                }
            });
            
            // Print suggestions
            print("\nDatabase: " + database.name);
            Object.keys(indexSuggestions).forEach(function(key) {
                var suggestion = indexSuggestions[key];
                if (suggestion.count > 5) {  // Only suggest if pattern appears frequently
                    print("\nSuggested index for collection '" + suggestion.collection + "':");
                    print("Fields: " + suggestion.fields.join(", "));
                    print("Would improve " + suggestion.count + " queries");
                    print("Total time spent: " + suggestion.totalTime + "ms");
                    
                    // Generate index creation command
                    var indexKey = {};
                    suggestion.fields.forEach(function(field) {
                        indexKey[field] = 1;
                    });
                    print("Create with: db." + suggestion.collection + 
                          ".createIndex(" + JSON.stringify(indexKey) + ")");
                }
            });
        }
    });
EOF
}

# Main menu
case "$1" in
    analyze)
        analyze_indexes
        ;;
    suggest)
        suggest_indexes
        ;;
    *)
        echo "Usage: $0 {analyze|suggest}"
        echo "  analyze  - Analyze existing indexes"
        echo "  suggest  - Suggest new indexes based on query patterns"
        ;;
esac
SCRIPT

chmod +x /opt/mongodb-manager/scripts/index_manager.sh
```

### 9.2 Performance Tuning Script

```bash
cat > /opt/mongodb-manager/scripts/tune_performance.sh << 'SCRIPT'
#!/bin/bash

# MongoDB Performance Tuning Script

# Get system info
TOTAL_RAM=$(free -m | awk '/^Mem:/{print $2}')
CPU_CORES=$(nproc)
MONGODB_CACHE_SIZE=$(echo "scale=1; $TOTAL_RAM * 0.5 / 1024" | bc)

echo "=== System Information ==="
echo "Total RAM: ${TOTAL_RAM}MB"
echo "CPU Cores: $CPU_CORES"
echo "Recommended WiredTiger Cache: ${MONGODB_CACHE_SIZE}GB"
echo

# Update MongoDB cache size
echo "Updating MongoDB cache size..."
sed -i "s/cacheSizeGB:.*/cacheSizeGB: $MONGODB_CACHE_SIZE/" /etc/mongod.conf

# Optimize read ahead for SSDs
echo "Optimizing read-ahead settings..."
for device in $(lsblk -d -o NAME,ROTA | grep -E "0$" | awk '{print $1}'); do
    echo 8 > /sys/block/$device/queue/read_ahead_kb
    echo "Set read-ahead to 8KB for /dev/$device (SSD)"
done

# Set CPU governor to performance
if command -v cpupower &> /dev/null; then
    cpupower frequency-set -g performance
    echo "Set CPU governor to performance mode"
fi

# Disable transparent huge pages
cat > /etc/systemd/system/disable-transparent-huge-pages.service << 'EOF'
[Unit]
Description=Disable Transparent Huge Pages (THP)
DefaultDependencies=no
After=sysinit.target local-fs.target
Before=mongod.service

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo never | tee /sys/kernel/mm/transparent_hugepage/enabled > /dev/null'
ExecStart=/bin/sh -c 'echo never | tee /sys/kernel/mm/transparent_hugepage/defrag > /dev/null'

[Install]
WantedBy=basic.target
EOF

systemctl daemon-reload
systemctl enable disable-transparent-huge-pages
systemctl start disable-transparent-huge-pages

# NUMA optimization
if command -v numactl &> /dev/null; then
    echo "NUMA hardware detected. Updating MongoDB service..."
    mkdir -p /etc/systemd/system/mongod.service.d
    cat > /etc/systemd/system/mongod.service.d/numa.conf << 'EOF'
[Service]
ExecStart=
ExecStart=/usr/bin/numactl --interleave=all /usr/bin/mongod --config /etc/mongod.conf
EOF
    systemctl daemon-reload
fi

echo "Performance tuning completed. Restart MongoDB to apply changes:"
echo "systemctl restart mongod"
SCRIPT

chmod +x /opt/mongodb-manager/scripts/tune_performance.sh
```

---

## 10. Maintenance & Troubleshooting

### 10.1 Health Check Dashboard

```bash
cat > /opt/mongodb-manager/scripts/dashboard.sh << 'SCRIPT'
#!/bin/bash

# MongoDB Health Dashboard

clear

while true; do
    echo "=== MongoDB Health Dashboard ==="
    echo "Time: $(date)"
    echo
    
    # MongoDB Status
    if systemctl is-active --quiet mongod; then
        echo "MongoDB Status: ✅ Running"
    else
        echo "MongoDB Status: ❌ Stopped"
    fi
    
    # System Resources
    echo
    echo "=== System Resources ==="
    echo "CPU Usage: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}')%"
    echo "Memory: $(free -h | awk '/^Mem:/ {print $3 " / " $2 " (" int($3/$2 * 100) "%)"}')"
    echo "Disk (/var/lib/mongodb): $(df -h /var/lib/mongodb | awk 'NR==2 {print $3 " / " $2 " (" $5 ")"}')"
    
    # MongoDB Metrics
    echo
    echo "=== MongoDB Metrics ==="
    mongosh --quiet --eval '
        var status = db.serverStatus();
        print("Connections: " + status.connections.current + " / " + status.connections.available);
        print("Operations/sec: " + JSON.stringify(status.opcounters));
        print("Uptime: " + Math.floor(status.uptime/3600) + " hours");
    ' mongodb://monitorUser:<PASSWORD>@localhost:27017/admin 2>/dev/null || echo "Unable to fetch MongoDB metrics"
    
    # Active connections by IP
    echo
    echo "=== Active Connections ==="
    ss -tn state established '( dport = :27017 )' | awk 'NR>1 {print $5}' | \
        cut -d: -f1 | sort | uniq -c | sort -rn | head -5
    
    # Recent errors
    echo
    echo "=== Recent Errors (last 5) ==="
    grep -i error /var/log/mongodb/mongod.log | tail -5
    
    echo
    echo "Press Ctrl+C to exit. Refreshing in 10 seconds..."
    sleep 10
    clear
done
SCRIPT

chmod +x /opt/mongodb-manager/scripts/dashboard.sh
```

### 10.2 Troubleshooting Guide

```bash
cat > /opt/mongodb-manager/TROUBLESHOOTING.md << 'EOF'
# MongoDB Troubleshooting Guide

## Common Issues and Solutions

### 1. MongoDB Won't Start

**Check logs:**
```bash
tail -100 /var/log/mongodb/mongod.log
journalctl -u mongod -n 50
```

**Common causes:**

- Disk full: `df -h`
- Permission issues: `ls -la /var/lib/mongodb`
- Port already in use: `netstat -tlnp | grep 27017`
- Configuration error: `mongod --config /etc/mongod.conf --test`

### 2. Authentication Failed

**Verify user exists:**

```bash
mongosh -u adminUser -p --authenticationDatabase admin
db.system.users.find().pretty()
```

**Reset password:**

```bash
# Stop MongoDB
systemctl stop mongod

# Start without auth
mongod --dbpath /var/lib/mongodb --noauth

# In another terminal
mongosh
use admin
db.updateUser("adminUser", {pwd: "newPassword"})
```

### 3. High Memory Usage

**Check cache size:**

```bash
mongosh -u adminUser -p --authenticationDatabase admin
db.serverStatus().wiredTiger.cache
```

**Adjust cache:**

```bash
# Edit /etc/mongod.conf
# storage.wiredTiger.engineConfig.cacheSizeGB
```

### 4. Slow Queries

**Enable profiling:**

```javascript
db.setProfilingLevel(1, { slowms: 100 })
db.system.profile.find().limit(5).sort({ ts: -1 }).pretty()
```

**Check missing indexes:**

```bash
/opt/mongodb-manager/scripts/index_manager.sh suggest
```

### 5. Connection Refused

**Check firewall:**

```bash
ufw status
iptables -L -n | grep 27017
```

**Verify MongoDB is listening:**

```bash
netstat -tlnp | grep mongod
```

**Check bind IP:**

```bash
grep bindIp /etc/mongod.conf
```

### 6. Disk Space Issues

**Find large collections:**

```javascript
db.adminCommand("listDatabases").databases.forEach(function(d) {
    db = db.getSiblingDB(d.name);
    db.getCollectionNames().forEach(function(c) {
        var stats = db[c].stats();
        print(d.name + "." + c + ": " + (stats.size/1024/1024).toFixed(2) + "MB");
    });
});
```

**Compact database:**

```javascript
db.runCommand({ compact: 'collection_name' })
```

### 7. Backup Restoration Issues

**Test restore to different database:**

```bash
mongorestore --db test_restore dump/original_db
```

**Verify backup integrity:**

```bash
tar -tzf backup.tar.gz | head -20
```

## Emergency Procedures

### Complete System Recovery

1. **Boot from recovery mode**
2. **Check filesystem:**

   ```bash
   fsck -y /dev/vda1
   ```

3. **Restore from backup:**

   ```bash
   /opt/mongodb-manager/scripts/restore.sh restore /path/to/backup.tar.gz
   ```

### Performance Emergency

1. **Kill long-running queries:**

   ```javascript
   db.currentOp().inprog.forEach(function(op) {
       if (op.secs_running > 300) db.killOp(op.opid);
   });
   ```

2. **Restart with minimal config:**

   ```bash
   systemctl stop mongod
   mongod --config /etc/mongod.conf.minimal
   ```

## Monitoring Commands

```bash
# Real-time operations
mongostat -u monitorUser -p <password> --authenticationDatabase admin

# Top-like interface
mongotop -u monitorUser -p <password> --authenticationDatabase admin

# Connection details
mongosh -u adminUser -p --authenticationDatabase admin --eval "db.currentOp()"

# Database sizes
mongosh -u adminUser -p --authenticationDatabase admin --eval "db.adminCommand('listDatabases')"
```

EOF

```

### 10.3 Quick Management Commands

```bash
# Create command aliases
cat >> /root/.bashrc << 'EOF'

# MongoDB Management Aliases
alias mongodb-status='systemctl status mongod'
alias mongodb-restart='systemctl restart mongod'
alias mongodb-logs='tail -f /var/log/mongodb/mongod.log'
alias mongodb-shell='mongosh -u adminUser -p --authenticationDatabase admin'
alias mongodb-servers='/opt/mongodb-manager/scripts/manage_servers.sh'
alias mongodb-backup='/opt/mongodb-manager/scripts/backup.sh'
alias mongodb-monitor='/opt/mongodb-manager/scripts/monitor.sh'
alias mongodb-dashboard='/opt/mongodb-manager/scripts/dashboard.sh'
alias mongodb-connections='ss -tn state established "( dport = :27017 )" | grep -v 127.0.0.1'

# Quick stats function
mongodb-stats() {
    echo "=== MongoDB Quick Stats ==="
    mongosh --quiet -u monitorUser -p $MONITOR_PASSWORD --authenticationDatabase admin --eval '
        var s = db.serverStatus();
        print("Uptime: " + Math.floor(s.uptime/3600) + " hours");
        print("Current connections: " + s.connections.current);
        print("Available connections: " + s.connections.available);
        print("Total operations: " + (s.opcounters.insert + s.opcounters.query + s.opcounters.update + s.opcounters.delete));
    '
}
EOF
```

---

## Quick Start Summary

After completing the setup, here's how to manage your MongoDB:

### Adding a New Server

```bash
mongodb-servers add app4-prod 192.168.1.100 "App 4 Production Server"
```

### Checking Server Access

```bash
mongodb-servers list
mongodb-servers check 192.168.1.100
```

### Monitoring Health

```bash
mongodb-dashboard  # Real-time dashboard
mongodb-monitor    # Run health checks
```

### Creating Backups

```bash
mongodb-backup     # Manual backup
```

### Connection Strings for Apps

```javascript
// Format for each app
mongodb://app_user:password@YOUR_MONGODB_IP:27017/app_db?authSource=app_db

// With connection pooling
const MongoClient = require('mongodb').MongoClient;
const options = {
    maxPoolSize: 10,
    minPoolSize: 2,
    maxIdleTimeMS: 10000,
    serverSelectionTimeoutMS: 5000,
    socketTimeoutMS: 45000,
};
```

## Security Checklist

- [ ] Changed all default passwords
- [ ] Firewall configured and tested
- [ ] MongoDB authentication enabled
- [ ] Fail2ban configured
- [ ] Backup encryption enabled
- [ ] Monitoring alerts configured
- [ ] VPN configured (optional)
- [ ] SSL/TLS enabled (optional)
- [ ] Audit logging enabled
- [ ] Regular security updates scheduled

Remember to test everything thoroughly before switching your production apps!
Copilots
