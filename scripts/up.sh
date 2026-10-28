#!/usr/bin/env bash
# Starts Gitea + registry, creates the admin user, registers the CI runner,
# creates the hello-app repo and pushes the first commit (which triggers the first pipeline run).
set -euo pipefail
. "$(dirname "$0")/lib.sh"
ensure_env

log "Starting Gitea and the registry"
$DC up -d gitea registry
wait_http "Gitea" "$GITEA_URL/api/healthz" 120
wait_http "Registry" "http://127.0.0.1:5000/v2/" 60

log "Creating Gitea admin user '${DEMO_USER}'"
if $DC exec -T -u git gitea gitea admin user list 2>/dev/null | grep -qw "$DEMO_USER"; then
  ok "user already exists"
else
  $DC exec -T -u git gitea gitea admin user create --admin \
    --username "$DEMO_USER" --password "$DEMO_PASSWORD" \
    --email "${DEMO_USER}@example.local" --must-change-password=false
fi

if [ -z "${RUNNER_TOKEN:-}" ]; then
  log "Generating the runner registration token"
  TOKEN="$($DC exec -T -u git gitea gitea actions generate-runner-token | tail -n1 | tr -d '\r\n ')"
  [ -n "$TOKEN" ] || die "could not generate a runner token"
  set_env RUNNER_TOKEN "$TOKEN"
  load_env
fi

log "Building and starting the CI runner"
$DC up -d --build runner

log "Creating repository ${DEMO_USER}/hello-app"
code="$(api POST /user/repos -d '{"name":"hello-app","private":false,"default_branch":"main"}' -o /dev/null -w '%{http_code}')"
case "$code" in
  201) ok "repository created" ;;
  409) ok "repository already exists" ;;
  *) die "repository creation failed (HTTP $code)" ;;
esac
api PATCH "/repos/${DEMO_USER}/hello-app" -d '{"has_actions":true}' -o /dev/null || true

code="$(api GET "/repos/${DEMO_USER}/hello-app/branches/main" -o /dev/null -w '%{http_code}')"
if [ "$code" != "200" ]; then
  log "Pushing the first commit of sample-app (this triggers the first pipeline run)"
  WORK="$(mktemp -d)"
  cp -a sample-app/. "$WORK/"
  (
    cd "$WORK"
    git init -q -b main
    git add -A
    git -c user.name="CI Demo" -c user.email="demo@example.local" commit -q -m "Initial commit: hello-app v1.0.0"
    git push -q "http://${DEMO_USER}:${DEMO_PASSWORD}@127.0.0.1:3000/${DEMO_USER}/hello-app.git" main
  )
  rm -rf "$WORK"
else
  ok "main branch already exists, not pushing again"
fi

cat <<EOF

Stack is up.
  Gitea UI   : http://localhost:3000   (through your SSH tunnel)
  Login      : ${DEMO_USER} / ${DEMO_PASSWORD}   (also saved in .env)
  Watch run  : http://localhost:3000/${DEMO_USER}/hello-app/actions
  Live app   : http://localhost:8081   (after the first pipeline run succeeds)

Next: ./scripts/smoke.sh   (waits for the first pipeline run, then checks everything)
EOF
