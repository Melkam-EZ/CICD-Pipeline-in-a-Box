#!/usr/bin/env bash
# Health-gated deploy with automatic rollback.
#   1. start the new image as a "candidate" on a side port
#   2. health-check it from outside the container
#   3. only if healthy: replace the live container
#   4. if the swap itself fails: restart the previous image
# If step 2 fails, the live container is never touched.
set -euo pipefail

IMAGE="${1:?usage: deploy.sh <image:tag>}"
APP="${APP_NAME:-hello-app}"
LIVE_PORT="${LIVE_PORT:-8081}"
CAND_PORT="${CAND_PORT:-8082}"
CAND="${APP}-candidate"

wait_healthy() { # port, tries
  local port="$1" tries="${2:-20}" i
  for ((i = 1; i <= tries; i++)); do
    if curl -fsS --max-time 2 "http://127.0.0.1:${port}/healthz" 2>/dev/null | grep -q '"status": "ok"'; then
      return 0
    fi
    sleep 1
  done
  return 1
}

run_container() { # name, port, image
  docker run -d --name "$1" --restart unless-stopped \
    --memory 128m -p "127.0.0.1:$2:8080" "$3" >/dev/null
}

echo "==> Deploying ${IMAGE}"
docker rm -f "$CAND" >/dev/null 2>&1 || true

echo "==> Starting candidate on port ${CAND_PORT}"
docker run -d --name "$CAND" --restart no --memory 128m \
  -p "127.0.0.1:${CAND_PORT}:8080" "$IMAGE" >/dev/null

if ! wait_healthy "$CAND_PORT" 20; then
  echo "!! Candidate failed its health check. Container logs:"
  docker logs --tail 20 "$CAND" || true
  docker rm -f "$CAND" >/dev/null 2>&1 || true
  echo "!! Deploy BLOCKED. The previous version is still serving on port ${LIVE_PORT}."
  exit 1
fi
echo "==> Candidate is healthy"
docker rm -f "$CAND" >/dev/null 2>&1 || true

PREVIOUS_IMAGE="$(docker inspect -f '{{.Config.Image}}' "$APP" 2>/dev/null || true)"
docker rm -f "$APP" >/dev/null 2>&1 || true

echo "==> Switching live container to the new version"
run_container "$APP" "$LIVE_PORT" "$IMAGE"

if wait_healthy "$LIVE_PORT" 20; then
  echo "==> Deploy OK: ${IMAGE} is live on port ${LIVE_PORT}"
  exit 0
fi

echo "!! Live container unhealthy after the swap. Rolling back."
docker rm -f "$APP" >/dev/null 2>&1 || true
if [ -n "$PREVIOUS_IMAGE" ]; then
  run_container "$APP" "$LIVE_PORT" "$PREVIOUS_IMAGE"
  echo "!! Rolled back to ${PREVIOUS_IMAGE}"
fi
exit 1
