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

    # Find and extract the downloaded zip file
    DOWNLOAD_ZIP=$(ls -t *.zip 2>/dev/null | head -1)
    if [ -n "$DOWNLOAD_ZIP" ] && [ -f "$DOWNLOAD_ZIP" ]; then
        log_info "Extracting $DOWNLOAD_ZIP..."
        unzip -o "$DOWNLOAD_ZIP" -d /opt/hytale/extracted
        log_info "Extraction complete"
    fi

    # Move downloaded files to server directory
    mkdir -p "${SERVER_DIR}"

    # Check extracted directory first, then current directory
    for src_dir in /opt/hytale/extracted /opt/hytale; do
        if [ -d "${src_dir}/Server" ]; then
            log_info "Copying Server from ${src_dir}..."
            cp -r "${src_dir}/Server" "${SERVER_DIR}/"
        fi
        if [ -f "${src_dir}/Assets.zip" ]; then
            log_info "Copying Assets.zip from ${src_dir}..."
            cp "${src_dir}/Assets.zip" "${SERVER_DIR}/"
        fi
    done
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

    # Start server in background to handle signals
    eval java ${JVM_ARGS} -jar HytaleServer.jar ${SERVER_ARGS} &
    SERVER_PID=$!

    log_info "Server started with PID: ${SERVER_PID}"

    # Wait for server process
    wait $SERVER_PID
    EXIT_CODE=$?

    # Save any new config files
    save_configs

    log_info "Server exited with code: ${EXIT_CODE}"
    exit $EXIT_CODE
}

main "$@"
