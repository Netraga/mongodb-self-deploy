# MongoDB Self-Hosted Setup for Ubuntu 24

This repository contains automated scripts to set up a self-hosted MongoDB instance on Ubuntu 24 Server with proper security, monitoring, and backup configurations.

## Overview

- **MongoDB Version**: 7.0
- **Access Methods**: SSH Tunnel, WireGuard VPN, Nginx Proxy, or direct connection
- **Port**: 27017 (can be hidden behind proxy/VPN)
- **Authentication**: Enabled with SCRAM-SHA-256
- **IP Protection**: Multiple FREE methods to hide server IP (100% free alternatives to Atlas)

## Prerequisites

- Ubuntu 24.04 Server
- Root or sudo access
- Minimum 4GB RAM recommended
- At least 20GB available disk space

## Directory Structure

```
mongodb-setup/
├── scripts/
│   ├── install-mongodb.sh      # Main installation script
│   ├── create-users.sh         # User creation script
│   ├── configure-security.sh   # Security configuration
│   └── setup-firewall.sh       # Firewall configuration
├── configs/
│   ├── mongod.conf            # Initial MongoDB config
│   └── mongod-secure.conf     # Secure MongoDB config
├── users/
│   └── (user credential documentation)
├── backup/
│   ├── mongodb-backup.sh      # Backup script
│   ├── mongodb-restore.sh     # Restore script
│   └── backup-cron.txt        # Cron schedule example
├── monitoring/
│   └── zabbix-mongodb-template.sh  # Monitoring setup
└── README.md
```

## Installation Steps

### 1. Upload and Extract Files

```bash
# Upload the mongodb-setup folder to your server
scp -r mongodb-setup/ user@your-server:/home/user/

# SSH into your server
ssh user@your-server

# Navigate to the setup directory
cd mongodb-setup/scripts/
```

### 2. Make Scripts Executable

```bash
chmod +x *.sh
cd ../backup/
chmod +x *.sh
cd ../monitoring/
chmod +x *.sh
```

### 3. Run Installation

```bash
# Navigate to scripts directory
cd /path/to/mongodb-setup/scripts/

# Run as root or with sudo
sudo ./install-mongodb.sh
```

### 4. Create Environment File and Users

```bash
# Copy and customize environment file
cp .env.example .env
nano .env  # Edit with your actual values

# Create users (secure version)
sudo ./create-users-secure.sh .env
```

### 5. Enable Security

```bash
sudo ./configure-security.sh
```

### 6. Setup System Limits (IMPORTANT for Production)

```bash
sudo ./setup-systemd-limits.sh
```

### 7. Setup Firewall

```bash
sudo ./setup-firewall.sh

# To allow specific IPs (replace with your app server IPs)
sudo mongodb-allow-ip.sh 192.168.1.100
sudo mongodb-allow-ip.sh 10.0.0.0/24
```

### 8. Configure Log Rotation

```bash
sudo cp ../configs/logrotate-mongodb /etc/logrotate.d/mongodb
sudo logrotate -f /etc/logrotate.d/mongodb  # Test rotation
```

### 9. Optional: Enable SSL/TLS (Recommended for Production)

```bash
sudo ./setup-ssl.sh
# Then restart MongoDB with SSL config
sudo systemctl stop mongod
sudo cp /etc/mongod-ssl.conf /etc/mongod.conf
sudo systemctl start mongod
```

### 10. Optional: Setup IP Protection (FREE Methods)

Choose one method to hide your MongoDB server IP:

**Option A - SSH Tunnel (Easiest):**
```bash
sudo ./setup-ssh-tunnel.sh
```

**Option B - WireGuard VPN (Most Secure):**
```bash
sudo ./setup-wireguard-vpn.sh
```

**Option C - Nginx Reverse Proxy (Port Obfuscation):**
```bash
sudo ./setup-nginx-proxy.sh
```

### 11. Optional: Performance Tuning

```bash
sudo ./tune-performance.sh
sudo systemctl restart mongod
```

## User Configuration

The setup creates users based on your `.env` file configuration:

| User | Purpose | Environment Variable | Database | Roles |
|------|---------|---------------------|----------|-------|
| Admin User | Full admin access | `MONGODB_ADMIN_PASSWORD` | admin | root, userAdminAnyDatabase |
| Staging User | Staging environment | `MONGODB_STAGING_PASSWORD` | Set in `MONGODB_STAGING_DB` | readWrite, dbAdmin |
| Test User | Test environment | `MONGODB_TEST_PASSWORD` | Set in `MONGODB_TEST_DB` | readWrite, dbAdmin |
| Production User | Production environment | `MONGODB_PRODUCTION_PASSWORD` | Set in `MONGODB_PRODUCTION_DB` | readWrite, dbAdmin |
| Monitoring User | Monitoring (Zabbix/Grafana) | `MONGODB_MONITORING_PASSWORD` | admin | clusterMonitor, read |
| Backup User | Backup operations | `MONGODB_BACKUP_PASSWORD` | admin | backup, restore |
| Reporting User | Read-only reporting | `MONGODB_REPORTING_PASSWORD` | Various | read (specific DBs) |

**🔒 SECURITY**: All passwords are configured via environment variables in your `.env` file (not committed to git).

## Connection Methods

### Method 1: SSH Tunnel (100% Free - IP Hidden)

**Setup tunnel on client:**
```bash
# Copy client script from server
scp root@YOUR_SERVER_IP:/usr/local/share/mongodb-tunnel/ssh-tunnel-mongodb.sh .

# Edit script and update SERVER_IP
nano ssh-tunnel-mongodb.sh

# Start tunnel
./ssh-tunnel-mongodb.sh start

# Connect via localhost
mongosh -u adminUser -p 'YOUR_ADMIN_PASSWORD' --host localhost --port 27017 --authenticationDatabase admin
```

