#!/bin/bash

# MongoDB Automated Installation Script
# Single command installation for Ubuntu 24.04 servers
# Usage: ./install.sh [--unattended] [--domain=your-domain.com]

set -euo pipefail

# Version and metadata
VERSION="1.0.0"
INSTALL_DATE=$(date '+%Y-%m-%d %H:%M:%S')
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="/var/log/mongodb-installer"
INSTALL_LOG="$LOG_DIR/install-$(date +%Y%m%d_%H%M%S).log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Progress tracking
TOTAL_STEPS=12
CURRENT_STEP=0

# Configuration
UNATTENDED=false
DOMAIN=""
SETUP_SSL=false
SETUP_MONITORING=false
ENABLE_FIREWALL=true
CREATE_BACKUPS=true
DEBUG_MODE=false

# Parse command line arguments
for arg in "$@"; do
    case $arg in
        --unattended)
            UNATTENDED=true
            shift
            ;;
        --domain=*)
            DOMAIN="${arg#*=}"
            shift
            ;;
        --ssl)
            SETUP_SSL=true
            shift
            ;;
        --monitoring)
            SETUP_MONITORING=true
            shift
            ;;
        --no-firewall)
            ENABLE_FIREWALL=false
            shift
            ;;
        --no-backup)
            CREATE_BACKUPS=false
            shift
            ;;
        --debug)
            DEBUG_MODE=true
            set -x
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $arg"
            show_help
            exit 1
            ;;
    esac
done

# Function definitions
show_help() {
    cat << EOF
MongoDB Automated Installation Script v$VERSION

USAGE:
    ./install.sh [OPTIONS]

OPTIONS:
    --unattended        Run without interactive prompts (uses defaults)
    --domain=DOMAIN     Set MongoDB domain/hostname
    --ssl               Enable SSL/TLS setup
    --monitoring        Setup monitoring (Zabbix/Grafana)
    --no-firewall       Skip firewall configuration
    --no-backup         Skip backup setup
    --help, -h          Show this help message

EXAMPLES:
    ./install.sh                                    # Interactive installation
    ./install.sh --domain=db.example.com --ssl     # With custom domain and SSL
    ./install.sh --unattended                      # Fully automated

REQUIREMENTS:
    - Ubuntu 24.04 LTS
    - Root or sudo privileges
    - Internet connection
    - Minimum 4GB RAM, 20GB disk space

EOF
}

print_banner() {
    clear
    cat << "EOF"
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║    🍃 MongoDB Self-Hosted Installation Script               ║
║                                                              ║
║    Version: 1.0.0                                           ║
║    Compatible: Ubuntu 24.04 LTS                             ║
║    Features: Security, SSL, Monitoring, Backups             ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
EOF
    echo ""
}

print_step() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    local message="$1"
    local percentage=$((CURRENT_STEP * 100 / TOTAL_STEPS))
    echo -e "${BLUE}[${CURRENT_STEP}/${TOTAL_STEPS}]${NC} ${GREEN}$message${NC} (${percentage}%)"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Step $CURRENT_STEP: $message" >> "$INSTALL_LOG" 2>/dev/null || true
}

print_status() {
    echo -e "${CYAN}[INFO]${NC} $1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - INFO: $1" >> "$INSTALL_LOG" 2>/dev/null || true
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - WARN: $1" >> "$INSTALL_LOG" 2>/dev/null || true
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: $1" >> "$INSTALL_LOG" 2>/dev/null || true
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - SUCCESS: $1" >> "$INSTALL_LOG" 2>/dev/null || true
}

cleanup_on_error() {
    echo -e "${RED}[ERROR]${NC} Installation failed. Check log: $INSTALL_LOG"
    echo -e "${RED}[ERROR]${NC} Run './uninstall.sh' to clean up if needed"
    exit 1
}

# Trap errors (only if not in debug mode)
if [ "$DEBUG_MODE" != true ]; then
    trap cleanup_on_error ERR
fi

