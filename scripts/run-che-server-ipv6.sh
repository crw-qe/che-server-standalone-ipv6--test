#!/bin/bash
#
# Run che-server with IPv6 support for factory resolver testing (PR 951).
# Uses CRC OpenShift for auth; nginx proxy injects token so Swagger works.
#
# Prerequisites:
#   - CRC running, oc logged in (crc-admin)
#   - Gitea + proxy running (run-ipv6-gitea.sh, run-gitea-github-proxy.sh)
#
# Env vars:
#   CHE_SERVER_IMAGE  - default: quay.io/eclipse/che-server:pr-951
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

CHE_IMAGE="${CHE_SERVER_IMAGE:-quay.io/eclipse/che-server:pr-951}"
CHE_CONTAINER="che-server-ipv6"
PROXY_CONTAINER="${CHE_CONTAINER}-proxy"
NETWORK_NAME="che-ipv6-net"
CHE_PORT="8080"
POD_NAMESPACE="che"
CRC_API_URL="https://api.crc.testing:6443"
CRC_HOST_IP="192.168.127.254"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "=========================================="
echo "che-server with IPv6 + CRC OpenShift auth"
echo "=========================================="
echo ""

if ! podman network exists "$NETWORK_NAME" 2>/dev/null; then
    echo -e "${YELLOW}[INFO]${NC} Creating IPv6 network $NETWORK_NAME..."
    podman network create --ipv6 --subnet=fd00:dead:beef::/48 --gateway=fd00:dead:beef::1 "$NETWORK_NAME"
fi

podman stop "$CHE_CONTAINER" "$PROXY_CONTAINER" 2>/dev/null || true
podman rm   "$CHE_CONTAINER" "$PROXY_CONTAINER" 2>/dev/null || true

OC_TOKEN=$(oc whoami -t 2>/dev/null || true)
if [ -z "$OC_TOKEN" ]; then
    echo -e "${RED}[ERROR]${NC} Could not get OpenShift token. Run: oc login ..."
    exit 1
fi
echo -e "${YELLOW}[INFO]${NC} Image: $CHE_IMAGE"
echo -e "${YELLOW}[INFO]${NC} CRC token: ${OC_TOKEN:0:20}..."
echo ""

echo -e "${GREEN}[STEP]${NC} Starting $CHE_IMAGE..."
podman run -d \
  --name "$CHE_CONTAINER" \
  --network "$NETWORK_NAME" \
  --add-host "api.crc.testing:${CRC_HOST_IP}" \
  -e CHE_PORT=8080 \
  -e CHE_HOST=localhost \
  -e CHE_DOCKER_NETWORK="$NETWORK_NAME" \
  -e CHE_INFRASTRUCTURE_ACTIVE=openshift \
  -e CHE_INFRA_OPENSHIFT_OAUTH__ENABLED=true \
  -e CHE_INFRA_KUBERNETES_MASTER__URL="$CRC_API_URL" \
  -e POD_NAMESPACE="$POD_NAMESPACE" \
  -v che-server-data-ipv6:/data \
  "$CHE_IMAGE"

echo -e "${YELLOW}[INFO]${NC} Waiting for che-server (60s)..."
sleep 60

if ! podman ps | grep -q "$CHE_CONTAINER"; then
    echo -e "${RED}[ERROR]${NC} che-server failed. Logs:"
    podman logs "$CHE_CONTAINER" 2>&1 | tail -50
    exit 1
fi

echo -e "${GREEN}[STEP]${NC} Starting nginx auth-proxy on port $CHE_PORT..."
NGINX_CONF="$REPO_DIR/.che-nginx-proxy.conf"
cat > "$NGINX_CONF" <<NGINX
events {}
http {
    server {
        listen ${CHE_PORT};

        location /swagger/ {
            proxy_pass http://${CHE_CONTAINER}:8080;
            proxy_set_header Host \$host;
        }

        location /api/ {
            proxy_pass http://${CHE_CONTAINER}:8080;
            proxy_set_header Host \$host;
            proxy_set_header Authorization "Bearer ${OC_TOKEN}";
        }

        location / {
            proxy_pass http://${CHE_CONTAINER}:8080;
            proxy_set_header Host \$host;
        }
    }
}
NGINX

podman run -d \
  --name "$PROXY_CONTAINER" \
  --network "$NETWORK_NAME" \
  -p "${CHE_PORT}:${CHE_PORT}" \
  -v "${NGINX_CONF}:/etc/nginx/nginx.conf:ro,z" \
  nginx:alpine

sleep 5

CHE_IPV6=$(podman inspect "$CHE_CONTAINER" --format '{{range .NetworkSettings.Networks}}{{.GlobalIPv6Address}}{{end}}')

if [ -f "$REPO_DIR/.test-env" ]; then
    if grep -q "^CHE_IPV6=" "$REPO_DIR/.test-env"; then
        sed -i.bak "s/^CHE_IPV6=.*/CHE_IPV6=${CHE_IPV6}/" "$REPO_DIR/.test-env"
        rm -f "$REPO_DIR/.test-env.bak"
    else
        echo "CHE_IPV6=$CHE_IPV6" >> "$REPO_DIR/.test-env"
    fi
fi

echo ""
echo "=========================================="
echo "che-server is running"
echo "=========================================="
echo ""
echo "  Swagger UI:    http://localhost:${CHE_PORT}/swagger/"
echo "  Factory API:   http://localhost:${CHE_PORT}/api/factory/resolver"
echo ""
echo "  Test with: ./scripts/test-factory-resolver.sh"
echo "=========================================="
