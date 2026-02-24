#!/bin/bash
#
# Start GitHub-Enterprise-compatible nginx proxy in front of Gitea.
# che-server expects GitHub API v3 and raw URL format; Gitea uses v1.
# This proxy maps GitHub-style endpoints to Gitea equivalents.
#
# Prerequisites: Gitea running (./scripts/run-ipv6-gitea.sh)
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PROXY_CONTAINER="gitea-github-compat-proxy"
PROXY_PORT="4000"
NETWORK_NAME="che-ipv6-net"
GITEA_CONTAINER="gitea-ipv6"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

if ! podman network exists "$NETWORK_NAME" 2>/dev/null; then
    echo -e "${RED}[ERROR]${NC} Network $NETWORK_NAME not found. Run ./scripts/run-ipv6-gitea.sh first."
    exit 1
fi

podman stop $PROXY_CONTAINER 2>/dev/null || true
podman rm $PROXY_CONTAINER 2>/dev/null || true

NGINX_CONF="$REPO_DIR/config/gitea-github-proxy.conf"
if [ ! -f "$NGINX_CONF" ]; then
    echo -e "${RED}[ERROR]${NC} Config not found: $NGINX_CONF"
    exit 1
fi

echo -e "${GREEN}[STEP]${NC} Starting GitHub-Enterprise-compatible proxy on port $PROXY_PORT..."
podman run -d \
  --name $PROXY_CONTAINER \
  --network $NETWORK_NAME \
  -p $PROXY_PORT:$PROXY_PORT \
  -v "${NGINX_CONF}:/etc/nginx/nginx.conf:ro,z" \
  nginx:alpine

sleep 2

PROXY_IPV6=$(podman inspect $PROXY_CONTAINER --format '{{range .NetworkSettings.Networks}}{{.GlobalIPv6Address}}{{end}}')

# Update .test-env
if [ -f "$REPO_DIR/.test-env" ]; then
    if grep -q "^PROXY_IPV6=" "$REPO_DIR/.test-env"; then
        sed -i.bak "s/^PROXY_IPV6=.*/PROXY_IPV6=$PROXY_IPV6/" "$REPO_DIR/.test-env"
        rm -f "$REPO_DIR/.test-env.bak"
    else
        echo "PROXY_IPV6=$PROXY_IPV6" >> "$REPO_DIR/.test-env"
    fi
fi

echo ""
echo "=========================================="
echo "GitHub-Enterprise proxy ready"
echo "=========================================="
echo ""
echo "  Proxy IPv6:    $PROXY_IPV6"
echo "  Port:          $PROXY_PORT"
echo ""
echo "  Factory resolver test URL:"
echo "    http://[$PROXY_IPV6]:$PROXY_PORT/testuser/nodejs-mongodb-sample"
echo ""
echo "  Next: ./scripts/run-che-server-ipv6.sh"
echo "=========================================="
