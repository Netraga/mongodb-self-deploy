# 100% FREE MongoDB IP Protection Guide

## 🆓 **Completely FREE Methods to Hide Your MongoDB Server IP**

No paid services, no subscriptions, no hidden costs! Here are proven free methods to protect your MongoDB server IP address.

---

## 🔒 **Method 1: SSH Tunneling (Recommended - Easiest)**

### **How It Works:**
```
Client → SSH Tunnel → Your Hidden MongoDB Server
```

Instead of connecting directly to your server IP, clients connect through an encrypted SSH tunnel.

### **Setup on Server:**

1. **Ensure SSH is properly configured:**
```bash
# Edit SSH config for security
sudo nano /etc/ssh/sshd_config

# Add these lines:
PermitTunnel yes
GatewayPorts yes
AllowTcpForwarding yes

# Restart SSH
sudo systemctl restart ssh
```

2. **Configure MongoDB to bind only to localhost:**
```bash
# Edit MongoDB config
sudo nano /etc/mongod.conf

# Set bind IP to localhost only
net:
  bindIp: 127.0.0.1
  port: 27017

# Restart MongoDB
sudo systemctl restart mongod
```

3. **Update firewall to block direct MongoDB access:**
```bash
# Block direct access to MongoDB port
sudo ufw deny 27017
sudo ufw allow ssh
sudo ufw reload
```

### **Client Connection:**

**One-time setup per client:**
```bash
# Create SSH tunnel (runs in background)
ssh -fN -L 27017:localhost:27017 root@YOUR_SERVER_IP

# Now connect to localhost instead of server IP
mongosh --host localhost --port 27017 -u adminUser --authenticationDatabase admin
```

**Application connection string:**
```
mongodb://username:password@localhost:27017/database?authSource=admin
```

### **Automation Script for Clients:**

```bash
#!/bin/bash
# ssh-tunnel-mongodb.sh

SERVER_IP="YOUR_SERVER_IP"
SERVER_USER="root"  # or your SSH user
LOCAL_PORT="27017"

echo "Starting SSH tunnel to MongoDB server..."

# Check if tunnel already exists
if pgrep -f "ssh.*$SERVER_IP.*27017" > /dev/null; then
    echo "✅ SSH tunnel already running"
    exit 0
fi

# Start SSH tunnel
ssh -fN -L $LOCAL_PORT:localhost:27017 $SERVER_USER@$SERVER_IP

if [ $? -eq 0 ]; then
    echo "✅ SSH tunnel established successfully!"
    echo "Connect to: localhost:$LOCAL_PORT"
else
    echo "❌ Failed to establish SSH tunnel"
    exit 1
fi
```

---

## 🔒 **Method 2: WireGuard VPN (Most Secure)**

### **Why WireGuard:**
- **100% free** and open source
- **Ultra-fast** - 2x faster than OpenVPN
- **Simple setup** - Only 4,000 lines of code
- **Perfect for MongoDB** - Creates private network

### **Server Setup:**

```bash
# Install WireGuard
sudo apt update
sudo apt install wireguard -y

# Generate server keys
wg genkey | tee /etc/wireguard/privatekey | wg pubkey | tee /etc/wireguard/publickey

# Create server config
sudo nano /etc/wireguard/wg0.conf
```

**Server Configuration (`/etc/wireguard/wg0.conf`):**
```ini
[Interface]
PrivateKey = SERVER_PRIVATE_KEY_HERE
Address = 10.0.0.1/24
ListenPort = 51820
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

# Client 1
[Peer]
PublicKey = CLIENT_1_PUBLIC_KEY_HERE
AllowedIPs = 10.0.0.2/32

# Client 2
[Peer]
PublicKey = CLIENT_2_PUBLIC_KEY_HERE
AllowedIPs = 10.0.0.3/32
```

**Configure MongoDB for VPN access only:**
```yaml
# /etc/mongod.conf
net:
  bindIp: 127.0.0.1,10.0.0.1  # Localhost + VPN IP
  port: 27017
```

**Start WireGuard:**
```bash
# Enable IP forwarding
echo 'net.ipv4.ip_forward=1' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# Start WireGuard
sudo systemctl enable wg-quick@wg0
sudo systemctl start wg-quick@wg0

# Configure firewall
sudo ufw allow 51820/udp  # WireGuard port
sudo ufw deny 27017       # Block direct MongoDB access
```

### **Client Setup:**

**Generate client keys:**
```bash
# On client machine
wg genkey | tee privatekey | wg pubkey | tee publickey
```

**Client Configuration (`client.conf`):**
```ini
[Interface]
PrivateKey = CLIENT_PRIVATE_KEY_HERE
Address = 10.0.0.2/32
DNS = 8.8.8.8

[Peer]
PublicKey = SERVER_PUBLIC_KEY_HERE
Endpoint = YOUR_SERVER_IP:51820
AllowedIPs = 10.0.0.0/24
PersistentKeepalive = 20
```

