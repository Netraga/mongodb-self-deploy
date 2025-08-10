#!/bin/bash

# MongoDB Security Audit Script
# Comprehensive security check for MongoDB installation

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_header() {
    echo -e "${BLUE}[AUDIT]${NC} $1"
    echo "======================================="
}

print_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
}

print_info() {
    echo -e "       $1"
}

# Initialize counters
PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

# Environment file check
ENV_FILE="${1:-.env}"
AUDIT_REPORT="/var/log/mongodb/security-audit-$(date +%Y%m%d_%H%M%S).log"

# Create log directory
mkdir -p /var/log/mongodb
exec > >(tee -a "$AUDIT_REPORT")
exec 2>&1

print_header "MongoDB Security Audit Report"
echo "Date: $(date)"
echo "System: $(uname -a)"
echo "Report saved to: $AUDIT_REPORT"
echo ""

# 1. Environment File Security
print_header "1. Environment File Security"

if [ -f "$ENV_FILE" ]; then
    ENV_PERMS=$(stat -c "%a" "$ENV_FILE" 2>/dev/null || stat -f "%A" "$ENV_FILE" 2>/dev/null)
    if [ "$ENV_PERMS" = "600" ]; then
        print_pass "Environment file has secure permissions (600)"
        ((PASS_COUNT++))
    else
        print_fail "Environment file permissions too open ($ENV_PERMS), should be 600"
        print_info "Fix: chmod 600 $ENV_FILE"
        ((FAIL_COUNT++))
    fi
else
    print_fail "Environment file not found: $ENV_FILE"
    ((FAIL_COUNT++))
fi

# 2. MongoDB Service Status
print_header "2. MongoDB Service Status"

if systemctl is-active --quiet mongod; then
    print_pass "MongoDB service is running"
    ((PASS_COUNT++))
else
    print_fail "MongoDB service is not running"
    ((FAIL_COUNT++))
fi

if systemctl is-enabled --quiet mongod; then
    print_pass "MongoDB service is enabled for startup"
    ((PASS_COUNT++))
else
    print_warn "MongoDB service not enabled for automatic startup"
    ((WARN_COUNT++))
fi

# 3. Configuration Security
print_header "3. MongoDB Configuration Security"

CONFIG_FILE="/etc/mongod.conf"
if [ -f "$CONFIG_FILE" ]; then
    # Check if authentication is enabled
    if grep -q "authorization: enabled" "$CONFIG_FILE"; then
        print_pass "Authentication is enabled"
        ((PASS_COUNT++))
    else
        print_fail "Authentication is NOT enabled - CRITICAL SECURITY RISK"
        print_info "Fix: Run ./configure-security.sh"
        ((FAIL_COUNT++))
    fi
    
    # Check bind IP configuration
    if grep -q "bindIp.*127.0.0.1" "$CONFIG_FILE"; then
        print_pass "MongoDB bound to localhost (secure)"
        ((PASS_COUNT++))
    else
        print_warn "MongoDB may be bound to external interfaces"
        print_info "Ensure firewall rules are properly configured"
        ((WARN_COUNT++))
    fi
    
    # Check if JavaScript is enabled
    if grep -q "javascriptEnabled.*false" "$CONFIG_FILE"; then
        print_pass "JavaScript execution is disabled"
        ((PASS_COUNT++))
    else
        print_warn "JavaScript execution is enabled (potential security risk)"
        print_info "Consider disabling if not needed"
        ((WARN_COUNT++))
    fi
    
else
    print_fail "MongoDB configuration file not found"
    ((FAIL_COUNT++))
fi

# 4. File Permissions
print_header "4. File Permissions Security"

# Check MongoDB data directory
DATA_DIR="/var/lib/mongodb"
if [ -d "$DATA_DIR" ]; then
    DATA_OWNER=$(stat -c "%U:%G" "$DATA_DIR" 2>/dev/null || stat -f "%Su:%Sg" "$DATA_DIR" 2>/dev/null)
    if [ "$DATA_OWNER" = "mongodb:mongodb" ]; then
        print_pass "MongoDB data directory has correct ownership"
        ((PASS_COUNT++))
    else
        print_fail "MongoDB data directory ownership incorrect: $DATA_OWNER"
        ((FAIL_COUNT++))
    fi
