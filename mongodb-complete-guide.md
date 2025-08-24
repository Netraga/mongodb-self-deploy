# MongoDB VPS Complete Setup & Management Guide

## 🚀 Quick Overview

- **Server**: 148.230.91.50 (mdb.netraga.com)
- **MongoDB**: Port 27017 with TLS enabled
- **Grafana**: http://148.230.91.50:3000
- **Prometheus**: http://148.230.91.50:9090
- **Performance**: 10-12x faster than Atlas, saving $155/month

---

## 📊 Connection Strings

### Application Connections
```bash
# Conferbot
mongodb://conferbot_user:PASSWORD@mdb.netraga.com:27017/test?authSource=test&tls=true&tlsAllowInvalidCertificates=true

# Copilotly  
mongodb://copilotly_user:PASSWORD@mdb.netraga.com:27017/prod?authSource=prod&tls=true&tlsAllowInvalidCertificates=true

# Autonoly
mongodb://autonoly_user:2Aajm1aA5nNCGWm3sH+8HxTYqzRQ8fBF@mdb.netraga.com:27017/proddb?authSource=proddb&tls=true&tlsAllowInvalidCertificates=true
```

### Admin Access
```bash
# Admin connection
mongosh --tls --tlsAllowInvalidCertificates \
  -u adminUser -p 'SzknwUBmCv/mXlzXtX6qfLV8wMhy9e/4' \
  --authenticationDatabase admin
```

---

## 🔒 IP Whitelist Management

### Add IP to Whitelist
```bash
# Simple command to add any IP
sudo ufw allow from NEW_IP_HERE to any port 27017

# Example: Add IP 192.168.1.100
sudo ufw allow from 192.168.1.100 to any port 27017
```

### Remove IP from Whitelist
```bash
# Step 1: List all rules with numbers
sudo ufw status numbered

# Step 2: Find the rule number for the IP you want to remove
# Example output:
# [ 5] 27017                      ALLOW IN    192.168.1.100

# Step 3: Delete by rule number
sudo ufw delete 5
```

### View All Whitelisted IPs
```bash
# Show all MongoDB access rules
sudo ufw status | grep 27017
```

### Quick Add Multiple IPs
```bash
# Create a script for multiple IPs
cat > add_ips.sh << 'EOF'
#!/bin/bash
# Add your IPs here
IPS=(
  "192.168.1.100"
  "192.168.1.101"
  "10.0.0.50"
)

for ip in "${IPS[@]}"; do
  echo "Adding $ip..."
  sudo ufw allow from $ip to any port 27017
done

echo "Done! Current MongoDB access:"
sudo ufw status | grep 27017
EOF

chmod +x add_ips.sh
./add_ips.sh
```

---

## 🔄 Sync Data from Atlas to VPS

### One-Time Sync Script

Save this as `sync-from-atlas.sh`:

```bash
#!/bin/bash

echo "=== MongoDB Atlas to VPS Sync ==="
echo "This will sync latest data from Atlas"
echo

# Admin credentials for VPS
ADMIN_PASS="SzknwUBmCv/mXlzXtX6qfLV8wMhy9e/4"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/opt/mongodb-backup/atlas-sync-$TIMESTAMP"

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Function to sync a database
sync_database() {
    local app_name=$1
    local atlas_uri=$2
    local db_name=$3
    
    echo
    echo "=== Syncing $app_name ($db_name) ==="
    
    # Dump from Atlas
    echo "1. Dumping from Atlas..."
    if mongodump --uri="$atlas_uri" --out="$BACKUP_DIR/${app_name}_dump"; then
        echo "   ✓ Dump complete"
        
        # Backup current VPS data first
        echo "2. Backing up current VPS data..."
        mongodump --uri="mongodb://adminUser:$ADMIN_PASS@localhost:27017/admin?tls=true&tlsInsecure=true" \
            --db="$db_name" --gzip \
            --out="$BACKUP_DIR/${app_name}_vps_backup"
        
        # Restore to VPS
        echo "3. Restoring to VPS..."
        mongorestore --uri="mongodb://adminUser:$ADMIN_PASS@localhost:27017/admin?tls=true&tlsInsecure=true" \
            --drop --db="$db_name" \
            "$BACKUP_DIR/${app_name}_dump/$db_name"
        
        echo "   ✓ $app_name sync completed!"
    else
        echo "   ✗ Failed to sync $app_name"
    fi
}

# Sync all three databases
sync_database "Conferbot" \
    "mongodb+srv://dpac:admin@cluster0.fb8e5.mongodb.net/test" \
    "test"

sync_database "Copilotly" \
    "mongodb+srv://root:redhat@cluster0.iytnfwf.mongodb.net/prod" \
    "prod"

sync_database "Autonoly" \
    "mongodb+srv://admin:redhat@cluster0.ilnzdpz.mongodb.net/proddb" \
    "proddb"

echo
echo "=== Sync Complete ==="
echo "Backup location: $BACKUP_DIR"
echo "You can now switch your apps to use the VPS MongoDB!"
```

