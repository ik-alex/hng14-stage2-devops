#!/bin/bash
set -euo pipefail

# =====================================================================
# Rolling update script
# Usage: ./deploy.sh <image> <service_name> <port> <health_path>
# Example: ./deploy.sh localhost:5000/api:abc1234 api 8000 /healthz
#
# Behavior:
#   1. Starts a new container named "<service>-new" from the given image.
#   2. Waits up to 60s for its Docker health check to pass.
#   3. If healthy: stops old container, renames new one to <service>.
#   4. If unhealthy within timeout: kills new container, leaves old running.
# =====================================================================

IMAGE="${1:?Usage: deploy.sh <image> <service_name> <port> <health_path>}"
SERVICE="${2:?Usage: deploy.sh <image> <service_name> <port> <health_path>}"
PORT="${3:?Usage: deploy.sh <image> <service_name> <port> <health_path>}"
HEALTH_PATH="${4:?Usage: deploy.sh <image> <service_name> <port> <health_path>}"

NEW_CONTAINER="${SERVICE}-new"
OLD_CONTAINER="${SERVICE}"
TIMEOUT=60
NETWORK="app-net"

echo "=========================================="
echo "Rolling update"
echo "  Image:         ${IMAGE}"
echo "  Service:       ${SERVICE}"
echo "  Port:          ${PORT}"
echo "  Health path:   ${HEALTH_PATH}"
echo "  Timeout:       ${TIMEOUT}s"
echo "=========================================="

# Clean up any leftover "new" container from a previous failed run
docker rm -f "${NEW_CONTAINER}" 2>/dev/null || true

echo ""
echo "[1/4] Starting new container: ${NEW_CONTAINER}"
docker run -d \
  --name "${NEW_CONTAINER}" \
  --network "${NETWORK}" \
  -e REDIS_HOST=redis-server \
  -e REDIS_PORT=6379 \
  -e REDIS_PASSWORD="${REDIS_PASSWORD}" \
  "${IMAGE}" > /dev/null

echo "Container started. Waiting up to ${TIMEOUT}s for health check..."
echo ""

# [2/4] Poll the health status
HEALTHY=0
for i in $(seq 1 ${TIMEOUT}); do
  STATUS=$(docker inspect --format='{{.State.Health.Status}}' "${NEW_CONTAINER}" 2>/dev/null || echo "missing")
  printf "  [%2d/%2d] health=%s\n" "${i}" "${TIMEOUT}" "${STATUS}"

  if [ "${STATUS}" = "healthy" ]; then
    HEALTHY=1
    break
  fi

  if [ "${STATUS}" = "unhealthy" ]; then
    echo ""
    echo "New container reported unhealthy status. Aborting deploy."
    break
  fi

  sleep 1
done

# [3/4] Act on the result
if [ "${HEALTHY}" -ne 1 ]; then
  echo ""
  echo "=========================================="
  echo "Rolling update FAILED"
  echo "=========================================="
  echo "New container failed to become healthy within ${TIMEOUT}s."
  echo "Dumping logs from new container:"
  echo "------------------------------------------"
  docker logs "${NEW_CONTAINER}" || true
  echo "------------------------------------------"
  echo "Removing failed new container, leaving old container running."
  docker rm -f "${NEW_CONTAINER}" > /dev/null
  echo ""
  echo "Current state:"
  docker ps --filter "name=${OLD_CONTAINER}" --format "table {{.Names}}\t{{.Status}}"
  exit 1
fi

echo ""
echo "[3/4] New container is healthy. Swapping in..."

# Stop and remove the old container (if it exists)
if docker ps -a --format '{{.Names}}' | grep -q "^${OLD_CONTAINER}$"; then
  echo "Stopping old container: ${OLD_CONTAINER}"
  docker stop "${OLD_CONTAINER}" > /dev/null
  docker rm "${OLD_CONTAINER}" > /dev/null
else
  echo "No existing container named '${OLD_CONTAINER}' — this is a first deploy."
fi

# Rename new container to take over
echo "Renaming ${NEW_CONTAINER} → ${OLD_CONTAINER}"
docker rename "${NEW_CONTAINER}" "${OLD_CONTAINER}"

echo ""
echo "[4/4] Rolling update complete."
echo ""
docker ps --filter "name=${OLD_CONTAINER}" --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"
echo ""
echo "=========================================="
echo "Rolling update SUCCEEDED"
echo "=========================================="
