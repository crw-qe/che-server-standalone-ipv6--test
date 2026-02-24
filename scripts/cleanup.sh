#!/bin/bash
#
# Cleanup IPv6 test environment: containers, network, optional volumes.
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

NETWORK_NAME="che-ipv6-net"
GITEA_CONTAINER="gitea-ipv6"
CHE_CONTAINER="che-server-ipv6"
PROXY_CONTAINER="${CHE_CONTAINER}-proxy"
GITEA_PROXY="gitea-github-compat-proxy"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "IPv6 Test Environment Cleanup"
echo "=========================================="
echo ""

echo -e "${GREEN}[STEP]${NC} Stopping containers..."
podman stop $CHE_CONTAINER $PROXY_CONTAINER $GITEA_PROXY $GITEA_CONTAINER 2>/dev/null || true

echo -e "${GREEN}[STEP]${NC} Removing containers..."
podman rm $CHE_CONTAINER $PROXY_CONTAINER $GITEA_PROXY $GITEA_CONTAINER 2>/dev/null || true

echo -e "${GREEN}[STEP]${NC} Removing network..."
podman network rm $NETWORK_NAME 2>/dev/null || true

if podman volume ls | grep -q gitea-data; then
    read -p "Remove Gitea data volume? (y/N): " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]] && podman volume rm gitea-data 2>/dev/null || true
fi

if [ -f "$REPO_DIR/.test-env" ]; then
    rm "$REPO_DIR/.test-env"
    echo -e "${YELLOW}[INFO]${NC} Removed .test-env"
fi

echo ""
echo "=========================================="
echo "Cleanup complete"
echo "=========================================="
echo "Run ./scripts/run-ipv6-gitea.sh to start again."
echo ""
