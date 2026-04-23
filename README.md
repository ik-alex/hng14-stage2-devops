# HNG14 Stage 2 DevOps — Containerized Job Queue

A containerized microservices application consisting of a FastAPI job submission API, a background worker, a Node.js frontend proxy, and a Redis-backed job queue. Includes a full production-grade CI/CD pipeline implemented with GitHub Actions.

![CI/CD Pipeline](https://github.com/ik-alex/hng14-stage2-devops/actions/workflows/ci-cd.yml/badge.svg)

---

## Architecture

```
┌──────────┐         ┌─────────┐         ┌──────────┐
│ Browser  │────────▶│Frontend │────────▶│   API    │
│          │         │(Express)│         │(FastAPI) │
└──────────┘         │  :3000  │         │  :8000   │
                     └─────────┘         └────┬─────┘
                                              │
                                              ▼
                                         ┌──────────┐
                                         │  Redis   │
                                         │  :6379   │
                                         └──────────┘
                                              ▲
                                              │ (brpop)
                                         ┌────┴─────┐
                                         │  Worker  │
                                         │ (Python) │
                                         └──────────┘
```

| Service  | Language | Port | Purpose                                                |
| -------- | -------- | ---- | ------------------------------------------------------ |
| api      | Python   | 8000 | FastAPI — creates jobs, returns job status             |
| worker   | Python   | –    | Consumes jobs from Redis queue, processes them         |
| frontend | Node.js  | 3000 | Express proxy to the API (no browser-facing API calls) |
| redis    | Redis 7  | 6379 | Job queue and status store                             |

---

## Prerequisites

Confirmed to work on a clean Ubuntu 22.04 / 24.04 machine and macOS (Intel + Apple Silicon).

You need:

- **Docker Engine** — 24.0 or newer. Install via [Docker's official instructions](https://docs.docker.com/engine/install/).
- **Docker Compose v2** — included with Docker Desktop and modern Docker Engine installs. Verify with `docker compose version` (note the space, not a hyphen).
- **Git** — to clone the repository.
- A terminal that runs bash or zsh.

Verify your install:

```bash
docker --version           # Docker version 24.x or higher
docker compose version     # Docker Compose version v2.x or higher
git --version              # any recent version
```

No Python, Node.js, or Redis needs to be installed on the host — everything runs in containers.

---

## Quick Start

From a fresh terminal on a clean machine:

```bash
# 1. Clone the repository
git clone https://github.com/ik-alex/hng14-stage2-devops.git
cd hng14-stage2-devops

# 2. Create your .env file from the template
cp .env.example .env

# 3. Set a strong Redis password (one command, no manual editing needed)
#    Linux:
sed -i "s|^REDIS_PASSWORD=.*|REDIS_PASSWORD=$(openssl rand -base64 32)|" .env
#    macOS:
# sed -i '' "s|^REDIS_PASSWORD=.*|REDIS_PASSWORD=$(openssl rand -base64 32)|" .env

# 4. Build and start the full stack
docker compose up --build -d

# 5. Wait for services to become healthy (takes ~30 seconds)
docker compose ps
```

When everything is ready, `docker compose ps` will show all four services as `Up` and `healthy`:

```
NAME                                   STATUS                    PORTS
redis-server                           Up (healthy)              0.0.0.0:6379->6379/tcp
hng14-stage2-devops-api-1              Up (healthy)              0.0.0.0:8000->8000/tcp
hng14-stage2-devops-worker-1           Up
hng14-stage2-devops-frontend-1         Up                        0.0.0.0:3000->3000/tcp
```

---

## Verifying It Works

Submit a job through the frontend and poll until it completes:

```bash
# 1. Health check
curl http://localhost:8000/healthz
# Expected: {"status":"ok"}

# 2. Submit a job
JOB_ID=$(curl -sf -X POST http://localhost:3000/submit | python3 -c "import sys,json; print(json.load(sys.stdin)['job_id'])")
echo "Created job: $JOB_ID"

# 3. Wait a few seconds for the worker, then check status
sleep 3
curl http://localhost:3000/status/$JOB_ID
# Expected: {"job_id":"...","status":"completed"}
```

A successful run looks like this:

```
$ curl http://localhost:8000/healthz
{"status":"ok"}

$ curl -X POST http://localhost:3000/submit
{"job_id":"a7f3c2e1-8b4d-4e9f-b2a1-f8c6d9e5a3b2"}

$ sleep 3 && curl http://localhost:3000/status/a7f3c2e1-8b4d-4e9f-b2a1-f8c6d9e5a3b2
{"job_id":"a7f3c2e1-8b4d-4e9f-b2a1-f8c6d9e5a3b2","status":"completed"}
```

---

## What a Successful Startup Looks Like

When you run `docker compose up --build`, the expected output includes:

```
 ✔ Image hng14-stage2-devops-api            Built
 ✔ Image hng14-stage2-devops-worker         Built
 ✔ Image hng14-stage2-devops-frontend       Built
 ✔ Network hng14-stage2-devops_default      Created
 ✔ Container redis-server                   Healthy
 ✔ Container hng14-stage2-devops-worker-1   Started
 ✔ Container hng14-stage2-devops-api-1      Healthy
 ✔ Container hng14-stage2-devops-frontend-1 Started
```

The key indicators of success:

- All three images build without errors
- `redis-server` becomes **Healthy** (not just Started)
- `api` becomes **Healthy** (not just Started) — this confirms the `/healthz` endpoint is reachable and Redis connectivity works
- Worker logs show `Worker started`
- Frontend logs show `Frontend running on port 3000`

---

## Common Operations

```bash
# View live logs from all services
docker compose logs -f

# View logs from a specific service
docker compose logs -f worker

# Restart a single service
docker compose restart api

# Stop everything (preserves volumes)
docker compose down

# Stop everything AND remove volumes (full reset)
docker compose down -v

# Rebuild after code changes
docker compose up --build -d

# Check service health
docker compose ps
```

---

## Troubleshooting

| Symptom                                         | Likely cause                                         | Fix                                                                    |
| ----------------------------------------------- | ---------------------------------------------------- | ---------------------------------------------------------------------- |
| API container shows `unhealthy`                 | Redis hostname mismatch or password wrong            | Check `REDIS_HOST=redis-server` in compose; verify `.env` exists       |
| `NOAUTH Authentication required` in worker logs | Redis requires password but worker isn't sending one | Confirm `.env` has `REDIS_PASSWORD` and compose passes it              |
| `Cannot connect to the Docker daemon`           | Docker Desktop not running                           | Start Docker Desktop or `sudo systemctl start docker`                  |
| `docker compose: command not found`             | Docker Compose v2 not installed                      | Upgrade Docker Engine; v2 ships with modern installs                   |
| Port 8000 / 3000 / 6379 already in use          | Another service is using that port                   | Stop the conflicting service, or edit `ports:` in `docker-compose.yml` |
| Job stuck in `queued` status                    | Worker can't reach Redis                             | Check worker logs: `docker compose logs worker`                        |

For a full reset:

```bash
docker compose down -v
docker system prune -af
docker compose up --build -d
```

---

## Repository Layout

```
.
├── api/                      # FastAPI service
│   ├── Dockerfile            # Multi-stage, non-root, with healthcheck
│   ├── .dockerignore
│   ├── main.py               # POST /jobs, GET /jobs/{id}, /healthz, /readyz
│   ├── requirements.txt      # Runtime deps
│   ├── requirements-dev.txt  # Test deps (pytest, coverage)
│   └── tests/
│       └── test_main.py      # Unit tests with mocked Redis
├── worker/                   # Background job processor
│   ├── Dockerfile
│   ├── .dockerignore
│   ├── worker.py             # brpop loop with graceful shutdown + error handling
│   └── requirements.txt
├── frontend/                 # Express proxy
│   ├── Dockerfile
│   ├── .dockerignore
│   ├── app.js
│   ├── package.json
│   ├── .eslintrc.json
│   └── views/
├── scripts/
│   ├── integration-test.sh   # End-to-end job flow verification
│   └── deploy.sh             # Rolling update with health-gate + rollback
├── .github/
│   └── workflows/
│       └── ci-cd.yml         # 6-stage pipeline
├── .hadolint.yaml            # Dockerfile lint config
├── .env.example              # Template for local setup (committed)
├── .env                      # Local secrets (NOT committed, gitignored)
├── .gitignore
├── docker-compose.yml
├── FIXES.md                  # Bugs found and how they were fixed
└── README.md                 # You are here
```

---

## CI/CD Pipeline

Every push to `main` (and every pull request) runs a 6-stage pipeline on GitHub Actions:

```
lint → test → build → security-scan → integration-test → deploy
```

Each stage gates the next — a failure blocks all downstream stages.

| Stage                | What it does                                                                                      |
| -------------------- | ------------------------------------------------------------------------------------------------- |
| **lint**             | `flake8` (Python), `eslint` (JS), `hadolint` (Dockerfiles)                                        |
| **test**             | `pytest` with coverage ≥ 70%, Redis mocked; uploads HTML + XML coverage as artifacts              |
| **build**            | Builds 3 images, tags each with git SHA + `latest`, pushes to a local registry service container  |
| **security-scan**    | Trivy scans each image; fails on any CRITICAL; uploads SARIF artifacts                            |
| **integration-test** | Brings the full stack up, submits a real job, polls until completed, tears down on any outcome    |
| **deploy**           | Pushes to `main` only — scripted rolling update with 60s health-check gate and automatic rollback |

See `.github/workflows/ci-cd.yml` for details.

---

## Security Notes

- Secrets are injected via environment variables at runtime. No secrets are baked into images.
- `.env` is gitignored and excluded from every Docker build context via `.dockerignore`.
- All three services run as **non-root** users inside their containers.
- Images use **multi-stage builds** — final images contain no build tools or dev dependencies.
- All images pass Trivy's CRITICAL-severity scan as part of CI.
- Redis requires a password (`--requirepass`) — passwordless Redis is never exposed.

---

## License

MIT
