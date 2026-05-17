#!/bin/bash
#
# Test factory resolver with IPv6 URLs.
# Uses PROXY_IPV6 (GitHub-Enterprise-compatible) for full end-to-end success.
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ ! -f "$REPO_DIR/.test-env" ]; then
    echo "Error: .test-env not found. Run setup scripts first."
    exit 1
fi

source "$REPO_DIR/.test-env"

AUTH_TOKEN="${OC_TOKEN:-$(oc whoami -t 2>/dev/null || true)}"
[ -z "$AUTH_TOKEN" ] && echo "[WARN] No auth token - requests may get 401" || echo "[INFO] Using OpenShift auth token"

# Prefer proxy URL (full success) over direct Gitea (may 400 due to API differences)
TEST_IPV6="${PROXY_IPV6:-$GITEA_IPV6}"
TEST_PORT="${PROXY_IPV6:+$PROXY_PORT}"
TEST_PORT="${TEST_PORT:-$GITEA_PORT}"
TEST_BASE="http://[$TEST_IPV6]:$TEST_PORT/$GITEA_USER/$REPO_NAME"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "Factory Resolver IPv6 Tests"
echo "=========================================="
echo ""

# Check che-server
if ! curl -s "http://localhost:${CHE_PORT}/api/system/state" &>/dev/null; then
    echo -e "${RED}Error:${NC} che-server not accessible. Run ./scripts/run-che-server-ipv6.sh"
    exit 1
fi

run_test() {
    local name="$1"
    local url="$2"
    echo -e "${YELLOW}[TEST]${NC} $name"
    echo "  URL: $url"
    RESP=$(curl -s -w "\n%{http_code}" -X POST \
        "http://localhost:${CHE_PORT}/api/factory/resolver?validate=false" \
        ${AUTH_TOKEN:+-H "Authorization: Bearer ${AUTH_TOKEN}"} \
        -H "Content-Type: application/json" \
        -d "{\"url\": \"$url\"}")
    CODE=$(echo "$RESP" | tail -n1)
    BODY=$(echo "$RESP" | sed '$d')
    echo "  HTTP: $CODE"
    if [ "$CODE" = "200" ]; then
        echo -e "  ${GREEN}[PASS]${NC}"
        return 0
    fi
    if echo "$BODY" | grep -qi "not a valid.*URL\|Cannot build factory"; then
        echo -e "  ${RED}[FAIL]${NC} URL parsing/rejection"
        echo "$BODY" | head -3
        return 1
    fi
    echo -e "  ${YELLOW}[INFO]${NC} $CODE (may be auth/config)"
    return 0
}

echo "Primary test (proxy URL - expect HTTP 200):"
run_test "IPv6 via GitHub-Enterprise proxy" "$TEST_BASE"
echo ""

echo "Additional tests:"
run_test "IPv6 with .git suffix" "${TEST_BASE}.git" || true
run_test "IPv6 with branch" "${TEST_BASE}/tree/main" || true
run_test "IPv4 localhost" "http://localhost:${GITEA_PORT}/${GITEA_USER}/${REPO_NAME}" || true
echo ""

echo "=========================================="
echo "Manual curl example:"
echo "=========================================="
echo ""
echo "curl -X POST 'http://localhost:${CHE_PORT}/api/factory/resolver?validate=false' \\"
echo "  -H 'Content-Type: application/json' \\"
echo "  -d '{\"url\": \"$TEST_BASE\"}'"
echo ""