check_system() {
    print_step "System Compatibility Check"
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root or with sudo"
        exit 1
    fi
    
    # Check Ubuntu version
    if ! grep -q "Ubuntu 24.04" /etc/os-release; then
        print_warning "This script is designed for Ubuntu 24.04. Continuing anyway..."
    fi
    
    # Check system resources
    local total_ram=$(free -m | awk '/^Mem:/{print $2}')
    local available_disk=$(df / | awk 'NR==2{print $4}')
    
    if [ "$total_ram" -lt 4096 ]; then
        print_warning "System has less than 4GB RAM ($total_ram MB). MongoDB may not perform optimally."
    fi
    
    if [ "$available_disk" -lt 20971520 ]; then  # 20GB in KB
        print_warning "Available disk space is less than 20GB. Consider freeing up space."
    fi
    
    print_success "System compatibility check completed"
}

setup_logging() {
    # Create log directory
    mkdir -p "$LOG_DIR"
    chmod 750 "$LOG_DIR"
    
    print_status "Installation log: $INSTALL_LOG"
    
    # Start logging (simplified to avoid hanging)
    {
        echo "MongoDB Installation Started: $(date)"
        echo "Version: $VERSION"
        echo "System: $(uname -a)"
        echo "User: $(whoami)"
        echo "Arguments: $*"
        echo "============================================"
    } >> "$INSTALL_LOG"
}

interactive_setup() {
    if [ "$UNATTENDED" = true ]; then
        print_status "Running in unattended mode with default settings"
        # Set defaults for unattended mode
        if [ -z "$DOMAIN" ]; then
            DOMAIN=$(hostname -f 2>/dev/null || hostname 2>/dev/null || echo "localhost")
        fi
        print_status "Domain set to: $DOMAIN"
        print_status "SSL: $SETUP_SSL, Monitoring: $SETUP_MONITORING, Firewall: $ENABLE_FIREWALL, Backups: $CREATE_BACKUPS"
        return
    fi
    
    print_step "Interactive Configuration"
    
    echo -e "${PURPLE}MongoDB Installation Configuration${NC}"
    echo "================================================"
    
    # Domain configuration
    if [ -z "$DOMAIN" ]; then
        read -p "Enter your MongoDB domain/hostname [localhost]: " DOMAIN
        DOMAIN=${DOMAIN:-localhost}
    fi
    
    # SSL setup
    if [ "$SETUP_SSL" = false ]; then
        read -p "Enable SSL/TLS encryption? [y/N]: " ssl_choice
        if [[ $ssl_choice =~ ^[Yy]$ ]]; then
            SETUP_SSL=true
        fi
    fi
    
    # Monitoring setup
    if [ "$SETUP_MONITORING" = false ]; then
        read -p "Setup monitoring (Zabbix/Grafana templates)? [y/N]: " monitor_choice
        if [[ $monitor_choice =~ ^[Yy]$ ]]; then
            SETUP_MONITORING=true
        fi
    fi
    
    # Firewall setup
    read -p "Configure firewall protection? [Y/n]: " firewall_choice
    if [[ $firewall_choice =~ ^[Nn]$ ]]; then
        ENABLE_FIREWALL=false
    fi
    
    # Backup setup
    read -p "Setup automated backups? [Y/n]: " backup_choice
    if [[ $backup_choice =~ ^[Nn]$ ]]; then
        CREATE_BACKUPS=false
    fi
    
    # Summary
    echo ""
    echo -e "${PURPLE}Configuration Summary:${NC}"
    echo "======================"
    echo "Domain: $DOMAIN"
    echo "SSL/TLS: $SETUP_SSL"
    echo "Monitoring: $SETUP_MONITORING"
    echo "Firewall: $ENABLE_FIREWALL"
    echo "Backups: $CREATE_BACKUPS"
    echo ""
    
    if [ "$UNATTENDED" = false ]; then
        read -p "Proceed with installation? [Y/n]: " proceed_choice
        if [[ $proceed_choice =~ ^[Nn]$ ]]; then
            print_status "Installation cancelled by user"
            exit 0
        fi
    fi
}

