#!/usr/bin/env bash
# Removes everything this project created on the instance.
# Usage: ./scripts/destroy.sh [--keep-env]
set -uo pipefail
. "$(dirname "$0")/lib.sh"

log "Stopping the stack and deleting its volumes"
$DC down -v --remove-orphans

log "Removing the deployed app and project images"
$DOCKER rm -f hello-app hello-app-candidate >/dev/null 2>&1 || true
$DOCKER images --format '{{.Repository}}:{{.Tag}}' |
  grep -E '^(localhost:5000/hello-app|hello-app|cicd-box-runner)' |
  xargs -r $DOCKER rmi -f >/dev/null 2>&1 || true
$DOCKER image prune -f >/dev/null 2>&1 || true

rm -rf "$ROOT/.demo"
if [ "${1:-}" != "--keep-env" ]; then rm -f "$ROOT/.env"; fi

echo
echo "Cleanup done."
echo "IMPORTANT: terminate the EC2 instance in the AWS console (EC2 > Instances >"
echo "Instance state > Terminate) so it stops costing money."
