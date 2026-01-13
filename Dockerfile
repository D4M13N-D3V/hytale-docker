# Hytale Dedicated Server Docker Image
# https://support.hytale.com/hc/en-us/articles/45326769420827-Hytale-Server-Manual

FROM eclipse-temurin:25-jre

LABEL maintainer="hytale-docker"
LABEL description="Hytale Dedicated Server"

# Install dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    unzip \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user for running the server
RUN groupadd -g 1001 hytale && \
    useradd -u 1001 -g hytale -m -s /bin/bash hytale

# Set up directories
RUN mkdir -p /opt/hytale /data/universe /data/mods /data/logs /data/config /data/backups && \
    chown -R hytale:hytale /opt/hytale /data

WORKDIR /opt/hytale

# Download hytale-downloader
RUN curl -fsSL https://downloader.hytale.com/hytale-downloader.zip -o /tmp/hytale-downloader.zip && \
    unzip /tmp/hytale-downloader.zip -d /opt/hytale && \
    chmod +x /opt/hytale/hytale-downloader && \
    rm /tmp/hytale-downloader.zip

# Copy entrypoint script
COPY --chown=hytale:hytale entrypoint.sh /opt/hytale/entrypoint.sh
RUN chmod +x /opt/hytale/entrypoint.sh

# Switch to non-root user
USER hytale

# Environment variables with defaults
ENV JAVA_MEMORY="8G" \
    SERVER_PORT="5520" \
    AUTH_MODE="authenticated" \
    PATCHLINE="release" \
    ENABLE_BACKUP="false" \
    BACKUP_FREQUENCY="30"

# Expose UDP port for QUIC protocol
EXPOSE 5520/udp

# Persistent data volumes
VOLUME ["/data/universe", "/data/mods", "/data/logs", "/data/config", "/data/backups"]

# Health check - verify Java process is running
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD pgrep -f "HytaleServer.jar" > /dev/null || exit 1

ENTRYPOINT ["/opt/hytale/entrypoint.sh"]