**Connect:**
```bash
# Start VPN connection
sudo wg-quick up client

# Now connect to MongoDB via VPN IP
mongosh --host 10.0.0.1 --port 27017 -u adminUser --authenticationDatabase admin

# Application connection string
mongodb://username:password@10.0.0.1:27017/database?authSource=admin
```

---

## 🔒 **Method 3: Nginx Reverse Proxy (Port Obfuscation)**

### **Setup Nginx TCP Proxy:**

```bash
# Install Nginx with stream module
sudo apt update
sudo apt install nginx-full -y

# Create stream configuration
sudo nano /etc/nginx/nginx.conf
```

**Add to `/etc/nginx/nginx.conf` (outside http block):**
```nginx
# Add this at the end of the file, outside http block
stream {
    # MongoDB proxy
    upstream mongodb_backend {
        server 127.0.0.1:27017;
    }
    
    server {
        listen 9999;  # Custom port instead of 27017
        proxy_pass mongodb_backend;
        proxy_timeout 1s;
        proxy_responses 1;
        proxy_connect_timeout 1s;
    }
}
```

**Configure firewall:**
```bash
# Allow custom port, deny default MongoDB port
sudo ufw allow 9999
sudo ufw deny 27017
sudo ufw reload

# Restart Nginx
sudo systemctl restart nginx
```

**Client connection:**
```bash
# Connect to custom port instead of 27017
mongosh --host YOUR_SERVER_IP --port 9999 -u adminUser --authenticationDatabase admin

# Application connection string
mongodb://username:password@YOUR_SERVER_IP:9999/database?authSource=admin
```

---

## 🔒 **Method 4: Multiple Server Setup (Ultimate Protection)**

### **Architecture:**
```
Client → Proxy Server (Cheap VPS) → Your Hidden MongoDB Server
```

### **Setup:**

1. **Get a cheap VPS** ($2.50-5/month) as proxy server
2. **Install Nginx or HAProxy** on proxy server
3. **Configure proxy** to forward to your hidden MongoDB server
4. **Clients connect** to proxy server IP, never see your real server

**Proxy Server Configuration (HAProxy):**
```
# /etc/haproxy/haproxy.cfg
global
    maxconn 4096

defaults
    mode tcp
    timeout connect 5000ms
    timeout client 50000ms
    timeout server 50000ms

frontend mongodb_frontend
    bind *:27017
    default_backend mongodb_backend

backend mongodb_backend
    server mongodb1 YOUR_HIDDEN_SERVER_IP:27017 check
```

---

## 🆚 **Free Methods Comparison**

| Method | Setup Difficulty | Security | Performance | Cost |
|--------|-----------------|----------|-------------|------|
| SSH Tunnel | ⭐ Easy | ⭐⭐⭐⭐ High | ⭐⭐⭐ Good | 🆓 Free |
| WireGuard VPN | ⭐⭐ Medium | ⭐⭐⭐⭐⭐ Highest | ⭐⭐⭐⭐⭐ Excellent | 🆓 Free |
| Nginx Proxy | ⭐⭐ Medium | ⭐⭐ Medium | ⭐⭐⭐⭐ Very Good | 🆓 Free |
| Multiple Servers | ⭐⭐⭐ Hard | ⭐⭐⭐⭐⭐ Highest | ⭐⭐⭐⭐ Very Good | 💰 $2.50+/month |

## 🎯 **Recommended FREE Setup**

### **For Most Users: SSH Tunneling**
- Easiest to set up
- No additional software needed
- Works with existing SSH infrastructure
- Perfect for small teams

### **For High Security: WireGuard VPN**
- Best security and performance
- Creates private network
- Scales well for multiple clients
- Modern encryption

### **Quick Start Commands:**

**Option 1 - SSH Tunnel:**
```bash
# Server setup
sudo ufw deny 27017
sudo ufw allow ssh

# Client connection
ssh -fN -L 27017:localhost:27017 root@YOUR_SERVER_IP
mongosh --host localhost --port 27017 -u adminUser --authenticationDatabase admin
```

**Option 2 - WireGuard:**
```bash
# Server setup
sudo apt install wireguard -y
# [Configure as shown above]

# Client setup  
sudo wg-quick up client.conf
mongosh --host 10.0.0.1 --port 27017 -u adminUser --authenticationDatabase admin
```

## 🔐 **Security Benefits:**

✅ **Server IP completely hidden** from clients  
✅ **Encrypted connections** (SSH/WireGuard)  
✅ **No direct port 27017 access** from internet  
✅ **Custom ports** to avoid automated scans  
✅ **VPN-only access** for maximum security  
✅ **No ongoing costs** - completely free!  

Your MongoDB server IP is now **completely hidden** without spending a single dollar! 🎉