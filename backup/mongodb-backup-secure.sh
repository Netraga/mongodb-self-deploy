#!/bin/bash

# MongoDB Backup Script (Secure Version)
# Uses environment variables for all credentials

set -euo pipefail

# Configuration
ENV_FILE="${1:-.env}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

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

# Check if environment file exists
if [ ! -f "$ENV_FILE" ]; then
    print_error "Environment file not found: $ENV_FILE"
    print_error "Please create an .env file based on .env.example"
    exit 1
fi

# Load environment variables
print_status "Loading environment variables..."
set -a
source "$ENV_FILE"
set +a

# Validate required variables
REQUIRED_VARS=(
    "MONGODB_HOST"
    "MONGODB_PORT"
    "MONGODB_BACKUP_USER"
    "MONGODB_BACKUP_PASSWORD"
    "BACKUP_DIR"
    "BACKUP_RETENTION_DAYS"
)

for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var:-}" ]; then
        print_error "Required environment variable not set: $var"
        exit 1
    fi
done

# Set defaults
BACKUP_NAME="mongodb_backup_${TIMESTAMP}"
AUTH_DB="admin"

# Create backup directory if it doesn't exist
if [ ! -d "$BACKUP_DIR" ]; then
    print_status "Creating backup directory: $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
    chmod 700 "$BACKUP_DIR"  # Secure permissions
fi

# Start backup
print_status "Starting MongoDB backup..."
print_status "Backup name: $BACKUP_NAME"

# Build mongodump command
MONGODUMP_CMD="mongodump"
MONGODUMP_CMD="$MONGODUMP_CMD --host=$MONGODB_HOST"
MONGODUMP_CMD="$MONGODUMP_CMD --port=$MONGODB_PORT"
MONGODUMP_CMD="$MONGODUMP_CMD --username=$MONGODB_BACKUP_USER"
MONGODUMP_CMD="$MONGODUMP_CMD --password=$MONGODB_BACKUP_PASSWORD"
MONGODUMP_CMD="$MONGODUMP_CMD --authenticationDatabase=$AUTH_DB"
MONGODUMP_CMD="$MONGODUMP_CMD --out=$BACKUP_DIR/$BACKUP_NAME"
MONGODUMP_CMD="$MONGODUMP_CMD --gzip"

# Add SSL options if enabled
if [ "${MONGODB_SSL_ENABLED:-false}" = "true" ]; then
    print_status "Using SSL/TLS connection..."
    MONGODUMP_CMD="$MONGODUMP_CMD --ssl"
    if [ ! -z "${MONGODB_SSL_CA_PATH:-}" ]; then
        MONGODUMP_CMD="$MONGODUMP_CMD --sslCAFile=$MONGODB_SSL_CA_PATH"
    fi
fi

# Perform the backup
if eval "$MONGODUMP_CMD"; then
    print_status "Backup completed successfully!"
    
    # Create a compressed archive
    print_status "Creating compressed archive..."
    cd "$BACKUP_DIR"
    tar -czf "${BACKUP_NAME}.tar.gz" "$BACKUP_NAME"
    
    # Secure the archive
    chmod 600 "${BACKUP_NAME}.tar.gz"
    
    # Remove uncompressed directory
    rm -rf "$BACKUP_NAME"
    
    # Calculate backup size
    BACKUP_SIZE=$(du -h "${BACKUP_NAME}.tar.gz" | cut -f1)
    print_status "Backup size: $BACKUP_SIZE"
    
else
    print_error "Backup failed!"
    exit 1
fi

# Clean up old backups
print_status "Cleaning up old backups (keeping last $BACKUP_RETENTION_DAYS days)..."
find "$BACKUP_DIR" -name "mongodb_backup_*.tar.gz" -type f -mtime +$BACKUP_RETENTION_DAYS -delete

# List current backups
print_status "Current backups:"
ls -lh "$BACKUP_DIR"/mongodb_backup_*.tar.gz 2>/dev/null || echo "No backups found"

# Log backup completion
LOG_FILE="$BACKUP_DIR/backup.log"
echo "$(date '+%Y-%m-%d %H:%M:%S') - Backup completed: ${BACKUP_NAME}.tar.gz ($BACKUP_SIZE)" >> "$LOG_FILE"

# Secure log file
chmod 600 "$LOG_FILE"

print_status "Backup process completed!"

# Optional: Send notification
if [ ! -z "${ALERT_EMAIL:-}" ]; then
    echo "MongoDB backup completed successfully: ${BACKUP_NAME}.tar.gz ($BACKUP_SIZE)" | mail -s "MongoDB Backup Success" "$ALERT_EMAIL" 2>/dev/null || true
fi

if [ ! -z "${SLACK_WEBHOOK_URL:-}" ]; then
    curl -X POST -H 'Content-type: application/json' \
        --data "{\"text\":\"✅ MongoDB backup completed: ${BACKUP_NAME}.tar.gz ($BACKUP_SIZE)\"}" \
        "$SLACK_WEBHOOK_URL" 2>/dev/null || true
fi