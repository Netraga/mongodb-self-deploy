# MongoDB Self-Hosted Setup for Ubuntu 24

**🚀 One-Command Installation Available!** See [QUICK-START.md](QUICK-START.md) for instant setup.

This repository contains automated scripts to set up a production-ready, self-hosted MongoDB instance on Ubuntu 24 Server with comprehensive security, monitoring, and backup configurations.

## ⚡ Quick Installation

### Single Command Setup
```bash
# Interactive installation (recommended)
curl -fsSL https://raw.githubusercontent.com/yourusername/mongodb-setup/main/quick-install.sh | sudo bash

# OR clone and run
git clone https://github.com/yourusername/mongodb-setup.git
cd mongodb-setup
sudo ./install.sh
```

### Unattended Installation
```bash
sudo ./install.sh --unattended --domain=db.example.com --ssl --monitoring
```

## 🎯 What You Get

- **MongoDB 7.0** - Latest stable version with security patches
- **Auto-generated secure passwords** - Cryptographically secure, no hardcoded credentials
- **SSL/TLS encryption** - Optional but recommended for production
- **Firewall protection** - UFW configured with port 27017 secured
- **Automated backups** - Daily backups with 7-day retention and compression
- **Performance optimization** - System tuning, limits, and WiredTiger optimization
- **Security audit tools** - Automated 10-point security checking
- **Monitoring ready** - Zabbix/Grafana templates and performance dashboards
- **Complete logging** - Centralized logs with rotation and audit trails
- **User management** - Least-privilege principle with role-based access

## 📋 System Requirements

### Minimum Requirements
- **OS**: Ubuntu 24.04 LTS
- **RAM**: 4GB (MongoDB requires significant memory)
- **Disk**: 20GB available space
- **Network**: Internet access for package installation
- **Access**: Root or sudo privileges

### Recommended for Production
- **CPU**: 4+ cores
- **RAM**: 8GB+ (more is better for performance)
- **Disk**: SSD storage, 100GB+ with dedicated volume
- **Network**: Dedicated network interface, stable connection

## 🔧 Installation Options

### Interactive Mode (Default)
```bash
sudo ./install.sh
```
**Features:**
- Guided configuration prompts
- Domain/hostname setup
- SSL/TLS option selection
- Monitoring setup choice
- Firewall configuration options
- Real-time progress indicators

### Unattended Mode
```bash
sudo ./install.sh --unattended [OPTIONS]
```

**Available Options:**
- `--domain=HOSTNAME` - Set MongoDB hostname/FQDN
- `--ssl` - Enable SSL/TLS encryption
- `--monitoring` - Setup monitoring templates
- `--no-firewall` - Skip firewall configuration
- `--no-backup` - Skip backup setup

**Examples:**
```bash
# Basic unattended installation
sudo ./install.sh --unattended

# Full production setup
sudo ./install.sh --unattended --domain=db.mycompany.com --ssl --monitoring

# Development setup (no firewall)
sudo ./install.sh --unattended --domain=localhost --no-firewall
```

## 📁 Directory Structure

```
mongodb-setup/
├── install.sh                    # 🚀 Main installation script
├── uninstall.sh                  # 🗑️ Complete removal script
├── quick-install.sh              # ⚡ One-command installer
├── QUICK-START.md                # 📖 Quick setup guide
├── .env.example                  # 🔒 Secure environment template
├── scripts/                      # 🔧 Core installation scripts
│   ├── install-mongodb.sh        # MongoDB installation
│   ├── create-users-secure.sh    # User creation (environment-based)
│   ├── configure-security.sh     # Security hardening
│   ├── setup-ssl.sh             # SSL/TLS setup
│   ├── setup-firewall.sh        # Firewall configuration
│   ├── setup-systemd-limits.sh  # System optimization
│   ├── tune-performance.sh      # Performance tuning
│   └── security-audit.sh        # Security auditing
├── configs/                      # ⚙️ Configuration templates
│   ├── mongod.conf              # Basic MongoDB config
│   ├── mongod-production.conf   # Production-optimized config
│   ├── mongod-secure.conf       # Security-focused config
│   ├── systemd-override.conf    # System limits
│   └── logrotate-mongodb        # Log rotation setup
├── backup/                       # 💾 Backup and restore tools
│   ├── mongodb-backup-secure.sh  # Secure backup script
│   ├── mongodb-restore-secure.sh # Secure restore script
│   └── backup-cron.txt          # Cron schedule examples
├── monitoring/                   # 📊 Monitoring integrations
│   └── zabbix-mongodb-template.sh # Zabbix setup
└── docs/                        # 📚 Complete documentation
    ├── SECURITY-GUIDE.md         # Security best practices
    ├── PRODUCTION-CHECKLIST.md   # Production deployment
    ├── MONGODB-COMPASS-GUIDE.md  # GUI client setup
    └── SECURITY-AUDIT-CHECKLIST.md # Security procedures
```

