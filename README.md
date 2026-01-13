# Hytale Docker Server

Docker and Kubernetes (Helm) deployment for Hytale dedicated game servers.

## Requirements

- Docker 20.10+ (for Docker deployment)
- Kubernetes 1.24+ (for Helm deployment)
- Helm 3.0+ (for Helm deployment)
- Minimum 4GB RAM (8GB recommended)

## Quick Start

### Docker Compose (Recommended for single server)

1. Clone this repository:
   ```bash
   git clone https://github.com/your-org/hytale-docker.git
   cd hytale-docker
   ```

2. Copy and configure environment:
   ```bash
   cp .env.example .env
   # Edit .env with your settings
   ```

3. Start the server:
   ```bash
   docker-compose up -d
   ```

4. View logs:
   ```bash
   docker-compose logs -f
   ```

5. Authenticate the server (required for authenticated mode):
   - Watch the logs for the device login prompt
   - Visit https://accounts.hytale.com/device
   - Enter the code shown in the server console

### Docker Run (Manual)

```bash
# Build the image
docker build -t hytale-server .

# Run the server
docker run -d \
  --name hytale-server \
  -p 5520:5520/udp \
  -e JAVA_MEMORY=8G \
  -e AUTH_MODE=authenticated \
  -v hytale-universe:/data/universe \
  -v hytale-mods:/data/mods \
  -v hytale-logs:/data/logs \
  -v hytale-config:/data/config \
  hytale-server
```

### Kubernetes (Helm)

1. Build and push the Docker image to your registry:
   ```bash
   docker build -t your-registry/hytale-server:latest .
   docker push your-registry/hytale-server:latest
   ```

2. Create a secret for auth tokens (recommended):
   ```bash
   kubectl create secret generic hytale-auth \
     --from-literal=session-token='your-session-token' \
     --from-literal=identity-token='your-identity-token'
   ```

3. Install the Helm chart:
   ```bash
   helm install hytale ./helm/hytale-server \
     --set image.repository=your-registry/hytale-server \
     --set auth.existingSecret=hytale-auth
   ```

4. Check the deployment:
   ```bash
   kubectl get pods
   kubectl logs -f hytale-0
   ```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `JAVA_MEMORY` | `8G` | JVM heap size allocation |
| `SERVER_PORT` | `5520` | UDP port for QUIC protocol |
| `AUTH_MODE` | `authenticated` | `authenticated` or `offline` |
| `PATCHLINE` | `release` | `release` or `pre-release` |
| `ENABLE_BACKUP` | `false` | Enable automatic backups |
| `BACKUP_FREQUENCY` | `30` | Backup interval in minutes |
| `HYTALE_SERVER_SESSION_TOKEN` | - | Session token for authentication |
| `HYTALE_SERVER_IDENTITY_TOKEN` | - | Identity token for authentication |

### Helm Values

See `helm/hytale-server/values.yaml` for all configurable options.

Key configurations:

```yaml
# Server settings
server:
  port: 5520
  memory: "8G"
  authMode: "authenticated"
  patchline: "release"

# Service type (NodePort for bare metal, LoadBalancer for cloud)
service:
  type: NodePort
  nodePort: ""  # Auto-assign or specify (30000-32767)

# Persistent storage sizes
persistence:
  universe:
    size: 10Gi
  mods:
    size: 1Gi

# Resource limits
resources:
  limits:
    memory: 10Gi
    cpu: "4"
  requests:
    memory: 8Gi
    cpu: "2"

# Use existing secret for auth tokens (recommended)
auth:
  existingSecret: "hytale-auth"
```

## Volumes / Persistent Data

| Path | Description |
|------|-------------|
| `/data/universe` | World and player save data |
| `/data/mods` | Installed modifications |
| `/data/logs` | Server activity logs |
| `/data/config` | Configuration files (config.json, permissions.json, etc.) |
| `/data/backups` | Automatic backup storage |

## Networking

Hytale uses **QUIC protocol over UDP** on port **5520** by default.

### Docker
Ensure your firewall allows UDP traffic on port 5520:
```bash
# Linux (ufw)
sudo ufw allow 5520/udp

# Linux (firewalld)
sudo firewall-cmd --add-port=5520/udp --permanent
sudo firewall-cmd --reload
```

### Kubernetes
The Helm chart creates a `NodePort` service by default. Ensure your node's firewall allows traffic on the assigned NodePort (30000-32767 range).

## Authentication

Hytale servers require authentication to accept player connections.

### Interactive Authentication (Development)
1. Start the server
2. Watch logs for the device login prompt
3. Visit https://accounts.hytale.com/device
4. Enter the code from the server console

### Token-Based Authentication (Production)
For automated deployments, obtain authentication tokens and configure via environment variables or Kubernetes secrets.

**Docker:**
```bash
export HYTALE_SERVER_SESSION_TOKEN="your-token"
export HYTALE_SERVER_IDENTITY_TOKEN="your-token"
docker-compose up -d
```

**Kubernetes:**
```bash
kubectl create secret generic hytale-auth \
  --from-literal=session-token='your-session-token' \
  --from-literal=identity-token='your-identity-token'

helm install hytale ./helm/hytale-server --set auth.existingSecret=hytale-auth
```

## Commands

### Docker

```bash
# Start server
docker-compose up -d

# Stop server (graceful)
docker-compose down

# View logs
docker-compose logs -f

# Restart server
docker-compose restart

# Enter container shell
docker-compose exec hytale-server bash

# Rebuild after changes
docker-compose build --no-cache
docker-compose up -d
```

### Kubernetes

```bash
# Install
helm install hytale ./helm/hytale-server

# Upgrade
helm upgrade hytale ./helm/hytale-server

# Uninstall
helm uninstall hytale

# View logs
kubectl logs -f hytale-0

# Exec into pod
kubectl exec -it hytale-0 -- bash

# Check status
kubectl get pods,svc,pvc
```

## Troubleshooting

### Server won't start
- Check logs: `docker-compose logs` or `kubectl logs`
- Verify Java memory settings don't exceed available RAM
- Ensure port 5520/udp is not in use

### Players can't connect
- Verify server is authenticated (check logs for "Authentication successful!")
- Ensure UDP port 5520 is open in firewall
- For Kubernetes, verify NodePort is accessible

### Download fails
- Check network connectivity
- Verify hytale-downloader can reach downloader.hytale.com
- For pre-release, set `PATCHLINE=pre-release`

## Resources

- [Hytale Server Manual](https://support.hytale.com/hc/en-us/articles/45326769420827-Hytale-Server-Manual)
- [Hytale Hardware Requirements](https://hytale.com/news/2025/12/hytale-hardware-requirements)
- [Hytale Official Website](https://hytale.com)

## License

MIT License - See LICENSE file for details.
