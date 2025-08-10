#!/bin/bash

# MongoDB Quick Install Script
# Single command installation from GitHub

set -euo pipefail

# Configuration
REPO_URL="https://github.com/yourusername/mongodb-setup.git"
INSTALL_DIR="/tmp/mongodb-setup-$(date +%s)"
LOG_FILE="/tmp/mongodb-install-$(date +%Y%m%d_%H%M%S).log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_banner() {
    cat << "EOF"
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║    🍃 MongoDB Quick Installation                             ║
║                                                              ║
║    One-command setup for Ubuntu 24.04 servers              ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
EOF
    echo ""
}

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: $1" >> "$LOG_FILE"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - SUCCESS: $1" >> "$LOG_FILE"
}

cleanup() {
    if [ -d "$INSTALL_DIR" ]; then
        rm -rf "$INSTALL_DIR"
    fi
}

trap cleanup EXIT

main() {
    print_banner
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root or with sudo"
        exit 1
    fi
    
    print_status "Starting MongoDB quick installation..."
    print_status "Installation log: $LOG_FILE"
    
    # Install git if needed
    if ! command -v git &> /dev/null; then
        print_status "Installing git..."
        apt-get update
        apt-get install -y git
    fi
    
    # Clone repository
    print_status "Downloading MongoDB setup from GitHub..."
    git clone "$REPO_URL" "$INSTALL_DIR" 2>&1 | tee -a "$LOG_FILE"
    
    # Navigate to directory
    cd "$INSTALL_DIR"
    
    # Make scripts executable
    chmod +x install.sh uninstall.sh
    chmod +x scripts/*.sh backup/*.sh monitoring/*.sh
    
    # Run installation with all arguments passed through
    print_status "Running MongoDB installation..."
    ./install.sh "$@" 2>&1 | tee -a "$LOG_FILE"
    
    print_success "Quick installation completed!"
    print_status "Installation files available at: $INSTALL_DIR"
    print_status "Complete log saved to: $LOG_FILE"
}

main "$@"