# 🚀 MongoDB Quick Start Guide

## One-Command Installation

### For Ubuntu 24.04 Servers

```bash
# Clone and install in one command
curl -fsSL https://raw.githubusercontent.com/yourusername/mongodb-setup/main/quick-install.sh | sudo bash
```

**OR** manually:

```bash
# 1. Clone repository
git clone https://github.com/yourusername/mongodb-setup.git
cd mongodb-setup

# 2. Make executable and run
chmod +x install.sh
sudo ./install.sh
```

## Installation Options

### Interactive Installation (Recommended)
```bash
sudo ./install.sh
```
- Prompts for domain, SSL, monitoring, etc.
- Safe defaults for all options
- Full configuration control

### Unattended Installation
```bash
sudo ./install.sh --unattended --domain=db.example.com --ssl
```
- No user interaction required
- Perfect for automation/scripts
- Uses sensible defaults

### Advanced Options
```bash
sudo ./install.sh \
    --domain=db.example.com \
    --ssl \
    --monitoring \
    --no-firewall \
    --unattended
```

## What Gets Installed

### ✅ Core Components
- **MongoDB 7.0** - Latest stable version
- **Authentication** - Secure user accounts with strong passwords
- **SSL/TLS** - Optional encryption (recommended)
- **Firewall** - UFW protection for port 27017
- **System Optimization** - Performance tuning and limits

### ✅ Security Features
- **Auto-generated passwords** - Cryptographically secure
- **Least privilege users** - Application users limited to specific databases
- **Environment variables** - No hardcoded credentials
- **Security audit tools** - Automated security checking

### ✅ Operational Tools
- **Automated backups** - Daily backups with 7-day retention
- **Log rotation** - Prevents disk space issues
- **Monitoring templates** - Zabbix/Grafana ready
- **Performance tools** - Real-time stats and optimization

## Quick Commands

### After Installation

```bash
# Check status
sudo systemctl status mongod

# Connect as admin
mongosh -u adminUser --authenticationDatabase admin

# Run security audit
cd /path/to/mongodb-setup/scripts
sudo ./security-audit.sh ../.env

# View credentials
cat .env
```

### Allow Application Access

```bash
# Allow specific IP to connect
sudo ./scripts/mongodb-allow-ip.sh 192.168.1.100

# Allow subnet
sudo ./scripts/mongodb-allow-ip.sh 10.0.0.0/24
```

### Backup & Restore

```bash
# Manual backup
sudo ./backup/mongodb-backup-secure.sh .env

# Restore backup
sudo ./backup/mongodb-restore-secure.sh .env backup_file.tar.gz
```

## Connection Examples

### From Application
```bash
# Staging environment
mongodb://stagingUser:PASSWORD@your-domain.com:27017/yourapp_staging?authSource=admin

# With SSL
mongodb://stagingUser:PASSWORD@your-domain.com:27017/yourapp_staging?authSource=admin&tls=true
```

### MongoDB Compass
```
Host: your-domain.com
Port: 27017
Authentication: Username/Password
Username: adminUser
Password: [from .env file]
Auth Database: admin
```

## File Locations

### Important Files
- **Configuration**: `/etc/mongod.conf`
- **Environment**: `./env` (keep secure!)
- **Logs**: `/var/log/mongodb/mongod.log`
- **Data**: `/var/lib/mongodb`
- **Backups**: `/var/backups/mongodb`

### Generated Scripts
- **Connection helper**: `connection-strings-template.txt`
- **Audit tool**: `./scripts/security-audit.sh`
- **Performance check**: `mongodb-performance-check.sh`

## Troubleshooting

### Installation Issues
```bash
# Check installation log
sudo tail -f /var/log/mongodb-installer/install-*.log

# Re-run specific step
cd scripts/
sudo ./install-mongodb.sh  # Just MongoDB
sudo ./setup-firewall.sh   # Just firewall
```

### Connection Issues
```bash
# Check MongoDB status
sudo systemctl status mongod

# Check firewall
sudo ufw status

# Test local connection
mongosh --eval "db.adminCommand({ping: 1})"
```

### Permission Issues
```bash
# Fix environment file permissions
chmod 600 .env

# Check MongoDB data permissions
sudo ls -la /var/lib/mongodb
```

## System Requirements

### Minimum
- **OS**: Ubuntu 24.04 LTS
- **RAM**: 4GB (8GB+ recommended)
- **Disk**: 20GB available
- **Network**: Internet access for packages

### Recommended
- **CPU**: 4+ cores
- **RAM**: 8GB+
- **Disk**: SSD storage, 100GB+
- **Network**: Dedicated network interface

## Security Checklist

### ✅ Post-Installation
- [ ] Change environment file permissions: `chmod 600 .env`
- [ ] Review generated passwords in `.env`
- [ ] Run security audit: `./scripts/security-audit.sh .env`
- [ ] Configure firewall for your app servers
- [ ] Test backup and restore process

### ✅ Production Ready
- [ ] Enable SSL/TLS encryption
- [ ] Set up monitoring (Zabbix/Grafana)
- [ ] Configure log aggregation
- [ ] Schedule regular security audits
- [ ] Document disaster recovery procedures

## Uninstallation

### Complete Removal
```bash
sudo ./uninstall.sh
```
⚠️ **WARNING**: This removes ALL data permanently!

### What Gets Removed
- All MongoDB packages and data
- Configuration files and SSL certificates
- Backup files and cron jobs
- System optimizations and firewall rules
- Monitoring configurations

## Support

### Documentation
- **Complete Guide**: `README.md`
- **Security**: `SECURITY-GUIDE.md`
- **Production**: `PRODUCTION-CHECKLIST.md`
- **Compass**: `MONGODB-COMPASS-GUIDE.md`

### Getting Help
1. Check installation logs: `/var/log/mongodb-installer/`
2. Run security audit for diagnostics
3. Review MongoDB logs: `/var/log/mongodb/mongod.log`
4. Create GitHub issue with logs and error details

---

## 🎯 Next Steps After Installation

1. **Secure your environment file**: `chmod 600 .env`
2. **Test connection**: Use MongoDB Compass or mongosh
3. **Configure applications**: Use connection strings from .env
4. **Set up monitoring**: Enable alerts and dashboards
5. **Plan backups**: Test restore procedures
6. **Review security**: Run regular audits

**🎉 You're ready to use MongoDB in production!**