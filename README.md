# che-server-standalone-test

Test environment for Eclipse Che server PRs in standalone mode. Scripts and configs to run che-server with Podman, Gitea (GitHub-compatible proxy), and CRC—**without full Eclipse Che deployment**.

**Focused on: [PR #951 – feat: enable IPv6 support for factory resolver endpoints](https://github.com/eclipse-che/che-server/pull/951)**

---

## Quick start

```bash
# 1. Gitea (IPv6 GitHub-like repo)
./scripts/run-ipv6-gitea.sh

# 2. GitHub-Enterprise-compatible proxy (required for full factory resolver success)
./scripts/run-gitea-github-proxy.sh

# 3. che-server (requires CRC running, oc login)
./scripts/run-che-server-ipv6.sh

# 4. Run tests
./scripts/test-factory-resolver.sh
```

---

## Prerequisites

| Tool | Purpose |
|------|---------|
| **Podman** | Containers (Gitea, nginx, che-server) |
| **CRC** (OpenShift Local) | OpenShift cluster for che-server auth |
| **oc** | Logged in to CRC (`oc login`) |

```bash
# Verify
podman --version
crc status
oc whoami
```

---

## Scripts

| Script | Description |
|--------|-------------|
| `scripts/run-ipv6-gitea.sh` | Start IPv6 Gitea with `nodejs-mongodb-sample` repo |
| `scripts/run-gitea-github-proxy.sh` | Start nginx proxy that maps GitHub v3 API → Gitea v1 |
| `scripts/run-che-server-ipv6.sh` | Start che-server (default: `quay.io/eclipse/che-server:pr-951`) |
| `scripts/test-factory-resolver.sh` | Test factory resolver with IPv6 URLs |
| `scripts/cleanup.sh` | Stop and remove all containers, network, optional volumes |

---

## Testing PR 951

### Test image

Default: `quay.io/eclipse/che-server:pr-951` (built by CI for [PR 951](https://github.com/eclipse-che/che-server/pull/951)).

Use a custom image:

```bash
export CHE_SERVER_IMAGE=quay.io/eclipse/che-server:pr-951
./scripts/run-che-server-ipv6.sh
```

### Test URL

After setup, `.test-env` contains `PROXY_IPV6`. Use it for factory resolver:

```
http://[<PROXY_IPV6>]:4000/testuser/nodejs-mongodb-sample
```

Example:

```bash
source .test-env
curl -X POST "http://localhost:8080/api/factory/resolver?validate=false" \
  -H "Content-Type: application/json" \
  -d "{\"url\": \"http://[${PROXY_IPV6}]:4000/testuser/nodejs-mongodb-sample\"}"
```

Expected: **HTTP 200** with parsed devfile and `scm_provider: github`.

### Swagger UI

1. Open http://localhost:8080/swagger/
2. Go to **factory** → **POST /factory/resolver**
3. Use test URL with IPv6 brackets, e.g.  
   `http://[fd00:dead:beef::13]:4000/testuser/nodejs-mongodb-sample`

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ Host                                                             │
│  localhost:8080 (nginx)  localhost:4000 (proxy)  localhost:3000  │
└────────────┬───────────────────────┬────────────────────┬───────┘
             │                       │                    │
             ▼                       ▼                    ▼
┌────────────────────┐  ┌────────────────────┐  ┌───────────────┐
│ nginx auth-proxy   │  │ gitea-github-proxy  │  │ Gitea         │
│ (injects CRC token)│  │ (GitHub v3→Gitea v1)│  │ (fd00::a)     │
└────────┬───────────┘  └──────────┬──────────┘  └───────┬───────┘
         │                          │                     │
         ▼                          │                     │
┌────────────────────┐              └─────────────────────┘
│ che-server-ipv6    │   IPv6 network: che-ipv6-net (fd00:dead:beef::/48)
│ (fd00::11)         │
└────────────────────┘
```

- **Gitea**: Git host with `nodejs-mongodb-sample`.
- **gitea-github-proxy**: Maps GitHub API v3/raw URLs to Gitea v1/raw (che-server expects GitHub-style endpoints).
- **che-server**: Factory resolver; needs CRC token for API auth.

---

## Endpoints

| Endpoint | URL |
|----------|-----|
| Swagger UI | http://localhost:8080/swagger/ |
| Factory resolver API | http://localhost:8080/api/factory/resolver |
| openapi.json | http://localhost:8080/api/openapi.json |
| Gitea Web | http://localhost:3000 |

---

## Troubleshooting

### Ports in use

```bash
lsof -i :8080
lsof -i :4000
lsof -i :3000
```

### che-server not starting

```bash
podman logs che-server-ipv6
```

Common: CRC not running or `oc` not logged in.

### 401 on API calls

Ensure CRC token is used: nginx proxy injects it automatically when you use `http://localhost:8080`.

### 400 "Cannot build factory"

- Use the **proxy** URL (`PROXY_IPV6`, port 4000), not the direct Gitea URL.
- Gitea uses `/api/v1/` while che-server expects GitHub v3; the proxy bridges this.

---

## Cleanup

```bash
./scripts/cleanup.sh
```

Optionally removes Gitea data volume to fully reset.

---

## Links

- [PR 951 – IPv6 support for factory resolver](https://github.com/eclipse-che/che-server/pull/951)
- [eclipse-che/che-server](https://github.com/eclipse-che/che-server)
- [che-samples/nodejs-mongodb-sample](https://github.com/che-samples/nodejs-mongodb-sample)
