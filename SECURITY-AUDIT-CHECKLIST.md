# MongoDB Security Audit Checklist

## 🔍 Pre-Deployment Security Checklist

### Critical Security Requirements ✅

#### Authentication & Authorization
- [ ] **Authentication enabled** - `authorization: enabled` in mongod.conf
- [ ] **Strong passwords** - All passwords meet complexity requirements (16+ chars, mixed case, numbers, symbols)
- [ ] **No default passwords** - All example passwords changed
- [ ] **Principle of least privilege** - Users have minimal required permissions
- [ ] **No shared accounts** - Each service has dedicated user account

#### Network Security
- [ ] **Firewall active** - UFW or iptables enabled
- [ ] **MongoDB port protected** - 27017 not open to public (0.0.0.0)
- [ ] **IP whitelisting** - Only authorized IPs can connect
- [ ] **Bind IP configured** - MongoDB not bound to all interfaces unless needed
- [ ] **SSL/TLS enabled** - Encrypted connections for production

#### File System Security
- [ ] **Secure permissions** - Data/log directories owned by mongodb user
- [ ] **Environment file secured** - .env file has 600 permissions
- [ ] **Certificate security** - SSL certificates properly protected (600/400 perms)
- [ ] **No secrets in git** - .gitignore excludes all sensitive files
- [ ] **Backup encryption** - Backup files are secured and optionally encrypted

#### System Hardening
- [ ] **Transparent Huge Pages disabled** - THP turned off for MongoDB
- [ ] **System limits optimized** - File descriptors, processes, memory limits set
- [ ] **Log rotation configured** - Prevents disk space issues
- [ ] **Audit logging enabled** - If using MongoDB Enterprise

## 🔧 Automated Security Audit

Run the automated security audit script:

```bash
cd /path/to/mongodb-setup/scripts/
chmod +x security-audit.sh
sudo ./security-audit.sh /path/to/.env
```

### Audit Categories:

1. **Environment File Security**
2. **MongoDB Service Status**
3. **Configuration Security**
4. **File Permissions**
5. **Network Security**
6. **SSL/TLS Configuration**
7. **System Limits**
8. **Backup Security**
9. **Log Security**
10. **User Account Security**

## 🚨 Critical Security Violations

### IMMEDIATE ACTION REQUIRED:

- **Default passwords in use** - Change all passwords immediately
- **Authentication disabled** - Enable authentication before production
- **MongoDB open to internet** - Restrict with firewall rules
- **Environment file world-readable** - Fix permissions immediately
- **SSL certificates expired** - Renew certificates
- **No firewall protection** - Enable and configure firewall

## 📋 Regular Security Maintenance

### Daily Checks
```bash
# Quick security status
sudo systemctl status mongod
sudo ufw status
grep -c "Authentication failed" /var/log/mongodb/mongod.log | tail -10

# Automated daily audit (add to cron)
0 6 * * * /path/to/scripts/security-audit.sh /path/to/.env
```

### Weekly Checks
```bash
# Certificate expiry check
openssl x509 -in /etc/mongodb/ssl/mongodb.pem -noout -dates

# User account review
mongosh -u adminUser --authenticationDatabase admin --eval "db.runCommand({usersInfo: 1})"

# Failed authentication analysis
grep "Authentication failed" /var/log/mongodb/mongod.log | tail -50
```

### Monthly Checks
```bash
# Full security audit
sudo ./security-audit.sh /path/to/.env

# Password rotation (critical accounts)
# Update .env file with new passwords
# Restart services after password changes

# Backup integrity test
sudo ./mongodb-restore-secure.sh /path/to/.env latest_backup.tar.gz --test-only
```

## 🛡️ Security Monitoring

### Log Monitoring Setup

1. **Authentication Failure Alerts**:
```bash
# Add to /etc/logrotate.d/mongodb
/var/log/mongodb/mongod.log {
    daily
    rotate 30
    compress
    notifempty
    create 600 mongodb mongodb
    postrotate
        # Alert on excessive auth failures
        FAILURES=$(grep -c "Authentication failed" /var/log/mongodb/mongod.log.1 || echo 0)
        if [ $FAILURES -gt 10 ]; then
            echo "WARNING: $FAILURES authentication failures detected" | mail -s "MongoDB Security Alert" admin@yoursite.com
        fi
    endscript
}
```

2. **Connection Monitoring**:
```bash
# Monitor unusual connection patterns
mongosh --eval "
var status = db.serverStatus();
print('Current connections: ' + status.connections.current);
if (status.connections.current > 1000) {
    print('WARNING: High connection count detected');
}
"
```

## 📊 Security Scoring System

### Audit Results Interpretation:

- **90-100% Pass Rate**: Excellent security posture
- **80-89% Pass Rate**: Good security, minor improvements needed
- **70-79% Pass Rate**: Adequate security, several issues to address
- **Below 70%**: Poor security posture, immediate action required

### Critical Failure Conditions:
- Any authentication disabled
- Default passwords detected
- MongoDB exposed to public internet
- No firewall protection
- SSL certificates expired
- Environment file world-readable

## 🔄 Incident Response Checklist

### Security Breach Response:

1. **Immediate Actions** (0-15 minutes):
   ```bash
   # Isolate the system
   sudo ufw deny in
   
   # Stop MongoDB if compromise confirmed
   sudo systemctl stop mongod
   
   # Preserve logs
   sudo cp -r /var/log/mongodb /tmp/incident-logs-$(date +%Y%m%d_%H%M%S)
   ```

2. **Assessment** (15-60 minutes):
   ```bash
   # Run security audit
   sudo ./security-audit.sh /path/to/.env
   
   # Check for data changes
   mongosh --eval "db.oplog.rs.find().sort({ts:-1}).limit(100)"
   
   # Review authentication logs
   grep "Authentication" /var/log/mongodb/mongod.log | tail -200
   ```

3. **Recovery** (1-4 hours):
   ```bash
   # Change all passwords
   # Rotate SSL certificates
   # Restore from clean backup if needed
   # Update firewall rules
   # Review and update security policies
   ```

## 📞 Emergency Contacts

```
Primary DBA: [Name] - [Phone] - [Email]
Security Team: [Name] - [Phone] - [Email]
System Administrator: [Name] - [Phone] - [Email]
Management: [Name] - [Phone] - [Email]
```

## 🔗 Security Resources

- [MongoDB Security Checklist](https://docs.mongodb.com/manual/administration/security-checklist/)
- [CIS MongoDB Benchmark](https://www.cisecurity.org/benchmark/mongodb/)
- [OWASP Database Security](https://owasp.org/www-project-database-security/)

## 💡 Security Best Practices Summary

1. **Defense in Depth**: Multiple layers of security
2. **Least Privilege**: Minimal required access
3. **Regular Audits**: Automated and manual security checks
4. **Incident Preparedness**: Clear response procedures
5. **Continuous Monitoring**: Real-time security awareness
6. **Documentation**: Keep security policies updated
7. **Training**: Team awareness of security procedures

---

**Remember**: Security is not a destination, it's a continuous journey. Regular audits and updates are essential for maintaining a secure MongoDB deployment.