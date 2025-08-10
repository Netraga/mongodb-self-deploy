# MongoDB Security Guide

## 🔒 Secure Credentials Management

### Environment Variables Setup

1. **Copy the environment template**:
   ```bash
   cp .env.example .env
   chmod 600 .env  # Secure permissions - owner read/write only
   ```

2. **Edit the .env file with your actual values**:
   ```bash
   nano .env  # or your preferred editor
   ```

3. **NEVER commit the .env file to version control**:
   - Already included in `.gitignore`
   - Double-check with: `git status` (should not show .env)

### Password Security Requirements

#### Strong Password Policy:
- **Minimum 16 characters**
- **Include**: uppercase, lowercase, numbers, special characters
- **Avoid**: dictionary words, predictable patterns, personal information
- **Use unique passwords** for each user/environment

#### Example Strong Passwords:
```bash
# DON'T use these examples - generate your own!
MONGODB_ADMIN_PASSWORD="Kx9#mP2$nQ8@wR5vY7zB3cN6gH4jL1sF"
MONGODB_STAGING_PASSWORD="Tn8&rW9#pL4@xK2nM5vC7zB9gH6jQ3sD"
```

#### Password Generation:
```bash
# Generate secure passwords
openssl rand -base64 32
# or
pwgen -s 32 1
# or use online tools like: https://bitwarden.com/password-generator/
```

## 🛡️ Security Hardening

### Network Security

1. **Firewall Configuration**:
   ```bash
   # Only allow specific IPs
   sudo mongodb-allow-ip.sh 192.168.1.100  # Your app server
   sudo mongodb-allow-ip.sh 10.0.0.0/24    # Your private network
   
   # NEVER allow all IPs
   # sudo ufw allow 27017  # DON'T DO THIS!
   ```

2. **SSL/TLS Encryption**:
   ```bash
   # Enable SSL/TLS for production
   sudo ./setup-ssl.sh
   
   # Use SSL in connection strings
   mongodb://user:pass@YOUR_DOMAIN.example.com:27017/db?tls=true&tlsCAFile=/path/to/ca.crt
   ```

### Authentication & Authorization

1. **User Privilege Principle**:
   - **Admin users**: Only for administration
   - **Application users**: Only access to specific databases
   - **Service accounts**: Minimal required permissions
   - **No shared accounts**: Each service has its own user

2. **Role-Based Access Control**:
   ```javascript
   // Example: Create application-specific user
   db.createUser({
     user: "myapp_prod",
     pwd: "STRONG_PASSWORD_HERE",
     roles: [
       { role: "readWrite", db: "myapp_production" }
       // Only access to specific database
     ]
   })
   ```

### Data Security

1. **Encryption at Rest** (MongoDB Enterprise):
   ```yaml
   # In mongod.conf
   security:
     enableEncryption: true
     encryptionKeyFile: /etc/mongodb-keyfile
   ```

2. **Audit Logging** (MongoDB Enterprise):
   ```yaml
   # In mongod.conf
   auditLog:
     destination: file
     format: JSON
     path: /var/log/mongodb/audit.json
   ```

## 🔍 Security Monitoring

### Log Analysis

1. **Monitor Authentication Failures**:
   ```bash
   # Check for failed logins
   grep -i "authentication failed" /var/log/mongodb/mongod.log
   
   # Check for unauthorized access attempts
   grep -i "unauthorized" /var/log/mongodb/mongod.log
   ```

2. **Connection Monitoring**:
   ```bash
   # Monitor connection spikes
   mongosh --eval "db.serverStatus().connections"
   ```

### Security Alerts Setup

1. **Failed Authentication Alerts**:
   ```bash
   # Add to cron for monitoring
   0 */6 * * * /path/to/check-auth-failures.sh
   ```

2. **Unusual Activity Detection**:
   - Monitor connection patterns
   - Track unusual query patterns
   - Alert on privilege escalation attempts

## 🔐 Credential Rotation

### Regular Password Changes

1. **Monthly rotation for admin accounts**:
   ```javascript
   // Connect as admin
   use admin
   db.changeUserPassword("adminUser", "NEW_STRONG_PASSWORD")
   ```

2. **Quarterly rotation for application accounts**:
   ```bash
   # Update .env file with new passwords
   # Restart applications after password change
   ```

3. **SSL Certificate Renewal**:
   ```bash
   # Before certificates expire
   sudo ./setup-ssl.sh  # Regenerates certificates
   ```

## 🚨 Incident Response

### Security Breach Response

1. **Immediate Actions**:
   ```bash
   # Disable compromised accounts
   mongosh --eval "db.updateUser('compromised_user', {roles: []})"
   
   # Block suspicious IPs
   sudo ufw deny from SUSPICIOUS_IP
   
   # Enable audit logging temporarily
   # Review connection logs
   ```

2. **Investigation Steps**:
   - Check audit logs for unauthorized access
   - Review database changes
   - Identify affected data
   - Assess damage scope

3. **Recovery Actions**:
   - Change all passwords
   - Revoke and regenerate certificates
   - Restore from clean backup if needed
   - Update firewall rules

## 🔧 Security Tools

### Vulnerability Scanning

1. **MongoDB Security Check**:
   ```bash
   # Custom security audit script
   ./security-audit.sh
   ```

2. **Network Security Scan**:
   ```bash
   # Scan for open ports
   nmap -p 27017 YOUR_DOMAIN.example.com
   
   # Should show: 27017/tcp filtered (not open to public)
   ```

### Backup Security

1. **Secure Backup Storage**:
   ```bash
   # Encrypt backup files
   gpg -c mongodb_backup_20240101.tar.gz
   
   # Store in secure location with limited access
   chmod 600 /var/backups/mongodb/*
   ```

2. **Backup Integrity**:
   ```bash
   # Verify backup integrity
   tar -tzf backup.tar.gz >/dev/null && echo "Backup OK" || echo "Backup CORRUPTED"
   ```

## ✅ Security Checklist

### Daily Checks
- [ ] Review authentication logs
- [ ] Check connection patterns
- [ ] Monitor disk usage
- [ ] Verify backup completion

### Weekly Checks
- [ ] Review user accounts and permissions
- [ ] Check SSL certificate expiry
- [ ] Analyze slow query logs
- [ ] Update firewall rules if needed

### Monthly Checks
- [ ] Rotate critical passwords
- [ ] Review access logs thoroughly
- [ ] Test backup restore procedure
- [ ] Update security patches
- [ ] Audit user permissions

### Quarterly Checks
- [ ] Comprehensive security audit
- [ ] Penetration testing
- [ ] Review security policies
- [ ] Update disaster recovery plan

## 📞 Emergency Contacts

```bash
# Create secure contact list
cat > /etc/mongodb/emergency-contacts << 'EOF'
DBA: [Name] - [Secure Phone] - [Secure Email]
Security Team: [Name] - [Phone] - [Email]
System Admin: [Name] - [Phone] - [Email]
Management: [Name] - [Phone] - [Email]
EOF

chmod 600 /etc/mongodb/emergency-contacts
```

## 🔗 Security Resources

- [MongoDB Security Checklist](https://docs.mongodb.com/manual/security/)
- [OWASP Database Security](https://owasp.org/www-project-database-security/)
- [CIS MongoDB Benchmark](https://www.cisecurity.org/benchmark/mongodb/)

---

**Remember**: Security is an ongoing process, not a one-time setup. Regularly review and update your security measures.