## 🔐 Security Features

### Built-in Security
- **No hardcoded credentials** - All passwords in environment variables
- **Auto-generated passwords** - 25+ character cryptographically secure
- **Least privilege users** - Application users limited to specific databases
- **Environment isolation** - .env file with 600 permissions, never committed
- **SSL/TLS ready** - Complete certificate generation and configuration
- **Firewall protection** - UFW with IP whitelisting capabilities
- **Audit logging** - Comprehensive security event logging

### User Accounts Created
| User | Purpose | Database Access | Permissions |
|------|---------|----------------|-------------|
| **adminUser** | System administration | All | Full admin rights |
| **stagingUser** | Staging environment | Staging DB only | Read/write to staging |
| **testUser** | Test environment | Test DB only | Read/write to test |
| **productionUser** | Production apps | Production DB only | Read/write to production |
| **monitoringUser** | Zabbix/Grafana | Read-only | Cluster monitoring |
| **backupUser** | Backup operations | All (read-only) | Backup/restore only |
| **reportingUser** | Analytics/BI | Specified DBs | Read-only reporting |

## 🚀 Post-Installation

### Immediate Steps
```bash
# 1. Secure your environment file
chmod 600 .env

# 2. Review auto-generated credentials
cat .env

# 3. Test admin connection
mongosh -u adminUser --authenticationDatabase admin

# 4. Run security audit
sudo ./scripts/security-audit.sh .env
```

### Configure Application Access
```bash
# Allow your application server
sudo ./scripts/mongodb-allow-ip.sh 192.168.1.100

# Allow entire subnet
sudo ./scripts/mongodb-allow-ip.sh 10.0.0.0/24
```

### Connection Examples

**From Application:**
```javascript
// Node.js with environment variables
const uri = `mongodb://${process.env.MONGODB_USER}:${process.env.MONGODB_PASSWORD}@${process.env.MONGODB_HOST}:27017/${process.env.MONGODB_DATABASE}?authSource=admin`;

// With SSL
const uri = `mongodb://${process.env.MONGODB_USER}:${process.env.MONGODB_PASSWORD}@${process.env.MONGODB_HOST}:27017/${process.env.MONGODB_DATABASE}?authSource=admin&tls=true`;
```

**MongoDB Compass:**
```
Host: your-domain.com
Port: 27017
Authentication: Username/Password
Username: adminUser
Password: [from .env file]
Auth Database: admin
SSL: On (if enabled)
```

## 📊 Monitoring & Maintenance

### Built-in Tools
```bash
# Real-time performance check
mongodb-performance-check.sh

# Security audit
sudo ./scripts/security-audit.sh .env

# System limits verification
check-mongodb-limits.sh

# Index optimization analysis
mongodb-index-advisor.sh
```

### Backup Operations
```bash
# Manual backup
sudo ./backup/mongodb-backup-secure.sh .env

# Restore from backup
sudo ./backup/mongodb-restore-secure.sh .env backup_file.tar.gz

# List available backups
ls -lh /var/backups/mongodb/
```

### Log Locations
- **MongoDB logs**: `/var/log/mongodb/mongod.log`
- **Installation logs**: `/var/log/mongodb-installer/`
- **Backup logs**: `/var/backups/mongodb/backup.log`
- **Performance reports**: `/var/log/mongodb/performance-reports/`

## 🔧 Advanced Configuration

### SSL/TLS Setup
```bash
# Enable SSL/TLS
sudo ./scripts/setup-ssl.sh

