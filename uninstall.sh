#!/bin/bash

# MongoDB Uninstall Script
# Removes MongoDB and cleans up all related files and configurations

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_banner() {
    clear
    cat << "EOF"
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║    🗑️  MongoDB Uninstall Script                             ║
║                                                              ║
║    This will completely remove MongoDB and all data         ║
║    ⚠️  WARNING: This action cannot be undone!              ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
EOF
    echo ""
}

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

confirm_uninstall() {
    print_banner
    
    echo -e "${RED}⚠️  DANGER ZONE ⚠️${NC}"
    echo ""
    echo "This script will:"
    echo "• Stop and remove MongoDB service"
    echo "• Delete all MongoDB data (databases, collections, etc.)"
    echo "• Remove MongoDB packages and configurations"
    echo "• Delete backup files"
    echo "• Remove SSL certificates"
    echo "• Clean up firewall rules"
    echo "• Remove system optimizations"
    echo ""
    echo -e "${RED}ALL DATA WILL BE PERMANENTLY LOST!${NC}"
    echo ""
    
    read -p "Are you absolutely sure you want to continue? [yes/NO]: " confirm
    if [ "$confirm" != "yes" ]; then
        print_status "Uninstall cancelled"
        exit 0
    fi
    
    echo ""
    read -p "Type 'DELETE ALL DATA' to confirm: " confirm2
    if [ "$confirm2" != "DELETE ALL DATA" ]; then
        print_status "Uninstall cancelled"
        exit 0
    fi
    
    echo ""
    print_warning "Starting uninstallation in 5 seconds... Press Ctrl+C to cancel"
    sleep 5
}

stop_services() {
    print_status "Stopping MongoDB services..."
    
    # Stop MongoDB
    if systemctl is-active --quiet mongod 2>/dev/null; then
        systemctl stop mongod
        print_status "MongoDB service stopped"
    fi
    
    # Stop any MongoDB-related services
    systemctl stop disable-transparent-huge-pages 2>/dev/null || true
    systemctl stop mongodb-readahead 2>/dev/null || true
}

backup_before_removal() {
    print_status "Creating final backup before removal..."
    
    local backup_dir="/tmp/mongodb-final-backup-$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    # Copy configuration files
    cp -r /etc/mongod* "$backup_dir/" 2>/dev/null || true
    
    # Copy environment file if it exists
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    cp "$script_dir/.env" "$backup_dir/" 2>/dev/null || true
    
    # Copy SSL certificates
    cp -r /etc/mongodb "$backup_dir/" 2>/dev/null || true
    
    print_status "Configuration backup saved to: $backup_dir"
    echo "You can restore configurations from this backup if needed"
}

remove_mongodb() {
    print_status "Removing MongoDB packages..."
    
    # Disable services
    systemctl disable mongod 2>/dev/null || true
    systemctl disable disable-transparent-huge-pages 2>/dev/null || true
    systemctl disable mongodb-readahead 2>/dev/null || true
    
    # Remove packages
    apt-get purge -y mongodb-org* 2>/dev/null || true
    apt-get autoremove -y
    apt-get autoclean
    
    # Remove package sources
    rm -f /etc/apt/sources.list.d/mongodb-org-*.list
    rm -f /usr/share/keyrings/mongodb-server-*.gpg
    
    print_success "MongoDB packages removed"
}

remove_data_and_logs() {
    print_status "Removing MongoDB data and logs..."
    
    # Remove data directory
    if [ -d "/var/lib/mongodb" ]; then
        rm -rf /var/lib/mongodb
        print_status "Data directory removed"
    fi
    
    # Remove log directory
    if [ -d "/var/log/mongodb" ]; then
        rm -rf /var/log/mongodb
        print_status "Log directory removed"
    fi
    
    # Remove installer logs
    if [ -d "/var/log/mongodb-installer" ]; then
        rm -rf /var/log/mongodb-installer
        print_status "Installer logs removed"
    fi
}

remove_configurations() {
    print_status "Removing configuration files..."
    
    # Remove configuration files
    rm -f /etc/mongod.conf*
    rm -f /etc/mongodb-keyfile
    
    # Remove systemd overrides
    rm -rf /etc/systemd/system/mongod.service.d/
    rm -f /etc/systemd/system/disable-transparent-huge-pages.service
    rm -f /etc/systemd/system/mongodb-readahead.service
    
    # Remove logrotate configuration
    rm -f /etc/logrotate.d/mongodb
    
    # Remove SSL directory
    if [ -d "/etc/mongodb" ]; then
        rm -rf /etc/mongodb
        print_status "SSL certificates removed"
    fi
    
    systemctl daemon-reload
}

remove_system_optimizations() {
    print_status "Removing system optimizations..."
    
    # Remove sysctl configurations
    rm -f /etc/sysctl.d/99-mongodb.conf
    
    # Remove limits configurations
    if [ -f "/etc/security/limits.conf" ]; then
        sed -i '/# MongoDB limits/,/^$/d' /etc/security/limits.conf
    fi
    
    # Reset transparent huge pages (if possible)
    if [ -f "/sys/kernel/mm/transparent_hugepage/enabled" ]; then
        echo always > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true
        echo always > /sys/kernel/mm/transparent_hugepage/defrag 2>/dev/null || true
    fi
}

