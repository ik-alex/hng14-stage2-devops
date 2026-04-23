# FIXES.md

Catalog of bugs and issues found in the starter code and the fixes applied. Organized by file.

---

## `api/main.py`

### Fix 1 — Hardcoded Redis connection (lines 7–8)

**Bug:** Redis client was initialized with hardcoded host and port, ignoring environment variables. The `.env` file defined a `REDIS_PASSWORD` that was never read.

```python
# Before
r = redis.Redis(host="redis-server", port=6379)
```

**Fix:** Read connection details from environment variables with sensible defaults, and pass the password.

```python
# After
r = redis.Redis(
    host=os.getenv("REDIS_HOST", "redis-server"),
    port=int(os.environ.get("REDIS_PORT", 6379)),
    password=os.environ.get("REDIS_PASSWORD"),
)
```

### Fix 2 — `/jobs/{job_id}` returned 200 on missing job

**Bug:** When a job didn't exist, the handler returned `{"error": "not found"}` with a 200 OK status, making clients unable to distinguish success from failure via HTTP status.

**Fix:** Raise `HTTPException` with status 404 so the response carries a proper status code.

```python
# Before
if not status:
    return {"error": "not found"}

# After
if not status:
    raise HTTPException(status_code=404, detail="not found")
```

### Fix 3 — No health check endpoints

**Bug:** The Dockerfile's `HEALTHCHECK` instruction hits `/healthz`, but the route didn't exist. The container would be permanently marked unhealthy.

**Fix:** Added `/healthz` (liveness — always returns 200) and `/readyz` (readiness — pings Redis, returns 503 on failure).

```python
@app.get("/healthz")
def liveness():
    return {"status": "ok"}

@app.get("/readyz")
def readiness():
    try:
        r.ping()
        return {"status": "ready"}
    except redis.RedisError as e:
        return JSONResponse(
            status_code=503,
            content={"status": "not ready", "error": str(e)}
        )
```

---

## `worker/worker.py`

### Fix 4 — Unused `signal` import + no graceful shutdown (line 4)

**Bug:** `signal` was imported but never used. The `while True` loop had no way to exit cleanly, meaning Docker's `SIGTERM` would kill the worker mid-job.

**Fix:** Added signal handlers for `SIGTERM` and `SIGINT` that flip a shutdown flag. The main loop checks the flag between jobs, so any in-progress job completes before the process exits.

```python
shutdown_requested = False

def handle_shutdown(signum, frame):
    global shutdown_requested
    shutdown_requested = True

signal.signal(signal.SIGTERM, handle_shutdown)
signal.signal(signal.SIGINT, handle_shutdown)

while not shutdown_requested:
    ...
```

### Fix 5 — Hardcoded Redis connection (line 6)

**Bug:** Same as Fix 1 in `main.py` — Redis host/port hardcoded, password never read.

**Fix:** Same pattern — `os.environ.get(...)` with defaults.

### Fix 6 — Missing `import os`

**Bug:** After adding `os.environ.get(...)` calls, `import os` was accidentally omitted. The worker would crash on startup with `NameError: name 'os' is not defined`.

**Fix:** Added `import os` to the imports block.

### Fix 7 — No error handling around job processing

**Bug:** A single exception in `process_job` (bad data, Redis blip, anything) would crash the entire worker. One bad job would kill the whole service.

**Fix:** Wrapped the processing logic in layered try/except:

- Inner catch around `process_job` — logs the error, marks the job as `failed` in Redis, continues to the next job.
- Outer catches for `redis.ConnectionError` (sleep 5s, retry) and `redis.RedisError` (sleep 1s, retry).
- A final catch-all `except Exception` for anything unexpected.

`KeyboardInterrupt` and `SystemExit` (which inherit from `BaseException`) are deliberately not caught, so signal handling still works.

---

## `frontend/app.js`

### Fix 8 — Hardcoded `API_URL` (line 6)

**Bug:** `const API_URL = "http://localhost:8000"` — this works when running the app directly on a laptop, but fails when the frontend runs inside a container. Inside the frontend container, `localhost:8000` resolves to the frontend container itself, not the API container.

**Fix:** Read from environment variable so Compose can inject the correct internal DNS name (`http://api:8000`) at runtime:

```javascript
// Before
const API_URL = "http://localhost:8000";

// After
const API_URL = process.env.API_URL || "http://localhost:8000";
```

In `docker-compose.yml`, the frontend service sets `API_URL=http://api:8000`.

---

## `docker-compose.yml`

