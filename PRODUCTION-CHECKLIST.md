# MongoDB Production Readiness Checklist

## Pre-Deployment Checklist

### 🔒 Security
- [ ] **Authentication enabled** - Verify security.authorization is set to "enabled"
- [ ] **Strong passwords** - All default passwords changed
- [ ] **SSL/TLS configured** - Run `./setup-ssl.sh` and enable TLS in config
- [ ] **Firewall configured** - Only necessary IPs whitelisted
- [ ] **SELinux/AppArmor** - Security policies configured if applicable
- [ ] **Audit logging** - Enable if using MongoDB Enterprise
- [ ] **Principle of least privilege** - Users have minimal required permissions

### 🔧 System Configuration
- [ ] **Systemd limits** - Run `./setup-systemd-limits.sh`
- [ ] **Transparent Huge Pages disabled** - Verify with `cat /sys/kernel/mm/transparent_hugepage/enabled`
- [ ] **NUMA disabled** - For NUMA hardware, run MongoDB with `numactl --interleave=all`
- [ ] **Swappiness = 1** - Verify with `cat /proc/sys/vm/swappiness`
- [ ] **File descriptors ≥ 64000** - Check with `ulimit -n`
- [ ] **Readahead = 256** - For data volume
- [ ] **NTP synchronized** - Time sync is critical for replica sets

### 💾 Storage
- [ ] **XFS or ext4 filesystem** - Recommended filesystems
- [ ] **Sufficient disk space** - At least 3x expected data size
- [ ] **Separate data volume** - MongoDB data on dedicated disk
- [ ] **Journal on same volume** - For write durability
- [ ] **Regular backups tested** - Verify restore procedure works
- [ ] **Disk monitoring** - Alert on >80% usage

### 🚀 Performance
- [ ] **WiredTiger cache sized** - Set to 50% RAM - 1GB
- [ ] **Indexes optimized** - Run `mongodb-index-advisor.sh`
- [ ] **Connection pooling** - Configure in application
- [ ] **Read/Write concerns** - Set appropriate defaults
- [ ] **Profiling configured** - Capture slow queries
- [ ] **Compression enabled** - Snappy or zstd

### 📊 Monitoring
- [ ] **Monitoring agent installed** - Zabbix/Prometheus/Datadog
- [ ] **Key metrics tracked**:
  - [ ] CPU usage
  - [ ] Memory usage
  - [ ] Disk I/O
  - [ ] Network traffic
  - [ ] Connection count
  - [ ] Operation latency
  - [ ] Replication lag
  - [ ] Lock percentage
- [ ] **Alerting configured**:
  - [ ] High CPU (>80%)
  - [ ] High memory (>90%)
  - [ ] Disk space low (<20%)
  - [ ] Replication lag (>10s)
  - [ ] Connection spikes
  - [ ] Authentication failures
- [ ] **Log aggregation** - Centralized log management

### 🔄 High Availability
- [ ] **Replica set configured** - Minimum 3 members
- [ ] **Arbiter placement** - Not on same host as data nodes
- [ ] **Write concern majority** - For critical writes
- [ ] **Read preference configured** - Based on consistency needs
- [ ] **Automatic failover tested** - Verify election process
- [ ] **Backup member** - For dedicated backups

### 📋 Operational Procedures
- [ ] **Runbook created** - Step-by-step procedures for common tasks
- [ ] **Disaster recovery plan** - Documented and tested
- [ ] **Change management** - Process for config changes
- [ ] **Access control** - SSH keys, sudo configuration
- [ ] **Documentation updated** - Architecture, procedures, contacts

## Deployment Steps

### 1. Initial Setup
```bash
# Run installation
sudo ./install-mongodb.sh

# Create users
sudo ./create-users.sh

# Configure security
sudo ./configure-security.sh
```

### 2. System Optimization
```bash
# Set system limits
sudo ./setup-systemd-limits.sh

# Configure performance
sudo ./tune-performance.sh

# Setup log rotation
sudo cp configs/logrotate-mongodb /etc/logrotate.d/mongodb
```

### 3. Security Hardening
```bash
# Setup SSL/TLS
sudo ./setup-ssl.sh

# Configure firewall
sudo ./setup-firewall.sh

# Add allowed IPs
sudo mongodb-allow-ip.sh YOUR_APP_SERVER_IP
```

### 4. Enable Monitoring
```bash
# Setup monitoring
cd monitoring/
sudo ./zabbix-mongodb-template.sh

# Test performance check
mongodb-performance-check.sh
```

### 5. Configure Backups
```bash
# Test backup
sudo ./backup/mongodb-backup.sh

# Setup cron
sudo crontab -e
# Add: 0 2 * * * /path/to/backup/mongodb-backup.sh
```

### 6. Final Verification
```bash
# Check MongoDB status
sudo systemctl status mongod

# Verify authentication
mongosh -u adminUser --authenticationDatabase admin --eval "db.adminCommand({ping: 1})"

# Check limits
check-mongodb-limits.sh

# Run performance check
mongodb-performance-check.sh
```

## Post-Deployment Tasks

### Week 1
- [ ] Monitor performance metrics daily
- [ ] Review logs for errors
- [ ] Verify backup completion
- [ ] Check disk usage trends

### Month 1
- [ ] Analyze slow query logs
- [ ] Review index usage
- [ ] Optimize frequently run queries
- [ ] Update documentation

### Ongoing
- [ ] Monthly security review
- [ ] Quarterly disaster recovery test
- [ ] Regular MongoDB updates
- [ ] Performance baseline updates

## Emergency Contacts

| Role | Name | Contact | When to Call |
|------|------|---------|--------------|
| DBA | [Name] | [Phone/Email] | Database issues |
| SysAdmin | [Name] | [Phone/Email] | System issues |
| Security | [Name] | [Phone/Email] | Security incidents |
| Manager | [Name] | [Phone/Email] | Escalations |

## Quick Commands Reference

```bash
# Connect with SSL
mongodb-connect-ssl.sh adminUser admin

# Check performance
mongodb-performance-check.sh

# Emergency backup
/path/to/backup/mongodb-backup.sh

# View recent errors
tail -n 100 /var/log/mongodb/mongod.log | grep -E "ERROR|FATAL"

# Restart MongoDB
sudo systemctl restart mongod

# Check replication status
mongosh -u adminUser --authenticationDatabase admin --eval "rs.status()"
```

## Red Flags - Immediate Action Required

1. **Authentication failures spike** - Possible attack
2. **Disk usage >90%** - Add space immediately
3. **Replication lag >60s** - Check network/load
4. **Memory usage >95%** - Risk of OOM killer
5. **Connections near limit** - Connection leak
6. **Backup failures** - Data at risk

---

**Remember**: This checklist should be reviewed and updated regularly based on your specific requirements and MongoDB best practices updates.