#!/bin/bash

# MongoDB Systemd Limits Configuration Script
# Optimizes systemd service limits for MongoDB production use

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

print_status "Configuring systemd limits for MongoDB..."

# Create systemd override directory
print_status "Creating systemd override directory..."
mkdir -p /etc/systemd/system/mongod.service.d/

# Copy override configuration
print_status "Installing systemd override configuration..."
cp ../configs/systemd-override.conf /etc/systemd/system/mongod.service.d/override.conf

# Configure system limits
print_status "Configuring system-wide limits..."
cat >> /etc/security/limits.conf << 'EOF'

# MongoDB limits
mongodb soft nofile 64000
mongodb hard nofile 64000
mongodb soft nproc 64000
mongodb hard nproc 64000
mongodb soft memlock unlimited
mongodb hard memlock unlimited
EOF

# Configure sysctl parameters
print_status "Configuring kernel parameters..."
cat > /etc/sysctl.d/99-mongodb.conf << 'EOF'
# MongoDB kernel tuning

# Virtual memory
vm.swappiness = 1
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5

# Network tuning
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 120
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 3

# File system
fs.file-max = 2097152
fs.aio-max-nr = 1048576

# Disable transparent huge pages (THP)
kernel.mm.transparent_hugepage.enabled = never
kernel.mm.transparent_hugepage.defrag = never
EOF

# Apply sysctl parameters
print_status "Applying kernel parameters..."
sysctl -p /etc/sysctl.d/99-mongodb.conf

# Disable transparent huge pages at boot
print_status "Disabling transparent huge pages..."
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

# Enable THP disable service
systemctl daemon-reload
systemctl enable disable-transparent-huge-pages.service
systemctl start disable-transparent-huge-pages.service

# Configure NUMA if applicable
if [ -f /proc/sys/vm/zone_reclaim_mode ]; then
    print_status "Configuring NUMA settings..."
    echo 0 > /proc/sys/vm/zone_reclaim_mode
    echo "vm.zone_reclaim_mode = 0" >> /etc/sysctl.d/99-mongodb.conf
fi

# Set readahead for data volume
print_status "Configuring disk readahead..."
cat > /etc/systemd/system/mongodb-readahead.service << 'EOF'
[Unit]
Description=Set readahead for MongoDB data volume
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/sbin/blockdev --setra 256 /dev/sda1
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# Note: Update /dev/sda1 to your actual MongoDB data volume

# Reload systemd
print_status "Reloading systemd configuration..."
systemctl daemon-reload

# Create performance check script
print_status "Creating performance check script..."
cat > /usr/local/bin/check-mongodb-limits.sh << 'EOF'
#!/bin/bash

echo "MongoDB Limits Check"
echo "==================="
echo ""

# Check process limits
echo "Process limits for mongod:"
cat /proc/$(pgrep mongod)/limits | grep -E "Max open files|Max processes|Max locked memory"
echo ""

# Check THP status
echo "Transparent Huge Pages status:"
cat /sys/kernel/mm/transparent_hugepage/enabled
cat /sys/kernel/mm/transparent_hugepage/defrag
echo ""

# Check swappiness
echo "Swappiness:"
cat /proc/sys/vm/swappiness
echo ""

# Check ulimits for mongodb user
echo "Ulimits for mongodb user:"
su - mongodb -s /bin/bash -c "ulimit -a"
EOF

chmod +x /usr/local/bin/check-mongodb-limits.sh

print_status "Systemd limits configuration completed!"
print_status "Changes will take effect after restarting MongoDB:"
print_status "  systemctl restart mongod"
print_status ""
print_status "To verify limits: check-mongodb-limits.sh"