fi

# Check log directory
LOG_DIR="/var/log/mongodb"
if [ -d "$LOG_DIR" ]; then
    LOG_OWNER=$(stat -c "%U:%G" "$LOG_DIR" 2>/dev/null || stat -f "%Su:%Sg" "$LOG_DIR" 2>/dev/null)
    if [ "$LOG_OWNER" = "mongodb:mongodb" ]; then
        print_pass "MongoDB log directory has correct ownership"
        ((PASS_COUNT++))
    else
        print_fail "MongoDB log directory ownership incorrect: $LOG_OWNER"
        ((FAIL_COUNT++))
    fi
fi

# 5. Network Security
print_header "5. Network Security"

# Check if MongoDB port is open to public
if command -v ss >/dev/null; then
    LISTEN_CHECK=$(ss -tuln | grep ":27017" || true)
    if echo "$LISTEN_CHECK" | grep -q "0.0.0.0:27017\|:::27017"; then
        print_warn "MongoDB is listening on all interfaces"
        print_info "Ensure firewall rules restrict access"
        ((WARN_COUNT++))
    else
        print_pass "MongoDB is not listening on all public interfaces"
        ((PASS_COUNT++))
    fi
fi

# Check firewall status
if command -v ufw >/dev/null; then
    if ufw status | grep -q "Status: active"; then
        print_pass "UFW firewall is active"
        ((PASS_COUNT++))
        
        # Check if MongoDB port is protected
        if ufw status | grep -q "27017"; then
            print_pass "MongoDB port has specific firewall rules"
            ((PASS_COUNT++))
        else
            print_warn "No specific firewall rules for MongoDB port"
            ((WARN_COUNT++))
        fi
    else
        print_fail "UFW firewall is not active"
        print_info "Fix: sudo ufw enable"
        ((FAIL_COUNT++))
    fi
fi

# 6. SSL/TLS Configuration
print_header "6. SSL/TLS Security"

SSL_DIR="/etc/mongodb/ssl"
if [ -d "$SSL_DIR" ]; then
    print_pass "SSL directory exists"
    ((PASS_COUNT++))
    
    if [ -f "$SSL_DIR/mongodb.pem" ]; then
        print_pass "SSL certificate file found"
        ((PASS_COUNT++))
        
        # Check certificate expiry
        CERT_EXPIRY=$(openssl x509 -in "$SSL_DIR/mongodb.pem" -noout -enddate 2>/dev/null | cut -d= -f2 || echo "Unknown")
        if [ "$CERT_EXPIRY" != "Unknown" ]; then
            print_info "Certificate expires: $CERT_EXPIRY"
            
            # Check if certificate expires in next 30 days
            if openssl x509 -in "$SSL_DIR/mongodb.pem" -noout -checkend 2592000 >/dev/null 2>&1; then
                print_pass "SSL certificate is valid for next 30 days"
                ((PASS_COUNT++))
            else
                print_warn "SSL certificate expires within 30 days"
                ((WARN_COUNT++))
            fi
        fi
    else
        print_warn "SSL certificate not found"
        print_info "Run ./setup-ssl.sh to enable SSL/TLS"
        ((WARN_COUNT++))
    fi
else
    print_warn "SSL not configured"
    print_info "Consider enabling SSL/TLS for production"
    ((WARN_COUNT++))
fi

# 7. System Limits
print_header "7. System Limits"

# Check if systemd overrides exist
if [ -f "/etc/systemd/system/mongod.service.d/override.conf" ]; then
    print_pass "Systemd service overrides configured"
    ((PASS_COUNT++))
else
    print_warn "Systemd service limits not optimized"
    print_info "Run ./setup-systemd-limits.sh"
    ((WARN_COUNT++))
fi

# Check transparent huge pages
if [ -f "/sys/kernel/mm/transparent_hugepage/enabled" ]; then
    THP_STATUS=$(cat /sys/kernel/mm/transparent_hugepage/enabled)
    if echo "$THP_STATUS" | grep -q "\[never\]"; then
        print_pass "Transparent Huge Pages disabled"
        ((PASS_COUNT++))
    else
        print_fail "Transparent Huge Pages NOT disabled"
        print_info "Run ./setup-systemd-limits.sh to disable"
        ((FAIL_COUNT++))
    fi