remove_backup_files() {
    print_status "Removing backup files..."
    
    if [ -d "/var/backups/mongodb" ]; then
        rm -rf /var/backups/mongodb
        print_status "Backup directory removed"
    fi
}

remove_cron_jobs() {
    print_status "Removing cron jobs..."
    
    # Remove MongoDB-related cron jobs
    (crontab -l 2>/dev/null | grep -v mongodb-backup-secure.sh | grep -v mongodb-daily-report.sh) | crontab - 2>/dev/null || true
}

remove_firewall_rules() {
    print_status "Removing firewall rules..."
    
    # Remove MongoDB port rules
    ufw delete allow 27017 2>/dev/null || true
    ufw delete allow from any to any port 27017 2>/dev/null || true
    
    # Remove specific IP rules (this is tricky, so we'll just note it)
    print_warning "Manual removal may be needed for specific MongoDB firewall rules"
    print_status "Check with: sudo ufw status numbered"
}

remove_monitoring() {
    print_status "Removing monitoring configurations..."
    
    # Remove Zabbix agent configurations
    rm -f /etc/zabbix/zabbix_agentd.d/mongodb.conf 2>/dev/null || true
    
    # Remove monitoring scripts
    rm -f /usr/local/bin/mongodb-stats.sh
    rm -f /usr/local/bin/mongodb-performance-check.sh
    rm -f /usr/local/bin/mongodb-daily-report.sh
    rm -f /usr/local/bin/mongodb-index-advisor.sh
    
    # Restart Zabbix agent if it exists
    if systemctl is-active --quiet zabbix-agent 2>/dev/null; then
        systemctl restart zabbix-agent
    fi
}

remove_utility_scripts() {
    print_status "Removing utility scripts..."
    
    # Remove utility scripts
    rm -f /usr/local/bin/mongodb-allow-ip.sh
    rm -f /usr/local/bin/mongodb-connect-ssl.sh
    rm -f /usr/local/bin/check-mongodb-limits.sh
    rm -f /usr/local/bin/test-mongodb-ssl.sh
}

cleanup_users() {
    print_status "Removing MongoDB system user..."
    
    # Remove mongodb user (if it exists and is not used by other services)
    if id mongodb &>/dev/null; then
        userdel mongodb 2>/dev/null || print_warning "Could not remove mongodb user"
    fi
    
    # Remove mongodb group
    if getent group mongodb &>/dev/null; then
        groupdel mongodb 2>/dev/null || print_warning "Could not remove mongodb group"
    fi
}

final_cleanup() {
    print_status "Performing final cleanup..."
    
    # Update package cache
    apt-get update
    
    # Remove any remaining MongoDB processes
    pkill -f mongod 2>/dev/null || true
    
    # Clean up any remaining lock files
    rm -f /var/run/mongodb/mongod.pid 2>/dev/null || true
    rm -f /tmp/mongodb-*.sock 2>/dev/null || true
    
    # Remove the installation directory files (but preserve the script)
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    rm -f "$script_dir/.env" 2>/dev/null || true
    rm -f "$script_dir/connection-strings-template.txt" 2>/dev/null || true
}

show_completion() {
    print_banner
    echo -e "${GREEN}✅ MongoDB Uninstallation Completed${NC}"
    echo ""
    echo "🗑️ Removed Components:"
    echo "====================="
    echo "• MongoDB packages and binaries"
    echo "• All databases and collections"
    echo "• Configuration files"
    echo "• SSL certificates"
    echo "• System optimizations"
    echo "• Backup files"
    echo "• Cron jobs"
    echo "• Firewall rules"
    echo "• Monitoring configurations"
    echo "• Utility scripts"
    echo ""
    echo "📋 What's Left:"
    echo "==============="
    echo "• System packages (curl, openssl, etc.) - still installed"
    echo "• Firewall (UFW) - still active"
    echo "• Backup saved at: /tmp/mongodb-final-backup-*"
    echo ""
    echo "🔄 To reinstall MongoDB:"
    echo "========================"
    echo "git clone <repository-url>"
    echo "cd mongodb-setup"
    echo "./install.sh"
    echo ""
    echo -e "${GREEN}MongoDB has been completely removed from your system.${NC}"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root or with sudo"
   exit 1
fi

# Main uninstallation process
main() {
    confirm_uninstall
    backup_before_removal
    stop_services
    remove_cron_jobs
    remove_mongodb
    remove_data_and_logs
    remove_configurations
    remove_system_optimizations
    remove_backup_files
    remove_firewall_rules
    remove_monitoring
    remove_utility_scripts
    cleanup_users
    final_cleanup
    show_completion
}

# Run main function
main "$@"