### Make it executable:
```bash
chmod +x sync-from-atlas.sh
```

### Run the sync:
```bash
./sync-from-atlas.sh
```

---

## 📈 Monitoring Access

### Grafana Dashboards
- **URL**: http://148.230.91.50:3000
- **Login**: admin/admin
- **Dashboards to import**: 14997, 7353, 2583

### Key Metrics to Watch
- **mongodb_up**: Should always be 1
- **mongodb_connections_current**: Active connections
- **mongodb_op_counters_total**: Operations per second
- **node_cpu_seconds_total**: CPU usage
- **node_memory_MemAvailable_bytes**: Available memory

---

## 🛠️ Common Tasks

### Check MongoDB Status
```bash
# Service status
sudo systemctl status mongod

# Exporter status
sudo systemctl status mongodb-exporter

# Test connection
mongosh --tls --tlsAllowInvalidCertificates \
  -u adminUser -p 'SzknwUBmCv/mXlzXtX6qfLV8wMhy9e/4' \
  --authenticationDatabase admin --eval "db.runCommand({ping: 1})"
```

### View Logs
```bash
# MongoDB logs
sudo tail -f /var/log/mongodb/mongod.log

# Exporter logs
sudo journalctl -u mongodb-exporter -f
```

### Restart Services
```bash
# Restart MongoDB
sudo systemctl restart mongod

# Restart Exporter
sudo systemctl restart mongodb-exporter

# Restart Prometheus
sudo systemctl restart prometheus
```

---

## 🔐 Security Best Practices

1. **Regular IP Audit**
   ```bash
   # Review whitelisted IPs monthly
   sudo ufw status | grep 27017
   ```

2. **Backup Before Sync**
   - The sync script automatically backs up current data
   - Backups are in `/opt/mongodb-backup/`

3. **Monitor Access**
   ```bash
   # Check current connections
   mongosh --tls --tlsAllowInvalidCertificates \
     -u adminUser -p 'YOUR_ADMIN_PASS' \
     --authenticationDatabase admin \
     --eval "db.currentOp(true).inprog.filter(op => op.client)"
   ```

---

## 🚨 Troubleshooting

### MongoDB Won't Start
```bash
sudo journalctl -u mongod -n 50
# Check disk space
df -h
```

### Can't Connect from App
1. Check IP is whitelisted: `sudo ufw status | grep YOUR_IP`
2. Test connection: `telnet mdb.netraga.com 27017`
3. Verify TLS in connection string

### Monitoring Not Working
```bash
# Check all exporters
curl http://localhost:9100/metrics | head  # Node exporter
curl http://localhost:9216/metrics | grep mongodb_up  # MongoDB exporter
```

---

## 📋 Quick Reference

| Service | Port | URL |
|---------|------|-----|
| MongoDB | 27017 | mongodb://mdb.netraga.com:27017 |
| Grafana | 3000 | http://148.230.91.50:3000 |
| Prometheus | 9090 | http://148.230.91.50:9090 |
| Node Exporter | 9100 | http://148.230.91.50:9100/metrics |
| MongoDB Exporter | 9216 | http://148.230.91.50:9216/metrics |

---

## 💡 Pro Tips

1. **Before switching production**: Test each app with VPS connection for 24 hours
2. **Final sync**: Do one last sync right before switching to minimize data loss
3. **Keep Atlas running**: For 48 hours after switch as backup
4. **Monitor closely**: First week after migration

---

## 📝 Notes

- TLS is required for all connections (use `tls=true` in connection strings)
- All IPs must be whitelisted before connecting
- Performance is 10-12x better than Atlas
- Saving $155/month ($1,860/year)

Keep this guide handy for managing your MongoDB VPS!