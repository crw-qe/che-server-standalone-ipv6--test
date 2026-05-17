# che-server-standalone-test

Standalone test environment for **Dev Spaces server IPv6 factory resolver** support. Runs the Dev Spaces server image locally with Podman, alongside Gitea and an API-compatibility proxy — all on a self-contained IPv6 network. Any OpenShift cluster is used only for token validation (auth).

**No full Dev Spaces / Che deployment required.**

---

## Quick start

```bash
# 0. Log in to any OpenShift cluster (used only for auth token validation)
oc login https://api.<cluster>:6443 -u <user> -p <password>

# 1. Start IPv6 Gitea (GitHub-like Git host)
./scripts/run-ipv6-gitea.sh

# 2. Start GitHub-Enterprise-compatible proxy (maps GitHub v3 API → Gitea v1)
./scripts/run-gitea-github-proxy.sh

# 3. Start Dev Spaces server (locally in Podman, authenticates against your OCP cluster)
./scripts/run-che-server-ipv6.sh

# 4. Run factory resolver IPv6 tests
./scripts/test-factory-resolver.sh
```

---

## Prerequisites

| Tool | Purpose |
|------|---------|
| **Podman** | Containers (Gitea, nginx, Dev Spaces server) |
| **oc** | Logged in to any OpenShift cluster (`oc login`) |

```bash
# Verify
podman --version
oc whoami
oc whoami --show-server
```

> **Why OpenShift?** The Dev Spaces server requires an OpenShift token for API auth. The server runs locally in Podman; it contacts the remote cluster only to validate tokens. Any OpenShift cluster works — CRC, OCP, ROSA, etc.

---

## Scripts

| Script | Description |
|--------|-------------|
| `scripts/run-ipv6-gitea.sh` | Start IPv6 Gitea with `nodejs-mongodb-sample` repo |
| `scripts/run-gitea-github-proxy.sh` | Start nginx proxy that maps GitHub v3 API → Gitea v1 |
| `scripts/run-che-server-ipv6.sh` | Start Dev Spaces server (default: `server-rhel9:3.28`) |
| `scripts/test-factory-resolver.sh` | Test factory resolver with IPv6 URLs |
| `scripts/cleanup.sh` | Stop and remove all containers, network, optional volumes |

---

## Testing

### Server image

Default: `quay.io/redhat-user-workloads/devspaces-tenant/devspaces/server-rhel9:3.28` (Dev Spaces 3.28).

Use a custom image:

```bash
export CHE_SERVER_IMAGE=quay.io/redhat-user-workloads/devspaces-tenant/devspaces/server-rhel9:3.28
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
│ (injects OCP token)│  │ (GitHub v3→Gitea v1)│  │ (fd00::a)     │
└────────┬───────────┘  └──────────┬──────────┘  └───────┬───────┘
         │                          │                     │
         ▼                          │                     │
┌────────────────────┐              └─────────────────────┘
│ Dev Spaces server  │   IPv6 network: che-ipv6-net (fd00:dead:beef::/48)
│ (fd00::11)         │
└────────┬───────────┘
         │ token validation only
         ▼
┌────────────────────┐
│ Remote OpenShift   │
│ (any OCP cluster)  │
└────────────────────┘
```

- **Gitea**: IPv6 Git host with `nodejs-mongodb-sample` repo.
- **gitea-github-proxy**: Maps GitHub API v3/raw URLs to Gitea v1/raw (Dev Spaces server expects GitHub-style endpoints).
- **Dev Spaces server**: Factory resolver running locally in Podman.
- **OpenShift cluster**: Used only for token validation — the server connects to the cluster API to authenticate requests.

> **Why not test on a deployed Dev Spaces instance directly?** The factory resolver must make outbound HTTP requests to the IPv6 Git URL. The local Podman IPv6 network (`fd00:dead:beef::/48`) is not routable from a remote OCP cluster. Running everything locally keeps the IPv6 network self-contained.

---

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CHE_SERVER_IMAGE` | `...server-rhel9:3.28` | Dev Spaces server image |
| `POD_NAMESPACE` | `openshift-devspaces` | Kubernetes namespace for che-server |

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

### Server not starting

```bash
podman logs che-server-ipv6
```

Common cause: `oc` not logged in or OpenShift cluster unreachable from the container.

### 500 on all API calls

Check `podman logs che-server-ipv6` for `timeout ... api.crc.testing` or similar. This means the server can't reach the OpenShift API. Verify `oc whoami` works and re-run `./scripts/run-che-server-ipv6.sh`.

### 401 on API calls

The OpenShift token may have expired. Re-run `oc login`, then restart che-server.
The nginx proxy injects the token automatically when you use `http://localhost:8080`.

### 400 "Cannot build factory"

- Use the **proxy** URL (`PROXY_IPV6`, port 4000), not the direct Gitea URL.
- Gitea uses `/api/v1/` while the server expects GitHub v3; the proxy bridges this.

---

## Cleanup

```bash
./scripts/cleanup.sh
```

Optionally removes Gitea data volume to fully reset.

---

## Links

- [Red Hat Dev Spaces](https://developers.redhat.com/products/devspaces/overview)
- [eclipse-che/che-server](https://github.com/eclipse-che/che-server)
- [che-samples/nodejs-mongodb-sample](https://github.com/che-samples/nodejs-mongodb-sample)
