# Hytale Docker Server

[![Build and Push](https://github.com/D4M13N-D3V/hytale-docker/actions/workflows/build-push.yml/badge.svg)](https://github.com/D4M13N-D3V/hytale-docker/actions/workflows/build-push.yml)
[![Helm Chart](https://img.shields.io/badge/helm-chart-blue)](https://github.com/D4M13N-D3V/hytale-docker/packages)

Docker and Kubernetes (Helm) deployment for Hytale dedicated game servers.

## Features

- Automatic server download and updates via official hytale-downloader
- Persistent storage for worlds, mods, configs, and backups
- Graceful shutdown handling
- Pre-release channel support
- Optional [playit.gg](https://playit.gg) tunnel for external access
- Helm chart for Kubernetes deployment

## Requirements

- Docker 20.10+ (for Docker deployment)
- Kubernetes 1.24+ (for Helm deployment)
- Helm 3.0+ (for Helm deployment)
- Minimum 4GB RAM (8GB recommended)

## Quick Start

### Docker Compose

```bash
# Clone the repository
git clone https://github.com/D4M13N-D3V/hytale-docker.git
cd hytale-docker

# Configure environment
cp .env.example .env
# Edit .env with your settings

# Start the server
docker-compose up -d

# View logs and get auth URL
docker-compose logs -f
```

### Kubernetes (Helm)

```bash
# Add the Helm repository
helm repo add hytale https://d4m13n-d3v.github.io/hytale-docker
helm repo update

# Install the chart
helm install hytale hytale/hytale-server -n hytale --create-namespace

# Or install from local chart
helm install hytale ./helm/hytale-server -n hytale --create-namespace

# View logs for auth URL
kubectl logs -f hytale-hytale-server-0 -n hytale
```

## Authentication

Hytale servers require OAuth authentication before players can connect.

1. Start the server and watch the logs
2. Look for the authentication URL:
   ```
   Please visit the following URL to authenticate:
   https://oauth.accounts.hytale.com/oauth2/device/verify?user_code=XXXXXXXX
   ```
3. Visit the URL and authorize the server

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `JAVA_MEMORY` | `8G` | JVM heap size |
| `SERVER_PORT` | `5520` | UDP port (QUIC protocol) |
| `AUTH_MODE` | `authenticated` | `authenticated` or `offline` |
| `PATCHLINE` | `release` | `release` or `pre-release` |
| `ENABLE_BACKUP` | `false` | Enable automatic backups |
| `BACKUP_FREQUENCY` | `30` | Backup interval (minutes) |
| `HYTALE_SERVER_SESSION_TOKEN` | - | Auth session token |
| `HYTALE_SERVER_IDENTITY_TOKEN` | - | Auth identity token |

### Helm Values

```yaml
# Image configuration
image:
  repository: ghcr.io/d4m13n-d3v/hytale-docker
  tag: latest

# Server settings
server:
  port: 5520
  memory: "8G"
  authMode: "authenticated"
  patchline: "release"
  backup:
    enabled: false
    frequency: 30

# Service configuration
service:
  type: NodePort
  port: 5520
  nodePort: ""  # Auto-assign or specify (30000-32767)

# Persistent storage
persistence:
  storageClass: "local-path"  # Adjust for your cluster
  universe:
    size: 10Gi
  mods:
    size: 1Gi
  logs:
    size: 1Gi

# Resource limits
resources:
  requests:
    memory: 8Gi
    cpu: "2"
  limits:
    memory: 10Gi
    cpu: "4"

# Playit.gg tunnel (optional)
playit:
  enabled: false
  secretKey: ""  # Get from playit.gg dashboard

# Auth tokens (use existingSecret for production)
auth:
  existingSecret: ""
  sessionToken: ""
  identityToken: ""
```

## Playit.gg Tunnel

[Playit.gg](https://playit.gg) provides free tunneling to make your server accessible without port forwarding.

### Docker Compose

Add playit as a service in `docker-compose.yml`:

```yaml
services:
  hytale-server:
    # ... existing config ...

  playit:
    image: ghcr.io/playit-cloud/playit-agent:0.16
    network_mode: host
    environment:
      - SECRET_KEY=your-secret-key-from-playit-dashboard
```

### Kubernetes

Enable playit in Helm values:

```bash
helm upgrade hytale hytale/hytale-server -n hytale \
  --set playit.enabled=true \
  --set playit.secretKey=your-secret-key-from-playit-dashboard
```

Or create a secret:

```bash
kubectl create secret generic playit-secret -n hytale \
  --from-literal=secret-key=your-secret-key

helm upgrade hytale hytale/hytale-server -n hytale \
  --set playit.enabled=true \
  --set playit.existingSecret=playit-secret
```

## Persistent Data

| Volume | Path | Description |
|--------|------|-------------|
| universe | `/data/universe` | World and player data |
| mods | `/data/mods` | Server modifications |
| logs | `/data/logs` | Server logs |
| config | `/data/config` | JSON config files |
| backups | `/data/backups` | Automatic backups |

## Networking

Hytale uses **QUIC protocol over UDP** on port **5520**.

### Firewall Rules

```bash
# Linux (ufw)
sudo ufw allow 5520/udp

# Linux (firewalld)
sudo firewall-cmd --add-port=5520/udp --permanent
sudo firewall-cmd --reload
```

## Commands

### Docker

```bash
docker-compose up -d          # Start
docker-compose down           # Stop
docker-compose logs -f        # Logs
docker-compose restart        # Restart
docker-compose exec hytale-server bash  # Shell
```

### Kubernetes

```bash
helm install hytale hytale/hytale-server -n hytale   # Install
helm upgrade hytale hytale/hytale-server -n hytale   # Upgrade
helm uninstall hytale -n hytale                       # Uninstall
kubectl logs -f hytale-hytale-server-0 -n hytale     # Logs
kubectl exec -it hytale-hytale-server-0 -n hytale -- bash  # Shell
```

## Troubleshooting

### Server won't start
- Check logs for errors
- Verify Java memory doesn't exceed available RAM
- Ensure port 5520/udp is available

### Players can't connect
- Verify authentication completed (check logs)
- Ensure UDP port 5520 is open
- Check playit.gg tunnel status if using

### Download fails
- Check network connectivity
- Try pre-release channel: `PATCHLINE=pre-release`

## Resources

- [Hytale Server Manual](https://support.hytale.com/hc/en-us/articles/45326769420827-Hytale-Server-Manual)
- [Hytale Hardware Requirements](https://hytale.com/news/2025/12/hytale-hardware-requirements)
- [Playit.gg Documentation](https://playit.gg/docs)

## License

MIT License
