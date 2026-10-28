#!/usr/bin/env bash
# Health check of the whole stack. Ends with "All N checks passed."
set -uo pipefail
. "$(dirname "$0")/lib.sh"
need_env

PASS=0
TOTAL=0
check() { # LABEL COMMAND...
  local label="$1"; shift
  TOTAL=$((TOTAL + 1))
  if "$@" >/dev/null 2>&1; then ok "$label"; PASS=$((PASS + 1)); else fail "$label"; fi
}

container_running() { [ "$($DOCKER inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" = "true" ]; }
runner_registered() { $DOCKER exec cicd-runner test -s /data/.runner; }
repo_exists() { curl -fsS -u "${DEMO_USER}:${DEMO_PASSWORD}" "${GITEA_URL}/api/v1/repos/${DEMO_USER}/hello-app"; }
pipeline_ok() { [ "$(wait_pipeline "$HEAD" 300)" = "success" ]; }
app_runs_head() { curl -fsS --max-time 3 http://127.0.0.1:8081/ | grep -q "$SHORT"; }
registry_has_latest() { curl -fsS http://127.0.0.1:5000/v2/hello-app/tags/list | grep -q latest; }

log "Smoke test"
check "Docker daemon reachable"         $DOCKER info
check "Gitea container running"         container_running cicd-gitea
check "Registry container running"      container_running cicd-registry
check "Runner container running"        container_running cicd-runner
check "Gitea API healthy"               curl -fsS "$GITEA_URL/api/healthz"
check "Registry answers /v2/"           curl -fsS http://127.0.0.1:5000/v2/
check "Runner registered with Gitea"    runner_registered
check "Repository demo/hello-app exists" repo_exists

HEAD="$(head_sha 2>/dev/null || true)"
SHORT="$(echo "$HEAD" | cut -c1-7)"
if [ -n "$HEAD" ]; then
  echo "    Waiting for the pipeline run of ${SHORT} (up to 5 minutes)..."
  check "Pipeline for latest commit succeeded" pipeline_ok
  check "Live app on :8081 runs commit ${SHORT}" app_runs_head
else
  TOTAL=$((TOTAL + 2)); fail "Could not read the latest commit from Gitea"
fi
check "Live app /healthz is ok"         curl -fsS --max-time 3 http://127.0.0.1:8081/healthz
check "Registry holds hello-app:latest" registry_has_latest

echo
if [ "$PASS" -eq "$TOTAL" ]; then
  echo "All ${TOTAL} checks passed."
  exit 0
fi
echo "$((TOTAL - PASS)) of ${TOTAL} checks failed." >&2
echo "--- runner logs (last 25 lines) ---" >&2
$DC logs --no-color --tail 25 runner 2>&1 >&2 || true
echo "See the troubleshooting table in STEPS.md." >&2
exit 1
