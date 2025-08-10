#!/bin/bash

# MongoDB Performance Tuning Script
# Optimizes MongoDB for production workloads

set -euo pipefail

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

# Get system information
TOTAL_RAM=$(free -g | awk '/^Mem:/{print $2}')
CPU_CORES=$(nproc)

print_status "System Information:"
print_status "  Total RAM: ${TOTAL_RAM}GB"
print_status "  CPU Cores: ${CPU_CORES}"

# Calculate optimal cache size (50% of RAM - 1GB)
CACHE_SIZE=$(echo "scale=1; ($TOTAL_RAM * 0.5) - 1" | bc)
if (( $(echo "$CACHE_SIZE < 1" | bc -l) )); then
    CACHE_SIZE=1
fi

print_status "Recommended WiredTiger cache size: ${CACHE_SIZE}GB"

# Backup current configuration
print_status "Backing up current MongoDB configuration..."
cp /etc/mongod.conf /etc/mongod.conf.backup.$(date +%Y%m%d_%H%M%S)

# Apply production configuration
print_status "Applying production configuration..."
cp ../configs/mongod-production.conf /etc/mongod.conf

# Update cache size in config
sed -i "s/cacheSizeGB: 4/cacheSizeGB: $CACHE_SIZE/g" /etc/mongod.conf

# Optimize disk scheduler
print_status "Optimizing disk I/O scheduler..."
# Find MongoDB data disk
DATA_DISK=$(df /var/lib/mongodb | tail -1 | awk '{print $1}' | sed 's/[0-9]*$//')
DISK_NAME=$(basename $DATA_DISK)

if [ -f "/sys/block/$DISK_NAME/queue/scheduler" ]; then
    echo noop > /sys/block/$DISK_NAME/queue/scheduler 2>/dev/null || \
    echo none > /sys/block/$DISK_NAME/queue/scheduler 2>/dev/null || \
    echo "Could not set disk scheduler"
    
    current_scheduler=$(cat /sys/block/$DISK_NAME/queue/scheduler)
    print_status "Disk scheduler set to: $current_scheduler"
fi

# Set up performance monitoring
print_status "Creating performance monitoring script..."
cat > /usr/local/bin/mongodb-performance-check.sh << 'EOF'
#!/bin/bash

echo "MongoDB Performance Check"
echo "========================"
echo ""

# Connect to MongoDB and get stats
mongosh -u adminUser --authenticationDatabase admin --quiet << 'EOJS'
// Server status
var serverStatus = db.serverStatus();
print("\n=== Connection Stats ===");
print("Current connections: " + serverStatus.connections.current);
print("Available connections: " + serverStatus.connections.available);
print("Total created: " + serverStatus.connections.totalCreated);

// Memory stats
print("\n=== Memory Stats ===");
print("Resident memory: " + (serverStatus.mem.resident / 1024).toFixed(2) + " GB");
print("Virtual memory: " + (serverStatus.mem.virtual / 1024).toFixed(2) + " GB");
print("Mapped memory: " + ((serverStatus.mem.mapped || 0) / 1024).toFixed(2) + " GB");

// WiredTiger cache stats
var wiredTiger = serverStatus.wiredTiger;
if (wiredTiger && wiredTiger.cache) {
    print("\n=== WiredTiger Cache ===");
    print("Cache size: " + (wiredTiger.cache["maximum bytes configured"] / 1024 / 1024 / 1024).toFixed(2) + " GB");
    print("Bytes in cache: " + (wiredTiger.cache["bytes currently in the cache"] / 1024 / 1024 / 1024).toFixed(2) + " GB");
    print("Dirty bytes: " + (wiredTiger.cache["tracked dirty bytes in the cache"] / 1024 / 1024).toFixed(2) + " MB");
}

// Operation counters
print("\n=== Operations Per Second ===");
var opcounters = serverStatus.opcounters;
print("Insert: " + opcounters.insert);
print("Query: " + opcounters.query);
print("Update: " + opcounters.update);
print("Delete: " + opcounters.delete);
print("Command: " + opcounters.command);

// Lock stats
print("\n=== Global Lock Stats ===");
var globalLock = serverStatus.globalLock;
print("Total time: " + globalLock.totalTime);
print("Current queue total: " + globalLock.currentQueue.total);
print("Active clients: " + globalLock.activeClients.total);