### Method 2: WireGuard VPN (100% Free - Most Secure)

**Setup VPN client:**
```bash
# Copy client config from server
scp root@YOUR_SERVER_IP:/etc/wireguard/clients/client1.conf .

# Install and connect
./install-client.sh client1.conf

# Connect via VPN IP
mongosh -u adminUser -p 'YOUR_ADMIN_PASSWORD' --host 10.0.200.1 --port 27017 --authenticationDatabase admin
```

### Method 3: Nginx Proxy (100% Free - Port Obfuscation)

**Connect to custom port:**
```bash
mongosh -u adminUser -p 'YOUR_ADMIN_PASSWORD' --host YOUR_SERVER_IP --port 9999 --authenticationDatabase admin
```

### Method 4: Direct Connection (Server IP Exposed)

**Standard connection:**
```bash
mongosh -u adminUser -p 'YOUR_ADMIN_PASSWORD' --host YOUR_SERVER_IP --port 27017 --authenticationDatabase admin
```

## Backup Configuration

### Manual Backup:
```bash
cd /path/to/mongodb-setup/backup/
sudo ./mongodb-backup-secure.sh /path/to/.env
```

### Automated Backup (Cron):
```bash
# Edit crontab
sudo crontab -e

# Add daily backup at 2 AM
0 2 * * * /path/to/mongodb-setup/backup/mongodb-backup-secure.sh /path/to/.env >> /var/log/mongodb-backup.log 2>&1
```

### Restore from Backup:
```bash
# List available backups
ls -lh /var/backups/mongodb/

# Restore specific backup
sudo ./mongodb-restore-secure.sh /path/to/.env mongodb_backup_20240101_020000.tar.gz

# Restore with dropping existing collections
sudo ./mongodb-restore-secure.sh /path/to/.env mongodb_backup_20240101_020000.tar.gz --drop
```

## Monitoring Setup

### For Zabbix:
```bash
cd /path/to/mongodb-setup/monitoring/
sudo ./zabbix-mongodb-template.sh
sudo systemctl restart zabbix-agent
```

### For Prometheus:
1. Install MongoDB exporter
2. Use the provided prometheus-mongodb-exporter.service file
3. Configure Prometheus to scrape the exporter

### For Grafana:
Import the provided `grafana-mongodb-dashboard.json` dashboard

## Security Considerations

1. **Firewall**: Only specific IPs are allowed to connect
2. **Authentication**: Always required after security setup
3. **Encryption**: Consider enabling TLS/SSL for production
4. **Passwords**: Change all default passwords immediately
5. **Monitoring**: Regularly check logs and metrics
6. **Updates**: Keep MongoDB updated with security patches

## Maintenance Commands

### Check MongoDB Status:
```bash
sudo systemctl status mongod
```

### View Logs:
```bash
sudo tail -f /var/log/mongodb/mongod.log
```

### Restart MongoDB:
```bash
sudo systemctl restart mongod
```

### Check Connections:
```bash
mongosh -u adminUser -p 'Admin#MongoDB2025!Secure' --authenticationDatabase admin --eval "db.serverStatus().connections"
```

## Troubleshooting

### MongoDB won't start:
```bash
# Check logs
sudo journalctl -u mongod -n 50

# Check config file syntax
mongod --config /etc/mongod.conf --test
```

### Connection refused:
1. Check if MongoDB is running: `sudo systemctl status mongod`
2. Verify firewall rules: `sudo ufw status`
3. Check bind IP in config: `grep bindIp /etc/mongod.conf`

### Authentication failed:
1. Verify credentials are correct
2. Check authenticationDatabase parameter
3. Ensure security is enabled in config

## Important Notes

1. **IP Protection**: Choose one of the FREE methods (SSH tunnel, WireGuard VPN, or Nginx proxy) to hide your server IP
2. **Firewall Configuration**: Different methods have different firewall requirements - follow the specific setup guide
3. **Zero Cost**: All IP protection methods are 100% FREE with no ongoing subscription costs
4. **Resources**: MongoDB can be memory intensive, monitor your server resources
5. **Backups**: Test your restore procedure regularly
6. **Security**: Never expose MongoDB directly to the internet without proper security
7. **Production Readiness**: Review PRODUCTION-CHECKLIST.md before going live
8. **SSL/TLS**: Strongly recommended for production environments
9. **Log Rotation**: Essential to prevent disk space issues

## Additional Documentation

- **FREE-IP-PROTECTION.md** - Complete guide for FREE methods to hide server IP (like Atlas)
- **PRODUCTION-CHECKLIST.md** - Complete production deployment checklist
- **MONGODB-COMPASS-GUIDE.md** - GUI client connection guide
- **SECURITY-GUIDE.md** - Comprehensive security documentation
- **SECURITY-AUDIT-CHECKLIST.md** - Security audit procedures

## Quick Health Check

After installation, verify everything is working:

```bash
# Check MongoDB status
sudo systemctl status mongod

# Verify authentication (use your actual admin password)
mongosh -u adminUser -p 'YOUR_ADMIN_PASSWORD' --authenticationDatabase admin --eval "db.adminCommand({ping: 1})"

# Check system limits
check-mongodb-limits.sh

# Check performance
mongodb-performance-check.sh

# Test backup
sudo /path/to/mongodb-setup/backup/mongodb-backup-secure.sh /path/to/.env
```

## Support

For MongoDB documentation: https://docs.mongodb.com/
For Ubuntu firewall: https://help.ubuntu.com/community/UFW