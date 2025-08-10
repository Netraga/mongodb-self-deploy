#!/bin/bash

# MongoDB Restore Script (Secure Version)
# Uses environment variables for all credentials

set -euo pipefail

# Configuration
ENV_FILE="${1:-.env}"
BACKUP_FILE="$2"
DROP_OPTION=""

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

# Check arguments
if [ $# -lt 2 ]; then
    print_error "Usage: $0 <env-file> <backup_file.tar.gz> [--drop]"
    echo ""
    echo "Examples:"
    echo "  $0 .env mongodb_backup_20240101_020000.tar.gz"
    echo "  $0 .env mongodb_backup_20240101_020000.tar.gz --drop"
    exit 1
fi

# Check for --drop option
if [ $# -eq 3 ] && [ "$3" = "--drop" ]; then
    DROP_OPTION="--drop"
    print_warning "Will drop existing collections before restore!"
fi

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
)

for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var:-}" ]; then
        print_error "Required environment variable not set: $var"
        exit 1
    fi
done

# Check if backup file exists
if [ ! -f "$BACKUP_FILE" ]; then
    # Check if file exists in backup directory
    if [ -f "$BACKUP_DIR/$BACKUP_FILE" ]; then
        BACKUP_FILE="$BACKUP_DIR/$BACKUP_FILE"
    else
        print_error "Backup file not found: $BACKUP_FILE"
        print_status "Available backups:"
        ls -lh "$BACKUP_DIR"/mongodb_backup_*.tar.gz 2>/dev/null || echo "No backups found"
        exit 1
    fi
fi

print_status "Starting MongoDB restore..."
print_status "Backup file: $BACKUP_FILE"

# Create temporary directory for extraction
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

print_status "Extracting backup to temporary directory..."

# Extract the backup
if ! tar -xzf "$BACKUP_FILE" -C "$TEMP_DIR"; then
    print_error "Failed to extract backup file"
    exit 1
fi

# Find the extracted directory
EXTRACTED_DIR=$(find "$TEMP_DIR" -maxdepth 1 -type d -name "mongodb_backup_*" | head -1)

if [ -z "$EXTRACTED_DIR" ]; then
    print_error "No valid backup directory found in archive!"
    exit 1
fi

# Confirm before proceeding
print_warning "This will restore data to MongoDB at $MONGODB_HOST:$MONGODB_PORT"
print_warning "Affected databases will be modified!"
if [ ! -z "$DROP_OPTION" ]; then
    print_warning "Existing collections will be DROPPED!"
fi

read -p "Are you sure you want to continue? (yes/no): " -r
if [[ ! $REPLY =~ ^[Yy]es$ ]]; then
    print_status "Restore cancelled."
    exit 0
fi

# Build mongorestore command
MONGORESTORE_CMD="mongorestore"
MONGORESTORE_CMD="$MONGORESTORE_CMD --host=$MONGODB_HOST"
MONGORESTORE_CMD="$MONGORESTORE_CMD --port=$MONGODB_PORT"
MONGORESTORE_CMD="$MONGORESTORE_CMD --username=$MONGODB_BACKUP_USER"
MONGORESTORE_CMD="$MONGORESTORE_CMD --password=$MONGODB_BACKUP_PASSWORD"
MONGORESTORE_CMD="$MONGORESTORE_CMD --authenticationDatabase=admin"
MONGORESTORE_CMD="$MONGORESTORE_CMD --gzip"
MONGORESTORE_CMD="$MONGORESTORE_CMD $DROP_OPTION"
MONGORESTORE_CMD="$MONGORESTORE_CMD $EXTRACTED_DIR"

# Add SSL options if enabled
if [ "${MONGODB_SSL_ENABLED:-false}" = "true" ]; then
    print_status "Using SSL/TLS connection..."
    MONGORESTORE_CMD="$MONGORESTORE_CMD --ssl"
    if [ ! -z "${MONGODB_SSL_CA_PATH:-}" ]; then
        MONGORESTORE_CMD="$MONGORESTORE_CMD --sslCAFile=$MONGODB_SSL_CA_PATH"
    fi
fi

# Perform the restore
print_status "Restoring MongoDB data..."
if eval "$MONGORESTORE_CMD"; then
    print_status "Restore completed successfully!"
else
    print_error "Restore failed!"
    exit 1
fi

# Log restore completion
LOG_FILE="$BACKUP_DIR/restore.log"
echo "$(date '+%Y-%m-%d %H:%M:%S') - Restore completed from: $(basename $BACKUP_FILE)" >> "$LOG_FILE"
chmod 600 "$LOG_FILE"

print_status "Restore process completed!"

# Optional: Send notification
if [ ! -z "${ALERT_EMAIL:-}" ]; then
    echo "MongoDB restore completed successfully from: $(basename $BACKUP_FILE)" | mail -s "MongoDB Restore Success" "$ALERT_EMAIL" 2>/dev/null || true
fi

if [ ! -z "${SLACK_WEBHOOK_URL:-}" ]; then
    curl -X POST -H 'Content-type: application/json' \
        --data "{\"text\":\"🔄 MongoDB restore completed from: $(basename $BACKUP_FILE)\"}" \
        "$SLACK_WEBHOOK_URL" 2>/dev/null || true
fi