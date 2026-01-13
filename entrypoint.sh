#!/bin/bash
set -e

# Hytale Server Entrypoint Script
# Handles download, configuration, and graceful shutdown

SERVER_DIR="/opt/hytale/server"
DATA_DIR="/data"
ASSETS_FILE="${SERVER_DIR}/Assets.zip"
SERVER_JAR="${SERVER_DIR}/Server/HytaleServer.jar"

# Colors for logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Graceful shutdown handler
shutdown_handler() {
    log_info "Received shutdown signal, stopping server gracefully..."
    if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
        kill -TERM "$SERVER_PID"
        wait "$SERVER_PID" 2>/dev/null || true
    fi
    log_info "Server stopped"
    exit 0
}

# Set up signal handlers
trap shutdown_handler SIGTERM SIGINT SIGQUIT

# Download/update server files
download_server() {
    log_info "Checking for server updates..."

    cd /opt/hytale

    # Restore cached credentials if they exist
    CREDS_FILE=".hytale-downloader-credentials.json"
    CREDS_CACHE="${DATA_DIR}/config/${CREDS_FILE}"
    if [ -f "$CREDS_CACHE" ]; then
        log_info "Restoring cached downloader credentials..."
        cp "$CREDS_CACHE" "/opt/hytale/${CREDS_FILE}"
    fi

    # Set patchline argument
    PATCHLINE_ARG=""
    if [ "$PATCHLINE" = "pre-release" ]; then
        PATCHLINE_ARG="-patchline pre-release"
        log_info "Using pre-release channel"
    else
        log_info "Using release channel"
    fi

    # Run the downloader
    if ./hytale-downloader $PATCHLINE_ARG; then
        log_info "Server files downloaded/updated successfully"
    else
        log_error "Failed to download server files"
        exit 1
    fi

    # Cache the credentials for next restart (they may have been refreshed)
    if [ -f "/opt/hytale/${CREDS_FILE}" ]; then
        log_info "Caching downloader credentials for future restarts..."
        cp "/opt/hytale/${CREDS_FILE}" "$CREDS_CACHE"
    fi

    # List files in download directory for debugging
    log_info "Files in /opt/hytale after download:"
    ls -la /opt/hytale/

    # Find the downloaded version zip (format: YYYY.MM.DD-hash.zip)
    # Exclude any other zip files that might exist
    DOWNLOAD_ZIP=$(ls -t /opt/hytale/*.zip 2>/dev/null | grep -E '[0-9]{4}\.[0-9]{2}\.[0-9]{2}-[a-f0-9]+\.zip' | head -1)

    if [ -z "$DOWNLOAD_ZIP" ]; then
        # Fallback: try to find any zip that's not a known non-server zip
        log_warn "Version-named zip not found, trying fallback..."
        DOWNLOAD_ZIP=$(ls -t /opt/hytale/*.zip 2>/dev/null | head -1)
    fi

    if [ -n "$DOWNLOAD_ZIP" ] && [ -f "$DOWNLOAD_ZIP" ]; then
        log_info "Found download zip: $DOWNLOAD_ZIP"

        # Clean up old extracted files
        rm -rf /opt/hytale/extracted
        mkdir -p /opt/hytale/extracted

        log_info "Extracting $DOWNLOAD_ZIP..."
        unzip -o "$DOWNLOAD_ZIP" -d /opt/hytale/extracted
        log_info "Extraction complete"

        # Show extracted contents
        log_info "Extracted contents:"
        ls -la /opt/hytale/extracted/
        if [ -d "/opt/hytale/extracted/Server" ]; then
            ls -la /opt/hytale/extracted/Server/
        fi
    else
        log_error "No download zip file found!"
        ls -la /opt/hytale/
        exit 1
    fi

    # Create server directory
    mkdir -p "${SERVER_DIR}"

    # Copy files from extracted directory
    if [ -d "/opt/hytale/extracted/Server" ]; then
        log_info "Copying Server directory to ${SERVER_DIR}/..."
        cp -r /opt/hytale/extracted/Server "${SERVER_DIR}/"
        log_info "Server directory copied"
    else
        log_error "Server directory not found in extracted files!"
        exit 1
    fi

    if [ -f "/opt/hytale/extracted/Assets.zip" ]; then
        log_info "Copying Assets.zip to ${SERVER_DIR}/..."
        cp /opt/hytale/extracted/Assets.zip "${SERVER_DIR}/"
        log_info "Assets.zip copied"
    else
        log_error "Assets.zip not found in extracted files!"
        exit 1
    fi

    # Verify files were copied correctly
    log_info "Verifying copied files..."
    log_info "Contents of ${SERVER_DIR}:"
    ls -la "${SERVER_DIR}/"
    log_info "Contents of ${SERVER_DIR}/Server:"
    ls -la "${SERVER_DIR}/Server/" 2>/dev/null || log_error "Server subdirectory not found!"

    if [ -f "${SERVER_JAR}" ]; then
        log_info "Server JAR verified at: ${SERVER_JAR}"
    else
        log_error "Server JAR not found at expected location: ${SERVER_JAR}"
        exit 1
    fi

    if [ -f "${ASSETS_FILE}" ]; then
        log_info "Assets file verified at: ${ASSETS_FILE}"
    else
        log_error "Assets file not found at expected location: ${ASSETS_FILE}"
        exit 1
    fi
}

# Create symlinks for persistent data
setup_persistence() {
    log_info "Setting up persistent data directories..."

    cd "${SERVER_DIR}/Server" 2>/dev/null || cd "${SERVER_DIR}"

    # Universe (world data)
    if [ ! -L "universe" ]; then
        rm -rf universe 2>/dev/null || true
        ln -sf "${DATA_DIR}/universe" universe
    fi

    # Mods
    if [ ! -L "mods" ]; then
        rm -rf mods 2>/dev/null || true
        ln -sf "${DATA_DIR}/mods" mods
    fi

    # Logs
    if [ ! -L "logs" ]; then
        rm -rf logs 2>/dev/null || true
        ln -sf "${DATA_DIR}/logs" logs
    fi

    # Config files - symlink individual files if they exist in persistent storage
    for config_file in config.json permissions.json whitelist.json bans.json; do
        if [ -f "${DATA_DIR}/config/${config_file}" ]; then
            ln -sf "${DATA_DIR}/config/${config_file}" "${config_file}" 2>/dev/null || true
        fi
    done

    log_info "Persistent data directories configured"
}

# Copy generated config files to persistent storage
save_configs() {
    cd "${SERVER_DIR}/Server" 2>/dev/null || cd "${SERVER_DIR}"

    for config_file in config.json permissions.json whitelist.json bans.json; do
        if [ -f "${config_file}" ] && [ ! -L "${config_file}" ]; then
            cp "${config_file}" "${DATA_DIR}/config/" 2>/dev/null || true
        fi
    done
}

# Build JVM arguments
build_jvm_args() {
    JVM_ARGS="-Xmx${JAVA_MEMORY} -Xms${JAVA_MEMORY}"

    # Add AOT cache if available
    if [ -f "HytaleServer.aot" ]; then
        JVM_ARGS="${JVM_ARGS} -XX:AOTCache=HytaleServer.aot"
    fi

    echo "$JVM_ARGS"
}

# Build server arguments
build_server_args() {
    SERVER_ARGS="--assets ${ASSETS_FILE}"
    SERVER_ARGS="${SERVER_ARGS} --bind 0.0.0.0:${SERVER_PORT}"
    SERVER_ARGS="${SERVER_ARGS} --auth-mode ${AUTH_MODE}"

    # Add auth tokens if provided
    if [ -n "$HYTALE_SERVER_SESSION_TOKEN" ]; then
        SERVER_ARGS="${SERVER_ARGS} --session-token \"${HYTALE_SERVER_SESSION_TOKEN}\""
    fi
    if [ -n "$HYTALE_SERVER_IDENTITY_TOKEN" ]; then
        SERVER_ARGS="${SERVER_ARGS} --identity-token \"${HYTALE_SERVER_IDENTITY_TOKEN}\""
    fi

    # Auto-trigger auth login on boot if no tokens provided and in authenticated mode
    if [ -z "$HYTALE_SERVER_SESSION_TOKEN" ] && [ "$AUTH_MODE" = "authenticated" ]; then
        SERVER_ARGS="${SERVER_ARGS} --boot-command 'auth login browser'"
        # Log to stderr so it doesn't get captured in the args
        echo -e "${GREEN}[INFO]${NC} No session token provided - will trigger 'auth login' on boot" >&2
    fi

    # Backup configuration
    if [ "$ENABLE_BACKUP" = "true" ]; then
        SERVER_ARGS="${SERVER_ARGS} --backup --backup-dir ${DATA_DIR}/backups --backup-frequency ${BACKUP_FREQUENCY}"
    fi

    echo "$SERVER_ARGS"
}

# Main execution
main() {
    log_info "Starting Hytale Server Container"
    log_info "Java Memory: ${JAVA_MEMORY}"
    log_info "Server Port: ${SERVER_PORT}"
    log_info "Auth Mode: ${AUTH_MODE}"
    log_info "Patchline: ${PATCHLINE}"

    # Download server if not present or if update check is needed
    if [ ! -f "$SERVER_JAR" ]; then
        log_info "Server files not found, downloading..."
        download_server
    else
        log_info "Checking for updates..."
        download_server
    fi

    # Verify server files exist
    if [ ! -f "$SERVER_JAR" ]; then
        log_error "Server JAR not found at ${SERVER_JAR}"
        exit 1
    fi

    if [ ! -f "$ASSETS_FILE" ]; then
        log_error "Assets file not found at ${ASSETS_FILE}"
        exit 1
    fi

    # Set up persistent storage
    setup_persistence

    # Build arguments
    JVM_ARGS=$(build_jvm_args)
    SERVER_ARGS=$(build_server_args)

    log_info "JVM Args: ${JVM_ARGS}"
    log_info "Server Args: ${SERVER_ARGS}"

    # Change to server directory
    cd "${SERVER_DIR}/Server" 2>/dev/null || cd "${SERVER_DIR}"

    log_info "Starting Hytale Server..."
    log_info "Use '/auth login' in the console to authenticate the server for player connections"

    # Run server in foreground with eval exec to properly handle quoted arguments
    # This replaces the shell process, allowing interactive console access
    eval exec java ${JVM_ARGS} -jar HytaleServer.jar ${SERVER_ARGS}
}

main "$@"
