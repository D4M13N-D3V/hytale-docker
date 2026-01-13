#!/bin/bash
# Get Hytale Server Session Tokens
# Uses the downloader credentials to create a game session for the server

set -e

CREDS_FILE="${1:-.hytale-downloader-credentials.json}"
OAUTH_URL="https://oauth.accounts.hytale.com"
SESSIONS_URL="https://sessions.hytale.com"

if [ ! -f "$CREDS_FILE" ]; then
    echo "Error: Credentials file not found: $CREDS_FILE"
    echo "Usage: $0 [path-to-credentials.json]"
    exit 1
fi

# Extract tokens from credentials file
REFRESH_TOKEN=$(jq -r '.refresh_token' "$CREDS_FILE")
ACCESS_TOKEN=$(jq -r '.access_token' "$CREDS_FILE")
EXPIRES_AT=$(jq -r '.expires_at' "$CREDS_FILE")
CURRENT_TIME=$(date +%s)

echo "Checking access token validity..."

# Refresh access token if expired or expiring soon
if [ "$CURRENT_TIME" -ge "$((EXPIRES_AT - 300))" ]; then
    echo "Access token expired or expiring soon, refreshing..."

    REFRESH_RESPONSE=$(curl -s -X POST "${OAUTH_URL}/oauth2/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=refresh_token" \
        -d "refresh_token=${REFRESH_TOKEN}" \
        -d "client_id=hytale-downloader")

    if echo "$REFRESH_RESPONSE" | jq -e '.access_token' > /dev/null 2>&1; then
        ACCESS_TOKEN=$(echo "$REFRESH_RESPONSE" | jq -r '.access_token')
        NEW_REFRESH=$(echo "$REFRESH_RESPONSE" | jq -r '.refresh_token // empty')
        if [ -n "$NEW_REFRESH" ]; then
            REFRESH_TOKEN="$NEW_REFRESH"
        fi
        echo "Access token refreshed successfully"
    else
        echo "Error refreshing token: $REFRESH_RESPONSE"
        exit 1
    fi
fi

echo "Getting account profiles..."

# Get profiles
PROFILES_RESPONSE=$(curl -s -X GET "${SESSIONS_URL}/my-account/get-profiles" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}")

if ! echo "$PROFILES_RESPONSE" | jq -e '.' > /dev/null 2>&1; then
    echo "Error getting profiles: $PROFILES_RESPONSE"
    exit 1
fi

# Get the first profile UUID
PROFILE_UUID=$(echo "$PROFILES_RESPONSE" | jq -r '.[0].uuid // empty')

if [ -z "$PROFILE_UUID" ]; then
    echo "No profiles found. Response: $PROFILES_RESPONSE"
    exit 1
fi

echo "Using profile UUID: $PROFILE_UUID"
echo "Creating game session..."

# Create game session
SESSION_RESPONSE=$(curl -s -X POST "${SESSIONS_URL}/game-session/new" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"uuid\": \"${PROFILE_UUID}\"}")

if ! echo "$SESSION_RESPONSE" | jq -e '.sessionToken' > /dev/null 2>&1; then
    echo "Error creating game session: $SESSION_RESPONSE"
    exit 1
fi

SESSION_TOKEN=$(echo "$SESSION_RESPONSE" | jq -r '.sessionToken')
IDENTITY_TOKEN=$(echo "$SESSION_RESPONSE" | jq -r '.identityToken')

echo ""
echo "=== Server Tokens (valid for ~1 hour) ==="
echo ""
echo "HYTALE_SERVER_SESSION_TOKEN=${SESSION_TOKEN}"
echo ""
echo "HYTALE_SERVER_IDENTITY_TOKEN=${IDENTITY_TOKEN}"
echo ""
echo "=== Kubernetes Secret Command ==="
echo ""
echo "kubectl create secret generic hytale-server-auth -n hytale \\"
echo "  --from-literal=session-token='${SESSION_TOKEN}' \\"
echo "  --from-literal=identity-token='${IDENTITY_TOKEN}' \\"
echo "  --dry-run=client -o yaml | kubectl apply -f -"
echo ""