fi

# 8. Backup Security
print_header "8. Backup Security"

BACKUP_DIR="/var/backups/mongodb"
if [ -d "$BACKUP_DIR" ]; then
    print_pass "Backup directory exists"
    ((PASS_COUNT++))
    
    BACKUP_PERMS=$(stat -c "%a" "$BACKUP_DIR" 2>/dev/null || stat -f "%A" "$BACKUP_DIR" 2>/dev/null)
    if [ "$BACKUP_PERMS" = "700" ]; then
        print_pass "Backup directory has secure permissions"
        ((PASS_COUNT++))
    else
        print_warn "Backup directory permissions could be more secure ($BACKUP_PERMS)"
        ((WARN_COUNT++))
    fi
    
    # Check recent backups
    RECENT_BACKUP=$(find "$BACKUP_DIR" -name "*.tar.gz" -mtime -2 | wc -l)
    if [ "$RECENT_BACKUP" -gt 0 ]; then
        print_pass "Recent backup files found"
        ((PASS_COUNT++))
    else
        print_warn "No recent backups found"
        ((WARN_COUNT++))
    fi
else
    print_warn "Backup directory not found"
    ((WARN_COUNT++))
fi

# 9. Log Security
print_header "9. Log Security"

# Check log rotation
if [ -f "/etc/logrotate.d/mongodb" ]; then
    print_pass "Log rotation configured"
    ((PASS_COUNT++))
else
    print_warn "Log rotation not configured"
    print_info "Install configs/logrotate-mongodb"
    ((WARN_COUNT++))
fi

# Check for authentication failures
if [ -f "/var/log/mongodb/mongod.log" ]; then
    AUTH_FAILURES=$(grep -c "Authentication failed" /var/log/mongodb/mongod.log 2>/dev/null || echo "0")
    if [ "$AUTH_FAILURES" -eq 0 ]; then
        print_pass "No recent authentication failures"
        ((PASS_COUNT++))
    elif [ "$AUTH_FAILURES" -lt 10 ]; then
        print_warn "$AUTH_FAILURES authentication failures found"
        ((WARN_COUNT++))
    else
        print_fail "$AUTH_FAILURES authentication failures found - potential attack"
        ((FAIL_COUNT++))
    fi
fi

# 10. User Account Security
print_header "10. User Account Security"

if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
    
    # Check if default passwords are still in use
    if echo "${MONGODB_ADMIN_PASSWORD:-}" | grep -q "Admin#MongoDB2025"; then
        print_fail "Default admin password detected - CHANGE IMMEDIATELY"
        ((FAIL_COUNT++))
    else
        print_pass "Admin password appears to be customized"
        ((PASS_COUNT++))
    fi
    
    if echo "${MONGODB_STAGING_PASSWORD:-}" | grep -q "SKnkdAHSDkrePass2025"; then
        print_fail "Default staging password detected - CHANGE IMMEDIATELY"
        ((FAIL_COUNT++))
    else
        print_pass "Staging password appears to be customized"
        ((PASS_COUNT++))
    fi
fi

# Summary
print_header "SECURITY AUDIT SUMMARY"

echo "Total Checks: $((PASS_COUNT + WARN_COUNT + FAIL_COUNT))"
echo "Passed: $PASS_COUNT"
echo "Warnings: $WARN_COUNT"
echo "Failed: $FAIL_COUNT"
echo ""

if [ $FAIL_COUNT -eq 0 ] && [ $WARN_COUNT -eq 0 ]; then
    print_pass "EXCELLENT: All security checks passed!"
elif [ $FAIL_COUNT -eq 0 ]; then
    print_warn "GOOD: No critical failures, but $WARN_COUNT warnings to address"
elif [ $FAIL_COUNT -le 2 ]; then
    print_warn "MODERATE: $FAIL_COUNT critical issues need immediate attention"
else
    print_fail "CRITICAL: $FAIL_COUNT security failures - IMMEDIATE ACTION REQUIRED"
fi

echo ""
echo "Report saved to: $AUDIT_REPORT"

# Exit with appropriate code
if [ $FAIL_COUNT -gt 0 ]; then
    exit 1
else
    exit 0
fi