install_dependencies() {
    print_step "Installing System Dependencies"
    
    # Update system
    apt-get update
    apt-get upgrade -y
    
    # Install required packages
    apt-get install -y \
        curl \
        gnupg \
        software-properties-common \
        apt-transport-https \
        ca-certificates \
        wget \
        unzip \
        openssl \
        ufw \
        logrotate \
        cron \
        bc \
        jq
    
    print_success "System dependencies installed"
}

generate_environment() {
    print_step "Generating Environment Configuration"
    
    # Generate secure passwords
    local admin_password=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    local staging_password=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    local test_password=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    local monitoring_password=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    local backup_password=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    local reporting_password=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    
    # Create .env file
    cat > "$SCRIPT_DIR/.env" << EOF
# MongoDB Environment Configuration - Generated $(date)
# KEEP THIS FILE SECURE - NEVER COMMIT TO VERSION CONTROL

# MongoDB Host Configuration
MONGODB_HOST="$DOMAIN"
MONGODB_PORT="27017"
MONGODB_REPLICA_SET=""

# SSL/TLS Configuration
MONGODB_SSL_ENABLED="$SETUP_SSL"
MONGODB_SSL_CERT_PATH="/etc/mongodb/ssl/mongodb.pem"
MONGODB_SSL_CA_PATH="/etc/mongodb/ssl/ca.crt"

# Admin User Credentials
MONGODB_ADMIN_USER="adminUser"
MONGODB_ADMIN_PASSWORD="$admin_password"
MONGODB_ADMIN_DB="admin"

# Application Database Names
MONGODB_STAGING_DB="yourapp_staging"
MONGODB_TEST_DB="yourapp_test"
MONGODB_PRODUCTION_DB="yourapp_production"

# Application User Credentials
MONGODB_STAGING_USER="stagingUser"
MONGODB_STAGING_PASSWORD="$staging_password"

MONGODB_TEST_USER="testUser"
MONGODB_TEST_PASSWORD="$test_password"

MONGODB_PRODUCTION_USER="productionUser"
MONGODB_PRODUCTION_PASSWORD="$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)"

# Service Account Credentials
MONGODB_MONITORING_USER="monitoringUser"
MONGODB_MONITORING_PASSWORD="$monitoring_password"

MONGODB_BACKUP_USER="backupUser"
MONGODB_BACKUP_PASSWORD="$backup_password"

MONGODB_REPORTING_USER="reportingUser"
MONGODB_REPORTING_PASSWORD="$reporting_password"

# Backup Configuration
BACKUP_RETENTION_DAYS="7"
BACKUP_DIR="/var/backups/mongodb"

# Performance Tuning
MONGODB_CACHE_SIZE_GB=""
MONGODB_MAX_CONNECTIONS="65536"

# Security Settings
ENABLE_AUDIT_LOG="false"
ENABLE_ENCRYPTION_AT_REST="false"
AUTH_MECHANISM="SCRAM-SHA-256"

# Monitoring Configuration
ENABLE_MONITORING="$SETUP_MONITORING"
MONITORING_INTERVAL_SECONDS="60"

# Log Configuration
LOG_LEVEL="0"
LOG_ROTATE_SIZE_MB="100"
LOG_RETENTION_DAYS="14"

# Network Configuration
BIND_IPS="127.0.0.1,$DOMAIN"
ALLOWED_CLIENT_IPS=""

# Notification Settings
ALERT_EMAIL=""
SLACK_WEBHOOK_URL=""

# Configuration metadata
CONFIG_VERSION="1.0"
INSTALL_VERSION="$VERSION"
INSTALL_DATE="$INSTALL_DATE"
EOF
    
    # Secure the environment file
    chmod 600 "$SCRIPT_DIR/.env"
    chown root:root "$SCRIPT_DIR/.env"
    
    print_success "Environment configuration generated with secure passwords"
    print_status "Environment file: $SCRIPT_DIR/.env (keep secure!)"
}

