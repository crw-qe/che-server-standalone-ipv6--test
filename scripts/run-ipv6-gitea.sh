#!/bin/bash
#
# Start IPv6 Gitea (GitHub-like repo) for factory resolver testing.
# Creates: Podman network, Gitea container with nodejs-mongodb-sample repo.
#
# Prerequisites: Podman
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

NETWORK_NAME="che-ipv6-net"
IPV6_SUBNET="fd00:dead:beef::/48"
IPV6_GATEWAY="fd00:dead:beef::1"
GITEA_CONTAINER="gitea-ipv6"
GITEA_PORT="3000"
GITEA_USER="testuser"
GITEA_PASS="testpass123"
GITEA_EMAIL="test@example.com"
REPO_NAME="nodejs-mongodb-sample"
REPO_URL="https://github.com/che-samples/nodejs-mongodb-sample"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "=========================================="
echo "IPv6 Gitea (imitate GitHub over IPv6)"
echo "=========================================="
echo ""

if ! command -v podman &>/dev/null; then
    echo -e "${RED}[ERROR]${NC} Podman is required."
    exit 1
fi

if lsof -Pi :$GITEA_PORT -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo -e "${RED}[ERROR]${NC} Port $GITEA_PORT is in use."
    exit 1
fi

podman stop $GITEA_CONTAINER 2>/dev/null || true
podman rm $GITEA_CONTAINER 2>/dev/null || true

if podman network exists "$NETWORK_NAME" 2>/dev/null; then
    echo -e "${YELLOW}[INFO]${NC} Network $NETWORK_NAME already exists, reusing."
else
    echo -e "${GREEN}[STEP]${NC} Creating IPv6 network..."
    podman network create --ipv6 --subnet=$IPV6_SUBNET --gateway=$IPV6_GATEWAY $NETWORK_NAME
fi

echo -e "${GREEN}[STEP]${NC} Starting Gitea..."
podman run -d \
  --name $GITEA_CONTAINER \
  --network $NETWORK_NAME \
  -e USER_UID=1000 \
  -e USER_GID=1000 \
  -e GITEA__database__DB_TYPE=sqlite3 \
  -e GITEA__server__ROOT_URL=http://localhost:$GITEA_PORT/ \
  -e GITEA__security__INSTALL_LOCK=true \
  -p $GITEA_PORT:3000 \
  -p 2222:22 \
  -v gitea-data:/data \
  gitea/gitea:1.21

echo -e "${YELLOW}[INFO]${NC} Waiting for Gitea (60s)..."
sleep 60

if ! podman ps | grep -q $GITEA_CONTAINER; then
    echo -e "${RED}[ERROR]${NC} Gitea failed to start."
    podman logs $GITEA_CONTAINER 2>&1 | tail -30
    exit 1
fi

GITEA_IPV6=$(podman inspect $GITEA_CONTAINER --format '{{range .NetworkSettings.Networks}}{{.GlobalIPv6Address}}{{end}}')
if [ -z "$GITEA_IPV6" ]; then
    GITEA_IPV6=$(podman inspect $GITEA_CONTAINER | grep -o '"GlobalIPv6Address": "[^"]*"' | head -1 | cut -d'"' -f4)
fi

for i in $(seq 1 30); do
    if curl -s http://localhost:$GITEA_PORT/api/v1/version &>/dev/null; then break; fi
    sleep 2
done

echo -e "${GREEN}[STEP]${NC} Configuring Gitea..."
podman exec --user 1000 $GITEA_CONTAINER gitea admin user create \
  --username $GITEA_USER \
  --password $GITEA_PASS \
  --email $GITEA_EMAIL \
  --admin \
  --must-change-password=false 2>/dev/null || true

TOKEN_RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -d '{"name":"che-server-test","scopes":["write:repository","write:user"]}' \
  -u "$GITEA_USER:$GITEA_PASS" \
  http://localhost:$GITEA_PORT/api/v1/users/$GITEA_USER/tokens)
ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | grep -o '"sha1":"[^"]*' | cut -d'"' -f4)
[ -z "$ACCESS_TOKEN" ] && ACCESS_TOKEN="dummy-token-for-testing"

curl -s -X POST -H "Authorization: token $ACCESS_TOKEN" -H "Content-Type: application/json" \
  -d "{\"name\":\"$REPO_NAME\",\"description\":\"IPv6 factory test\",\"private\":false,\"auto_init\":true}" \
  http://localhost:$GITEA_PORT/api/v1/user/repos &>/dev/null || true

curl -s -X POST -H "Authorization: token $ACCESS_TOKEN" -H "Content-Type: application/json" \
  -d "{\"clone_addr\":\"$REPO_URL\",\"repo_name\":\"$REPO_NAME\",\"repo_owner\":\"$GITEA_USER\",\"mirror\":false,\"private\":false}" \
  http://localhost:$GITEA_PORT/api/v1/repos/migrate &>/dev/null || true

echo -e "${YELLOW}[INFO]${NC} Waiting for repo migration (30s)..."
sleep 30

CHE_PORT="8080"
CHE_CONTAINER="che-server-ipv6"
PROXY_CONTAINER="gitea-github-compat-proxy"
PROXY_PORT="4000"
PROXY_IPV6=""

cat > "$REPO_DIR/.test-env" <<EOF
NETWORK_NAME=$NETWORK_NAME
GITEA_CONTAINER=$GITEA_CONTAINER
CHE_CONTAINER=$CHE_CONTAINER
PROXY_CONTAINER=$PROXY_CONTAINER
GITEA_PORT=$GITEA_PORT
CHE_PORT=$CHE_PORT
PROXY_PORT=$PROXY_PORT
GITEA_IPV6=$GITEA_IPV6
CHE_IPV6=
GITEA_USER=$GITEA_USER
GITEA_PASS=$GITEA_PASS
REPO_NAME=$REPO_NAME
ACCESS_TOKEN=$ACCESS_TOKEN
PROXY_IPV6=$PROXY_IPV6
EOF

echo ""
echo "=========================================="
echo "IPv6 Gitea ready"
echo "=========================================="
echo ""
echo "  Gitea Web:     http://localhost:$GITEA_PORT (user: $GITEA_USER / $GITEA_PASS)"
echo "  IPv6 address:  $GITEA_IPV6"
echo ""
echo "  Next: ./scripts/run-gitea-github-proxy.sh   (GitHub-Enterprise-compatible proxy)"
echo "  Then: ./scripts/run-che-server-ipv6.sh       (che-server)"
echo "  Test: ./scripts/test-factory-resolver.sh"
echo "=========================================="