### Fix 9 — Redis ran without a password

**Bug:** Even though `.env` defined `REDIS_PASSWORD`, the Redis container wasn't configured to require it. Setting `REDIS_PASSWORD` as an environment variable on the Redis container does nothing — the official Redis image doesn't read that variable.

**Fix:** Pass `--requirepass` as a command-line flag to the Redis process and use Compose's `${REDIS_PASSWORD}` substitution:

```yaml
redis:
  image: redis:7-alpine
  command: redis-server --requirepass ${REDIS_PASSWORD}
```

### Fix 10 — No `depends_on` health conditions

**Bug:** API and worker could start before Redis was actually ready to accept connections, causing initial connection failures.

**Fix:** Added healthcheck to Redis and `depends_on: condition: service_healthy` to downstream services:

```yaml
redis:
  healthcheck:
    test: ["CMD", "redis-cli", "-a", "${REDIS_PASSWORD}", "ping"]
    interval: 30s
    timeout: 5s
    retries: 3

api:
  depends_on:
    redis:
      condition: service_healthy
```

---

## Dockerfiles

### Fix 11 — `api/` had no Dockerfile, no start command documented

**Bug:** The API directory contained only Python code and requirements. Docker had no way to build or start the service. `uvicorn` was in `requirements.txt` but nothing indicated how to launch `main:app`.

**Fix:** Wrote a production-quality multi-stage `api/Dockerfile`:

- Builder stage installs Python packages to `/install` via `pip install --prefix=/install`
- Runtime stage copies only installed packages (no build tools) to `/usr/local`
- Non-root `appuser` (UID 1000) created explicitly
- `HEALTHCHECK` instruction hits `/healthz` via curl
- `PYTHONUNBUFFERED=1` so logs appear immediately
- Exec-form `CMD` so uvicorn receives signals as PID 1

Same pattern applied to `worker/Dockerfile` (healthcheck uses a Python one-liner that calls `r.ping()` since the worker has no HTTP port) and `frontend/Dockerfile` (Node 20 Alpine, uses the built-in `node` user).

### Fix 12 — No `.dockerignore` files

**Bug:** Without `.dockerignore`, `COPY . .` drags in `.env`, `node_modules`, `.git`, `__pycache__`, local virtualenvs, etc. This bloats images, leaks secrets, and breaks builds (host-built native modules don't run in alpine).

**Fix:** Added a `.dockerignore` per service listing `.env`, `.git`, cache directories, and language-specific junk (`node_modules`, `__pycache__`, etc.).

---

## GitHub Actions workflow

### Fix 13 — Trivy action version didn't exist

**Bug:** Initial attempt used `aquasecurity/trivy-action@0.24.0`. The action's tags were migrated to use a `v` prefix (after a supply-chain incident earlier in 2025), so bare-number tags aren't consistently available.

**Fix:** Pinned to `aquasecurity/trivy-action@v0.36.0` (a real, signed tag).

### Fix 14 — Trivy SARIF output ignored `severity: CRITICAL`

**Bug:** With `format: sarif`, Trivy defaults to including **all** severities in the output regardless of the `severity` input. This made `exit-code: "1"` fire on low-severity findings, failing the pipeline even though no CRITICAL issues existed.

**Fix:** Added `limit-severities-for-sarif: true` to each SARIF-producing step.

### Fix 15 — `integration-test.sh` had no executable bit in git

**Bug:** `chmod +x` on a file only sets the local filesystem permission. Git stores permissions in its index, and the default `100644` mode is non-executable. The CI runner checked out the script without the executable bit, so `./scripts/integration-test.sh` failed with `Permission denied` (exit code 126).

**Fix:** Ran `git update-index --chmod=+x scripts/integration-test.sh` to set the bit in git's index. Also added a defensive `chmod +x scripts/*.sh` step in affected workflow jobs.

### Fix 16 — `test_main.py` missing trailing newline

**Bug:** `flake8` rule W292 failed because the test file didn't end with a newline character, which some editors strip on paste.

**Fix:** Appended a newline to the file.

---

## Other

### Fix 17 — `CORS origins` referenced the wrong port

**Bug:** `origins = ["http://localhost:8000"]` in `main.py` allowed the API's own port as a CORS origin instead of the frontend's port. This wouldn't affect the current architecture (frontend-to-api traffic is server-to-server and not subject to CORS), but is incorrect if a browser ever calls the API directly.

**Note:** Mentioned for awareness; not changed in current state since it doesn't affect functionality as architected.
