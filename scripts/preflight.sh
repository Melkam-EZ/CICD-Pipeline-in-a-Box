#!/usr/bin/env bash
# Run this BEFORE the demo. It pulls every image, builds the runner image and
# runs the unit tests, so any failure shows up now and not in front of an audience.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
ensure_env

FAILS=0
check() { # LABEL COMMAND...
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$label"; else fail "$label"; FAILS=$((FAILS + 1)); fi
}

pull_with_retry() { # IMAGE
  local i
  for i in 1 2 3; do
    $DOCKER pull "$1" >/dev/null 2>&1 && return 0
    sleep 3
  done
  return 1
}

disk_ok() { [ "$(df -BG --output=avail / | tail -n1 | tr -dc '0-9')" -ge 8 ]; }
mem_ok()  { [ "$(free -m | awk '/^Mem:/{print $2}')" -ge 3000 ]; }
port_free() { ! ss -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]$1$"; }
runner_image_tools() {
  $DOCKER run --rm --entrypoint sh cicd-box-runner:local \
    -c 'docker --version && docker buildx version && git --version && bash --version && curl --version'
}
host_unit_tests() { (cd sample-app && PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests); }

log "System checks"
check "Docker daemon reachable"       $DOCKER info
check "Docker Compose v2 installed"   $DC version
check "At least 8 GB free disk"       disk_ok
check "At least 3 GB RAM"             mem_ok
if [ -n "$($DC ps -q 2>/dev/null)" ]; then
  ok "Stack already running (port check skipped)"
else
  for p in 3000 5000 8081 8082; do check "Port $p is free" port_free "$p"; done
fi
check "Outbound internet (Docker Hub)" curl -sS -m 10 -o /dev/null https://registry-1.docker.io/v2/

log "Pulling images (up to 3 tries each)"
for img in "$GITEA_IMAGE" "$REGISTRY_IMAGE" "$RUNNER_BASE_IMAGE" "$DOCKER_CLI_IMAGE" "$PYTHON_IMAGE"; do
  check "Pull $img" pull_with_retry "$img"
done

log "Building the runner image"
check "Build runner image"              $DC build runner
check "Runner image has docker/buildx/git/bash/curl" runner_image_tools

log "Unit tests on the host"
check "sample-app unit tests"           host_unit_tests

echo
if [ "$FAILS" -eq 0 ]; then
  echo "Preflight passed. Safe to run ./scripts/up.sh"
  exit 0
fi
echo "Preflight found $FAILS problem(s). See the troubleshooting table in STEPS.md." >&2
echo "Image pull failed? Run 'sudo docker login' with a free Docker Hub account (avoids rate limits)," >&2
echo "or change the image tag in .env and re-run this script." >&2
exit 1