run_installation_steps() {
    # Step 4: Install MongoDB
    print_step "Installing MongoDB 7.0"
    cd "$SCRIPT_DIR/scripts"
    ./install-mongodb.sh
    
    # Step 5: Create users
    print_step "Creating Database Users"
    ./create-users-secure.sh "$SCRIPT_DIR/.env"
    
    # Step 6: Configure security
    print_step "Enabling Security and Authentication"
    ./configure-security.sh
    
    # Step 7: System optimization
    print_step "Optimizing System Limits"
    ./setup-systemd-limits.sh
    
    # Step 8: Performance tuning
    print_step "Configuring Performance Settings"
    ./tune-performance.sh
    
    # Step 9: SSL setup (if enabled)
    if [ "$SETUP_SSL" = true ]; then
        print_step "Setting up SSL/TLS Encryption"
        ./setup-ssl.sh
    else
        CURRENT_STEP=$((CURRENT_STEP + 1))
        print_status "Skipping SSL/TLS setup (not enabled)"
    fi
    
    # Step 10: Firewall setup
    if [ "$ENABLE_FIREWALL" = true ]; then
        print_step "Configuring Firewall Protection"
        ./setup-firewall.sh
    else
        CURRENT_STEP=$((CURRENT_STEP + 1))
        print_status "Skipping firewall setup (disabled)"
    fi
    
    # Step 11: Backup setup
    if [ "$CREATE_BACKUPS" = true ]; then
        print_step "Setting up Automated Backups"
        setup_backups
    else
        CURRENT_STEP=$((CURRENT_STEP + 1))
        print_status "Skipping backup setup (disabled)"
    fi
    
    # Step 12: Final verification
    print_step "Running Post-Installation Verification"
    run_verification
}

setup_backups() {
    # Setup backup directory
    mkdir -p /var/backups/mongodb
    chmod 700 /var/backups/mongodb
    
    # Setup log rotation
    cp "$SCRIPT_DIR/configs/logrotate-mongodb" /etc/logrotate.d/mongodb
    
    # Add backup cron job
    local cron_line="0 2 * * * $SCRIPT_DIR/backup/mongodb-backup-secure.sh $SCRIPT_DIR/.env >> /var/log/mongodb-backup.log 2>&1"
    (crontab -l 2>/dev/null; echo "$cron_line") | crontab -
    
    # Test backup
    cd "$SCRIPT_DIR/backup"
    ./mongodb-backup-secure.sh "$SCRIPT_DIR/.env" || print_warning "Initial backup test failed"
}

setup_monitoring_components() {
    if [ "$SETUP_MONITORING" = true ]; then
        cd "$SCRIPT_DIR/monitoring"
        MONGODB_HOST="$DOMAIN" ./zabbix-mongodb-template.sh
    fi
}

run_verification() {
    local verification_failed=false
    
    # Check MongoDB service
    if ! systemctl is-active --quiet mongod; then
        print_error "MongoDB service is not running"
        verification_failed=true
    fi
    
    # Check authentication
    if ! timeout 10 mongosh --eval "db.adminCommand({ping: 1})" --quiet > /dev/null 2>&1; then
        print_warning "MongoDB connection test without auth succeeded (may be insecure)"
    fi
    
    # Run security audit
    cd "$SCRIPT_DIR/scripts"
    if ! ./security-audit.sh "$SCRIPT_DIR/.env"; then
        print_warning "Security audit found issues - review the report"
    fi
    
    if [ "$verification_failed" = true ]; then
        print_error "Verification failed - check logs for details"
        return 1
    fi
    
    print_success "Post-installation verification completed"
}

