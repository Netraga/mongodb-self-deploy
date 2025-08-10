#!/bin/bash

# Zabbix MongoDB Monitoring Setup Script
# This script creates necessary files for Zabbix MongoDB monitoring

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_status "Creating Zabbix MongoDB monitoring configuration..."

# Create Zabbix agent configuration for MongoDB
cat > /etc/zabbix/zabbix_agentd.d/mongodb.conf << 'EOF'
# MongoDB monitoring parameters for Zabbix
UserParameter=mongodb.status[*],echo "db.serverStatus().$1" | mongosh -u monitoringUser -p 'Monitor#2025!ReadOnly' --authenticationDatabase admin --quiet | grep -v "Current Mongosh Log ID" | python3 -c "import sys, json; print(json.load(sys.stdin)['$2'])"
UserParameter=mongodb.ping,echo "db.adminCommand('ping')" | mongosh -u monitoringUser -p 'Monitor#2025!ReadOnly' --authenticationDatabase admin --quiet | grep -v "Current Mongosh Log ID" | grep -c "ok.*1"
UserParameter=mongodb.version,mongosh --version | head -1 | awk '{print $2}'
UserParameter=mongodb.conn.current,echo "db.serverStatus().connections.current" | mongosh -u monitoringUser -p 'Monitor#2025!ReadOnly' --authenticationDatabase admin --quiet | grep -v "Current Mongosh Log ID"
UserParameter=mongodb.conn.available,echo "db.serverStatus().connections.available" | mongosh -u monitoringUser -p 'Monitor#2025!ReadOnly' --authenticationDatabase admin --quiet | grep -v "Current Mongosh Log ID"
UserParameter=mongodb.mem.resident,echo "db.serverStatus().mem.resident" | mongosh -u monitoringUser -p 'Monitor#2025!ReadOnly' --authenticationDatabase admin --quiet | grep -v "Current Mongosh Log ID"
UserParameter=mongodb.mem.virtual,echo "db.serverStatus().mem.virtual" | mongosh -u monitoringUser -p 'Monitor#2025!ReadOnly' --authenticationDatabase admin --quiet | grep -v "Current Mongosh Log ID"
EOF

# Create monitoring script
cat > /usr/local/bin/mongodb-stats.sh << 'EOF'
#!/bin/bash
# MongoDB Statistics Collection Script for Monitoring

MONGO_USER="monitoringUser"
MONGO_PASS="Monitor#2025!ReadOnly"
MONGO_AUTH_DB="admin"
MONGO_HOST="${MONGODB_HOST:-YOUR_DOMAIN.example.com}"
MONGO_PORT="27017"

# Function to execute MongoDB command
mongo_exec() {
    echo "$1" | mongosh -u "$MONGO_USER" -p "$MONGO_PASS" --host "$MONGO_HOST" --port "$MONGO_PORT" --authenticationDatabase "$MONGO_AUTH_DB" --quiet 2>/dev/null | grep -v "Current Mongosh Log ID"
}

# Get various statistics
case "$1" in
    connections)
        mongo_exec "db.serverStatus().connections"
        ;;
    opcounters)
        mongo_exec "db.serverStatus().opcounters"
        ;;
    memory)
        mongo_exec "db.serverStatus().mem"
        ;;
    replication)
        mongo_exec "rs.status()"
        ;;
    dbstats)
        mongo_exec "db.stats()"
        ;;
    *)
        echo "Usage: $0 {connections|opcounters|memory|replication|dbstats}"
        exit 1
        ;;
esac
EOF

chmod +x /usr/local/bin/mongodb-stats.sh

# Create Grafana dashboard configuration
cat > grafana-mongodb-dashboard.json << 'EOF'
{
  "dashboard": {
    "title": "MongoDB Monitoring Dashboard",
    "panels": [
      {
        "title": "Connections",
        "targets": [
          {
            "expr": "mongodb_connections_current",
            "legendFormat": "Current Connections"
          },
          {
            "expr": "mongodb_connections_available",
            "legendFormat": "Available Connections"
          }
        ]
      },
      {
        "title": "Operations Per Second",
        "targets": [
          {
            "expr": "rate(mongodb_opcounters_insert[5m])",
            "legendFormat": "Inserts/sec"
          },
          {
            "expr": "rate(mongodb_opcounters_query[5m])",
            "legendFormat": "Queries/sec"
          },
          {
            "expr": "rate(mongodb_opcounters_update[5m])",
            "legendFormat": "Updates/sec"
          },
          {
            "expr": "rate(mongodb_opcounters_delete[5m])",
            "legendFormat": "Deletes/sec"
          }
        ]
      },
      {
        "title": "Memory Usage",
        "targets": [
          {
            "expr": "mongodb_mem_resident",
            "legendFormat": "Resident Memory"
          },
          {
            "expr": "mongodb_mem_virtual",
            "legendFormat": "Virtual Memory"
          }
        ]
      }
    ]
  }
}
EOF

# Create Prometheus exporter configuration
cat > prometheus-mongodb-exporter.service << 'EOF'
[Unit]
Description=MongoDB Prometheus Exporter
After=network.target

[Service]
Type=simple
User=prometheus
ExecStart=/usr/local/bin/mongodb_exporter \
    --mongodb.uri=mongodb://monitoringUser:MONITORING_PASSWORD@YOUR_DOMAIN.example.com:27017/admin \
    --mongodb.tls \
    --mongodb.tls-disable-hostname-validation \
    --collect-all

Restart=always

[Install]
WantedBy=multi-user.target
EOF

print_status "Monitoring configuration files created!"
print_status "Files created:"
print_status "  - /etc/zabbix/zabbix_agentd.d/mongodb.conf (Zabbix agent config)"
print_status "  - /usr/local/bin/mongodb-stats.sh (Stats collection script)"
print_status "  - grafana-mongodb-dashboard.json (Grafana dashboard template)"
print_status "  - prometheus-mongodb-exporter.service (Prometheus exporter service)"
print_status ""
print_status "Next steps:"
print_status "1. Restart Zabbix agent: systemctl restart zabbix-agent"
print_status "2. Import Grafana dashboard"
print_status "3. Install and configure Prometheus MongoDB exporter if using Prometheus"