# Test SSL connection
test-mongodb-ssl.sh

# Connect with SSL
mongosh --tls --tlsCAFile /etc/mongodb/ssl/ca.crt --host your-domain.com
```

### Performance Tuning
```bash
# Apply performance optimizations
sudo ./scripts/tune-performance.sh

# Monitor performance
mongodb-performance-check.sh

# Daily performance reports (automatically enabled)
tail -f /var/log/mongodb/performance-reports/mongodb-performance-$(date +%Y%m%d).log
```

## 🔍 Troubleshooting

### Common Issues

**Connection Refused:**
```bash
# Check MongoDB status
sudo systemctl status mongod

# Check firewall
sudo ufw status

# Check if port is listening
ss -tuln | grep :27017
```

**Authentication Failed:**
```bash
# Verify credentials in .env file
cat .env

# Test local connection
mongosh --eval "db.adminCommand({ping: 1})"

# Check user permissions
mongosh -u adminUser --authenticationDatabase admin --eval "db.runCommand({usersInfo: 1})"
```

**Performance Issues:**
```bash
# Check system resources
free -h && df -h

# Run performance analysis
mongodb-performance-check.sh

# Check slow queries
mongodb-index-advisor.sh
```

## 🗑️ Uninstallation

### Complete Removal
```bash
sudo ./uninstall.sh
```

**⚠️ WARNING**: This permanently removes:
- All MongoDB packages and data
- All databases and collections
- Configuration files and SSL certificates
- Backup files and cron jobs
- System optimizations and firewall rules

A final backup is created before removal at `/tmp/mongodb-final-backup-*`

## 📚 Documentation

### Quick References
- **[QUICK-START.md](QUICK-START.md)** - One-command installation guide
- **[SECURITY-GUIDE.md](SECURITY-GUIDE.md)** - Complete security documentation
- **[PRODUCTION-CHECKLIST.md](PRODUCTION-CHECKLIST.md)** - Production deployment checklist
- **[MONGODB-COMPASS-GUIDE.md](MONGODB-COMPASS-GUIDE.md)** - GUI client connection guide
- **[SECURITY-AUDIT-CHECKLIST.md](SECURITY-AUDIT-CHECKLIST.md)** - Security audit procedures

### File References
- **[.env.example](.env.example)** - Environment variable template
- **[REPOSITORY-SAFETY.md](REPOSITORY-SAFETY.md)** - Security validation report

## 💡 Tips for Success

### Before Installation
1. **Plan your setup** - Decide on domain, SSL, and monitoring needs
2. **Check system resources** - Ensure adequate RAM and disk space
3. **Network preparation** - Configure DNS if using custom domain
4. **Backup existing data** - If upgrading from existing installation

### After Installation
1. **Test thoroughly** - Verify all components work as expected
2. **Document configuration** - Save connection details securely
3. **Set up monitoring** - Configure alerts and dashboards
4. **Plan maintenance** - Schedule regular backups and updates
5. **Security reviews** - Regular audits and credential rotation

## 🆘 Support

### Getting Help
1. **Check logs**: `/var/log/mongodb-installer/install-*.log`
2. **Run diagnostics**: `sudo ./scripts/security-audit.sh .env`
3. **Review documentation**: All guides in the repository
4. **MongoDB documentation**: https://docs.mongodb.com/

### Reporting Issues
When creating issues, please include:
- Ubuntu version: `cat /etc/os-release`
- Installation command used
- Complete error messages
- Installation log file
- System resources: `free -h && df -h`

---

## 🎉 Success!

If you've made it this far, you have a production-ready MongoDB instance with:
- ✅ Security hardening and audit tools
- ✅ Performance optimization and monitoring
- ✅ Automated backups and recovery procedures
- ✅ SSL/TLS encryption capability
- ✅ Comprehensive logging and alerting
- ✅ Complete documentation and support tools

**Welcome to self-hosted MongoDB done right!** 🍃