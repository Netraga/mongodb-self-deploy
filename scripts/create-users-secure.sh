#!/bin/bash

# MongoDB User Creation Script (Secure Version)
# Uses environment variables for all credentials

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

# Check if environment file exists
ENV_FILE="${1:-.env}"
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
    "MONGODB_ADMIN_USER"
    "MONGODB_ADMIN_PASSWORD"
    "MONGODB_STAGING_USER"
    "MONGODB_STAGING_PASSWORD"
    "MONGODB_STAGING_DB"
    "MONGODB_TEST_USER"
    "MONGODB_TEST_PASSWORD"
    "MONGODB_TEST_DB"
    "MONGODB_MONITORING_USER"
    "MONGODB_MONITORING_PASSWORD"
    "MONGODB_BACKUP_USER"
    "MONGODB_BACKUP_PASSWORD"
    "MONGODB_REPORTING_USER"
    "MONGODB_REPORTING_PASSWORD"
)

for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var:-}" ]; then
        print_error "Required environment variable not set: $var"
        exit 1
    fi
done

# Check if MongoDB is running
if ! systemctl is-active --quiet mongod; then
    print_error "MongoDB is not running. Please start it first."
    exit 1
fi

print_status "Creating MongoDB users..."

# Create admin user
print_status "Creating admin user..."
mongosh admin --eval "
db.createUser({
  user: '$MONGODB_ADMIN_USER',
  pwd: '$MONGODB_ADMIN_PASSWORD',
  roles: [
    { role: 'userAdminAnyDatabase', db: 'admin' },
    { role: 'dbAdminAnyDatabase', db: 'admin' },
    { role: 'readWriteAnyDatabase', db: 'admin' },
    { role: 'clusterAdmin', db: 'admin' },
    { role: 'restore', db: 'admin' },
    { role: 'backup', db: 'admin' },
    { role: 'root', db: 'admin' }
  ]
})
"

# Create staging user with least privilege
print_status "Creating staging user..."
mongosh admin --eval "
db.createUser({
  user: '$MONGODB_STAGING_USER',
  pwd: '$MONGODB_STAGING_PASSWORD',
  roles: [
    { role: 'readWrite', db: '$MONGODB_STAGING_DB' },
    { role: 'dbAdmin', db: '$MONGODB_STAGING_DB' }
  ]
})
"

# Create test user with least privilege
print_status "Creating test user..."
mongosh admin --eval "
db.createUser({
  user: '$MONGODB_TEST_USER',
  pwd: '$MONGODB_TEST_PASSWORD',
  roles: [
    { role: 'readWrite', db: '$MONGODB_TEST_DB' },
    { role: 'dbAdmin', db: '$MONGODB_TEST_DB' }
  ]
})
"

# Create monitoring user (read-only)
print_status "Creating monitoring user..."
mongosh admin --eval "
db.createUser({
  user: '$MONGODB_MONITORING_USER',
  pwd: '$MONGODB_MONITORING_PASSWORD',
  roles: [
    { role: 'clusterMonitor', db: 'admin' },
    { role: 'read', db: 'admin' },
    { role: 'read', db: 'local' }
  ]
})
"

# Create backup user
print_status "Creating backup user..."
mongosh admin --eval "
db.createUser({
  user: '$MONGODB_BACKUP_USER',
  pwd: '$MONGODB_BACKUP_PASSWORD',
  roles: [
    { role: 'backup', db: 'admin' },
    { role: 'restore', db: 'admin' }
  ]
})
"

# Create read-only reporting user
print_status "Creating read-only reporting user..."
mongosh admin --eval "
db.createUser({
  user: '$MONGODB_REPORTING_USER',
  pwd: '$MONGODB_REPORTING_PASSWORD',
  roles: [
    { role: 'read', db: '$MONGODB_STAGING_DB' },
    { role: 'read', db: '$MONGODB_TEST_DB' }
  ]
})
"

# Create production user if defined
if [ ! -z "${MONGODB_PRODUCTION_USER:-}" ] && [ ! -z "${MONGODB_PRODUCTION_PASSWORD:-}" ]; then
    print_status "Creating production user..."
    mongosh admin --eval "
    db.createUser({
      user: '$MONGODB_PRODUCTION_USER',
      pwd: '$MONGODB_PRODUCTION_PASSWORD',
      roles: [
        { role: 'readWrite', db: '$MONGODB_PRODUCTION_DB' },
        { role: 'dbAdmin', db: '$MONGODB_PRODUCTION_DB' }
      ]
    })
    "
fi

print_status "All users created successfully!"
print_status ""
print_warning "IMPORTANT SECURITY NOTES:"
print_warning "1. Users have been created with LEAST PRIVILEGE principle"
print_warning "2. Application users only have access to their specific databases"
print_warning "3. Store the .env file securely and never commit it to version control"
print_warning "4. Regularly rotate passwords"
print_warning "5. Enable authentication: Run ./configure-security.sh"

# Create connection strings file (without passwords)
print_status "Creating connection string templates..."
cat > connection-strings-template.txt << EOF
MongoDB Connection String Templates
==================================

Replace PASSWORD with actual password from your secure .env file

Admin Connection:
mongosh -u $MONGODB_ADMIN_USER -p 'PASSWORD' --authenticationDatabase admin

Staging Application:
mongodb://$MONGODB_STAGING_USER:PASSWORD@\${MONGODB_HOST}:27017/$MONGODB_STAGING_DB?authSource=admin

Test Application:
mongodb://$MONGODB_TEST_USER:PASSWORD@\${MONGODB_HOST}:27017/$MONGODB_TEST_DB?authSource=admin

Monitoring:
mongodb://$MONGODB_MONITORING_USER:PASSWORD@\${MONGODB_HOST}:27017/admin?authSource=admin&readPreference=secondaryPreferred

With SSL/TLS:
mongodb://$MONGODB_STAGING_USER:PASSWORD@\${MONGODB_HOST}:27017/$MONGODB_STAGING_DB?authSource=admin&tls=true&tlsCAFile=/path/to/ca.crt
EOF

print_status "Connection string templates saved to: connection-strings-template.txt"