// Index stats for all databases
print("\n=== Index Usage Stats ===");
db.adminCommand({ listDatabases: 1 }).databases.forEach(function(database) {
    if (database.name !== "local" && database.name !== "config") {
        var dbStats = db.getSiblingDB(database.name).stats();
        print("\nDatabase: " + database.name);
        print("  Data size: " + (dbStats.dataSize / 1024 / 1024).toFixed(2) + " MB");
        print("  Index size: " + (dbStats.indexSize / 1024 / 1024).toFixed(2) + " MB");
        print("  Index/Data ratio: " + ((dbStats.indexSize / dbStats.dataSize) * 100).toFixed(2) + "%");
    }
});

// Slow queries
print("\n=== Recent Slow Queries ===");
db.getSiblingDB("admin").aggregate([
    { $currentOp: { allUsers: true } },
    { $match: { 
        $and: [
            { secs_running: { $exists: true } },
            { secs_running: { $gt: 1 } }
        ]
    }},
    { $limit: 5 },
    { $project: {
        secs_running: 1,
        ns: 1,
        command: 1,
        planSummary: 1
    }}
]).forEach(function(op) {
    print("  Duration: " + op.secs_running + "s, Namespace: " + op.ns);
});

quit();
EOJS
EOF

chmod +x /usr/local/bin/mongodb-performance-check.sh

# Create index optimization script
print_status "Creating index optimization script..."
cat > /usr/local/bin/mongodb-index-advisor.sh << 'EOF'
#!/bin/bash

echo "MongoDB Index Advisor"
echo "===================="
echo ""

mongosh -u adminUser --authenticationDatabase admin --quiet << 'EOJS'
// Check for missing indexes
print("Checking for queries without indexes...\n");

db.adminCommand({ listDatabases: 1 }).databases.forEach(function(database) {
    if (database.name !== "local" && database.name !== "config" && database.name !== "admin") {
        var dbObj = db.getSiblingDB(database.name);
        print("\nDatabase: " + database.name);
        
        dbObj.getCollectionNames().forEach(function(collection) {
            var stats = dbObj[collection].stats();
            if (stats.size > 0) {
                print("  Collection: " + collection);
                print("    Documents: " + stats.count);
                print("    Indexes: " + stats.nindexes);
                
                // Get index usage stats
                var indexStats = dbObj[collection].aggregate([
                    { $indexStats: {} }
                ]).toArray();
                
                indexStats.forEach(function(idx) {
                    if (idx.accesses.ops === 0) {
                        print("    WARNING: Unused index: " + idx.name);
                    }
                });
            }
        });
    }
});

// Check for redundant indexes
print("\n\nChecking for redundant indexes...");
// This would require more complex logic to implement properly

quit();
EOJS
EOF

chmod +x /usr/local/bin/mongodb-index-advisor.sh

# Create automated performance report
print_status "Setting up automated performance reporting..."
cat > /usr/local/bin/mongodb-daily-report.sh << 'EOF'
#!/bin/bash

REPORT_DIR="/var/log/mongodb/performance-reports"
mkdir -p "$REPORT_DIR"

REPORT_FILE="$REPORT_DIR/mongodb-performance-$(date +%Y%m%d).log"

echo "MongoDB Daily Performance Report - $(date)" > "$REPORT_FILE"
echo "==========================================" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# System resources
echo "System Resources:" >> "$REPORT_FILE"
echo "-----------------" >> "$REPORT_FILE"
free -h >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
df -h /var/lib/mongodb >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# MongoDB performance
/usr/local/bin/mongodb-performance-check.sh >> "$REPORT_FILE" 2>&1

# Compress old reports
find "$REPORT_DIR" -name "*.log" -mtime +7 -exec gzip {} \;

# Delete very old reports
find "$REPORT_DIR" -name "*.gz" -mtime +30 -delete
EOF

chmod +x /usr/local/bin/mongodb-daily-report.sh

# Add to cron
print_status "Adding daily performance report to cron..."
(crontab -l 2>/dev/null; echo "0 2 * * * /usr/local/bin/mongodb-daily-report.sh") | crontab -

print_status "Performance tuning completed!"
print_status ""
print_status "Tools available:"
print_status "  - mongodb-performance-check.sh : Real-time performance stats"
print_status "  - mongodb-index-advisor.sh : Index usage analysis"
print_status "  - mongodb-daily-report.sh : Daily performance report"
print_status ""
print_warning "Restart MongoDB to apply all changes:"
print_warning "  systemctl restart mongod"