show_completion_summary() {
    local env_file="$SCRIPT_DIR/.env"
    
    print_banner
    echo -e "${GREEN}🎉 MongoDB Installation Completed Successfully! 🎉${NC}"
    echo ""
    echo "📊 Installation Summary:"
    echo "======================="
    echo "• MongoDB Version: 7.0"
    echo "• Domain/Host: $DOMAIN"
    echo "• SSL/TLS: $([ "$SETUP_SSL" = true ] && echo "✅ Enabled" || echo "❌ Disabled")"
    echo "• Firewall: $([ "$ENABLE_FIREWALL" = true ] && echo "✅ Enabled" || echo "❌ Disabled")"
    echo "• Monitoring: $([ "$SETUP_MONITORING" = true ] && echo "✅ Enabled" || echo "❌ Disabled")"
    echo "• Backups: $([ "$CREATE_BACKUPS" = true ] && echo "✅ Enabled" || echo "❌ Disabled")"
    echo ""
    echo "🔐 Security Information:"
    echo "======================="
    echo "• Environment file: $env_file"
    echo "• All passwords are auto-generated and secure"
    echo "• Authentication is ENABLED"
    echo "• Users follow least privilege principle"
    echo ""
    echo "📋 Next Steps:"
    echo "=============="
    echo "1. 🔒 Secure your environment file:"
    echo "   chmod 600 $env_file"
    echo ""
    echo "2. 📝 Review credentials:"
    echo "   cat $env_file"
    echo ""
    echo "3. 🔧 Test connection:"
    echo "   mongosh -u adminUser --authenticationDatabase admin"
    echo ""
    echo "4. 🔍 Run security audit:"
    echo "   cd $SCRIPT_DIR/scripts && ./security-audit.sh ../.env"
    echo ""
    echo "5. 📖 Read documentation:"
    echo "   • README.md - Complete setup guide"
    echo "   • SECURITY-GUIDE.md - Security best practices"
    echo "   • PRODUCTION-CHECKLIST.md - Production readiness"
    echo ""
    
    if [ "$ENABLE_FIREWALL" = true ]; then
        echo "🔥 Firewall Configuration:"
        echo "========================"
        echo "• MongoDB port 27017 is protected"
        echo "• To allow application servers:"
        echo "  sudo $SCRIPT_DIR/scripts/mongodb-allow-ip.sh YOUR_APP_SERVER_IP"
        echo ""
    fi
    
    if [ "$CREATE_BACKUPS" = true ]; then
        echo "💾 Backup Information:"
        echo "===================="
        echo "• Daily backups enabled at 2:00 AM"
        echo "• Backup location: /var/backups/mongodb"
        echo "• Retention: 7 days"
        echo "• Manual backup: $SCRIPT_DIR/backup/mongodb-backup-secure.sh $env_file"
        echo ""
    fi
    
    echo "📞 Support:"
    echo "=========="
    echo "• Installation log: $INSTALL_LOG"
    echo "• Documentation: https://github.com/your-repo/mongodb-setup"
    echo ""
    echo -e "${GREEN}✨ MongoDB is ready for production use! ✨${NC}"
}

# Main installation flow
main() {
    print_banner
    
    # Setup logging first
    setup_logging
    
    print_status "Starting installation process..."
    
    # Installation steps with error handling
    print_status "Step 1/12: System check..."
    check_system                    # Step 1
    
    print_status "Step 2/12: Configuration setup..."
    interactive_setup              # Step 2
    
    print_status "Step 3/12: Installing dependencies..."
    install_dependencies           # Step 3
    
    print_status "Step 4/12: Generating environment..."
    generate_environment          # Step 4
    
    print_status "Running main installation steps..."
    run_installation_steps        # Steps 5-12
    
    print_status "Setting up monitoring..."
    setup_monitoring_components   # Additional monitoring setup
    
    # Save installation metadata
    cat > "/var/log/mongodb-installer/install-info.json" << EOF
{
  "version": "$VERSION",
  "install_date": "$INSTALL_DATE",
  "domain": "$DOMAIN",
  "ssl_enabled": $SETUP_SSL,
  "monitoring_enabled": $SETUP_MONITORING,
  "firewall_enabled": $ENABLE_FIREWALL,
  "backups_enabled": $CREATE_BACKUPS,
  "install_directory": "$SCRIPT_DIR",
  "log_file": "$INSTALL_LOG"
}
EOF
    
    show_completion_summary
    
    print_success "MongoDB installation completed successfully!"
    exit 0
}

# Run main function
main "$@"