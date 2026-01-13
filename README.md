# Hytale Docker Server

[![Build and Push](https://github.com/D4M13N-D3V/hytale-docker/actions/workflows/build-push.yml/badge.svg)](https://github.com/D4M13N-D3V/hytale-docker/actions/workflows/build-push.yml)
[![Release](https://github.com/D4M13N-D3V/hytale-docker/actions/workflows/release.yml/badge.svg)](https://github.com/D4M13N-D3V/hytale-docker/releases)
[![Helm Chart](https://img.shields.io/badge/helm-chart-blue)](https://d4m13n-d3v.github.io/hytale-docker)

Docker and Kubernetes (Helm) deployment for Hytale dedicated game servers.

## Features

- Automatic server download and updates via official hytale-downloader
- **Two-step OAuth authentication** with credential caching
- Persistent storage for worlds, mods, configs, and backups
- Graceful shutdown handling
- Pre-release channel support
- Optional [playit.gg](https://playit.gg) tunnel for external access (sidecar container)
- Helm chart for Kubernetes deployment with semantic versioning

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

# View logs for authentication URLs
docker-compose logs -f
```

### With Playit.gg Tunnel (Docker)

```bash
# Set your playit secret key in .env
echo "PLAYIT_SECRET_KEY=your-secret-key" >> .env

# Start with playit profile enabled
docker-compose --profile playit up -d
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

# View logs for authentication URLs
kubectl logs -f hytale-hytale-server-0 -n hytale
```

### With Playit.gg Tunnel (Kubernetes)

```bash
helm install hytale hytale/hytale-server -n hytale --create-namespace \
  --set playit.enabled=true \
  --set playit.secretKey=your-secret-key-from-playit-dashboard
```

## Authentication

Hytale servers require **two separate OAuth authentications**:

### Step 1: Downloader Authentication

On first startup, the hytale-downloader needs to authenticate to download server files:

```
Please visit the following URL to authenticate:
https://oauth.accounts.hytale.com/oauth2/device/verify?user_code=XXXXXXXX
```

Visit the URL and authorize. **These credentials are cached** in `/data/config/` and will be reused on subsequent restarts.

### Step 2: Server Authentication

After the server boots, it automatically triggers `auth login browser` to authenticate for player connections:

```
Please visit the following URL to authenticate:
https://oauth.accounts.hytale.com/oauth2/device/verify?user_code=YYYYYYYY
```

Visit this second URL and authorize. This allows players to connect to your server.

> **Note:** The server authentication needs to be completed each time the server restarts (session tokens expire after ~1 hour). For automated deployments, you can provide `HYTALE_SERVER_SESSION_TOKEN` and `HYTALE_SERVER_IDENTITY_TOKEN` environment variables.

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
| `HYTALE_SERVER_SESSION_TOKEN` | - | Server session token (for automated auth) |
| `HYTALE_SERVER_IDENTITY_TOKEN` | - | Server identity token (for automated auth) |
| `PLAYIT_SECRET_KEY` | - | Playit.gg secret key (Docker Compose) |

### Helm Values

```yaml
# Image configuration
image:
  repository: ghcr.io/d4m13n-d3v/hytale-docker
  pullPolicy: Always  # Recommended for 'latest' tag
  tag: "latest"

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
  enabled: true
  storageClass: "local-path"  # Adjust for your cluster
  universe:
    size: 10Gi
  mods:
    size: 1Gi
  logs:
    size: 1Gi
  config:
    size: 100Mi
  backups:
    size: 20Gi

# Resource limits
resources:
  requests:
    memory: 8Gi
    cpu: "2"
  limits:
    memory: 10Gi
    cpu: "4"

# Playit.gg tunnel (optional sidecar)
playit:
  enabled: false
  image:
    repository: ghcr.io/playit-cloud/playit-agent
    tag: "0.16"
  secretKey: ""  # Get from playit.gg dashboard
  existingSecret: ""  # Or use existing K8s secret

# Auth tokens (use existingSecret for production)
auth:
  existingSecret: ""
  sessionToken: ""
  identityToken: ""
```

## Playit.gg Tunnel

[Playit.gg](https://playit.gg) provides free tunneling to make your server accessible without port forwarding.

### Setup

1. Create an account at [playit.gg](https://playit.gg)
2. Create a new agent and get your secret key
3. Create a UDP tunnel for port 5520

### Docker Compose

```bash
# Add to .env file
PLAYIT_SECRET_KEY=your-secret-key-from-playit-dashboard

# Start with playit profile
docker-compose --profile playit up -d
```

### Kubernetes

```bash
# Using secret key directly
helm upgrade hytale hytale/hytale-server -n hytale \
  --set playit.enabled=true \
  --set playit.secretKey=your-secret-key

# Or using Kubernetes secret
kubectl create secret generic playit-secret -n hytale \
  --from-literal=secret-key=your-secret-key

helm upgrade hytale hytale/hytale-server -n hytale \
  --set playit.enabled=true \
  --set playit.existingSecret=playit-secret
```

### Custom Domain with Playit.gg

To use a custom domain (e.g., `play.yourdomain.com`):

1. Go to your playit.gg dashboard
2. Navigate to your tunnel settings
3. Set your domain's nameservers to playit.gg nameservers
4. Wait for DNS propagation (can take up to 24-48 hours)

See [Playit.gg External Domain Guide](https://playit.gg/support/external-domain-namecheap/) for details.

## Persistent Data

| Volume | Path | Description |
|--------|------|-------------|
| universe | `/data/universe` | World and player data |
| mods | `/data/mods` | Server modifications |
| logs | `/data/logs` | Server logs |
| config | `/data/config` | JSON config files + cached credentials |
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
docker-compose up -d                    # Start server
docker-compose --profile playit up -d   # Start with playit tunnel
docker-compose down                     # Stop
docker-compose logs -f                  # View logs
docker-compose restart                  # Restart
docker-compose exec hytale-server bash  # Shell access
```

### Kubernetes

```bash
# Installation
helm install hytale hytale/hytale-server -n hytale --create-namespace

# With playit enabled
helm install hytale hytale/hytale-server -n hytale --create-namespace \
  --set playit.enabled=true \
  --set playit.secretKey=your-key

# Upgrade
helm upgrade hytale hytale/hytale-server -n hytale

# Uninstall
helm uninstall hytale -n hytale

# View logs
kubectl logs -f hytale-hytale-server-0 -n hytale

# Shell access
kubectl exec -it hytale-hytale-server-0 -n hytale -- bash

# Check both containers (server + playit)
kubectl logs hytale-hytale-server-0 -n hytale -c hytale-server
kubectl logs hytale-hytale-server-0 -n hytale -c playit
```

## Troubleshooting

### Server won't start
- Check logs for errors: `docker-compose logs` or `kubectl logs`
- Verify Java memory doesn't exceed available RAM
- Ensure port 5520/udp is available

### Download authentication fails
- Delete cached credentials and restart:
  - Docker: `docker-compose down -v` (removes volumes)
  - Kubernetes: Delete the config PVC or exec into pod and remove `/data/config/.hytale-downloader-credentials.json`

### Players can't connect
- Complete **both** authentication steps (downloader + server)
- Check server logs for "Server session token not available" error
- Ensure UDP port 5520 is open or playit tunnel is configured
- Verify playit.gg tunnel shows "1 tunnels registered"

### Playit tunnel not working
- Check playit container logs for errors
- Verify secret key is correct
- Ensure tunnel is configured for UDP on port 5520 in playit dashboard
- For custom domains, wait for DNS propagation

### Pod keeps restarting (Kubernetes)
- Check if playit secret key is missing when playit is enabled
- Review pod events: `kubectl describe pod hytale-hytale-server-0 -n hytale`

## Server Provider Authentication

For automated deployments (GSPs), you can obtain and provide session tokens programmatically. See the [Server Provider Authentication Guide](https://support.hytale.com/hc/en-us/articles/45328341414043-Server-Provider-Authentication-Guide) for details on:

- OAuth 2.0 Device Code Flow
- Creating game sessions via API
- Token refresh automation

## Resources

- [Hytale Server Manual](https://support.hytale.com/hc/en-us/articles/45326769420827-Hytale-Server-Manual)
- [Hytale Server Provider Auth Guide](https://support.hytale.com/hc/en-us/articles/45328341414043-Server-Provider-Authentication-Guide)
- [Hytale Hardware Requirements](https://hytale.com/news/2025/12/hytale-hardware-requirements)
- [Playit.gg Documentation](https://playit.gg/docs)

## License

MIT License
