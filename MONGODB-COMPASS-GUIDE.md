# MongoDB Compass Connection Guide

MongoDB Compass is the official GUI for MongoDB that allows you to explore and manipulate your data with a user-friendly interface.

## Download MongoDB Compass

1. Visit: https://www.mongodb.com/products/compass
2. Download the appropriate version for your OS (Windows/Mac/Linux)
3. Install following the standard procedure for your OS

## Connection Methods

### Method 1: Without SSL/TLS (Development)

1. **Open MongoDB Compass**

2. **Connection String**:
   ```
   mongodb://username:password@YOUR_DOMAIN.example.com:27017/?authSource=admin
   ```

3. **Or use Advanced Connection Options**:
   - **Hostname**: `YOUR_DOMAIN.example.com`
   - **Port**: `27017`
   - **Authentication**: Username/Password
   - **Username**: `adminUser` (or your specific user)
   - **Password**: Your password
   - **Authentication Database**: `admin`

### Method 2: With SSL/TLS (Production)

1. **First, copy the CA certificate from server**:
   ```bash
   scp root@YOUR_DOMAIN.example.com:/etc/mongodb/ssl/ca.crt ~/mongodb-ca.crt
   ```

2. **Connection String with SSL**:
   ```
   mongodb://username:password@YOUR_DOMAIN.example.com:27017/?authSource=admin&tls=true&tlsCAFile=/path/to/mongodb-ca.crt
   ```

3. **Or use Advanced Connection Options**:
   - Click "Advanced Connection Options"
   - Go to "TLS/SSL" tab
   - Enable "SSL"
   - **Certificate Authority**: Browse and select the `mongodb-ca.crt` file
   - Fill in authentication details as above

## User-Specific Connections

### Admin User (Full Access)
```
mongodb://adminUser:Admin%23MongoDB2025%21Secure@YOUR_DOMAIN.example.com:27017/?authSource=admin
```
**Note**: Password is URL-encoded. `#` becomes `%23`, `!` becomes `%21`

### Staging User
```
mongodb://digisvcStaging:SKnkdAHSDkrePass2025%21@YOUR_DOMAIN.example.com:27017/digisvc2025Staging?authSource=admin
```

### Test User
```
mongodb://digisvcTest:TestPass%232025%21Secure@YOUR_DOMAIN.example.com:27017/digisvc2025Test?authSource=admin
```

### Read-Only Reporting User
```
mongodb://reportingUser:Report%232025%21ReadOnly@YOUR_DOMAIN.example.com:27017/?authSource=admin
```

## Troubleshooting Connection Issues

### 1. "Connection Refused" Error
- **Check MongoDB is running**: SSH to server and run `sudo systemctl status mongod`
- **Verify firewall**: Your IP must be whitelisted. Ask admin to run:
  ```bash
  sudo mongodb-allow-ip.sh YOUR_IP_ADDRESS
  ```

### 2. "Authentication Failed" Error
- Verify username and password are correct
- Ensure `authSource=admin` is in connection string
- Check password special characters are URL-encoded

### 3. "SSL Certificate Error"
- Ensure you have the correct `ca.crt` file
- Verify the certificate path is absolute, not relative
- For development, you can temporarily disable certificate validation (not recommended for production)

### 4. "Timeout" Error
- Check network connectivity: `ping YOUR_DOMAIN.example.com`
- Verify DNS resolution: `nslookup YOUR_DOMAIN.example.com`
- Ensure port 27017 is not blocked by local firewall

## Compass Features to Explore

### 1. **Schema Analysis**
- Navigate to any collection
- Click "Schema" tab to analyze document structure

### 2. **Index Management**
- Go to collection > "Indexes" tab
- Create, view, and drop indexes

### 3. **Performance Monitoring**
- Click "Performance" tab
- View real-time metrics

### 4. **Query Builder**
- Visual query builder for complex queries
- Supports aggregation pipeline builder

### 5. **Document Validation**
- Set validation rules
- Test documents against rules

## Security Best Practices

1. **Never save passwords** in Compass favorites in shared computers
2. **Use read-only users** for data exploration
3. **Disconnect when done** - Don't leave connections open
4. **Use SSL/TLS** for production databases
5. **Limit connection time** - Set appropriate timeouts

## Useful Compass Shortcuts

- `Ctrl/Cmd + K`: Quick collection search
- `Ctrl/Cmd + Enter`: Execute query
- `Ctrl/Cmd + Shift + F`: Format query
- `F5`: Refresh current view
- `Ctrl/Cmd + D`: Duplicate document

## Export Connection for Team

1. In Compass, go to "Favorites"
2. Click "..." next to your connection
3. Select "Copy Connection String"
4. Share with team (remove password)

## Connection String Builder

For complex scenarios, use the connection string builder:
https://www.mongodb.com/docs/manual/reference/connection-string/

## Example Session

1. **Connect to MongoDB**
2. **Select Database**: `digisvc2025Staging`
3. **Query Collection**:
   ```javascript
   // Find recent documents
   { createdAt: { $gte: new Date('2024-01-01') } }
   
   // With projection
   { status: "active" }
   // Project: { name: 1, email: 1, _id: 0 }
   ```
4. **Create Index**:
   - Navigate to Indexes tab
   - Click "Create Index"
   - Add field: `{ createdAt: -1 }`
   - Create

## Additional Resources

- MongoDB Compass Docs: https://docs.mongodb.com/compass/
- Video Tutorials: https://university.mongodb.com/
- Connection Troubleshooting: https://docs.mongodb.com/manual/reference/connection-string/