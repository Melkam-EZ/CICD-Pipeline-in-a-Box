#!/usr/bin/env bash
# Live demo of the pipeline. Usage: ./scripts/demo.sh [good|bad-test|bad-health|all]
#   good        bump the version  -> tests pass -> deployed
#   bad-test    break a unit test -> pipeline FAILS at tests -> nothing deployed
#   bad-health  bug that tests miss (app listens on loopback only) -> deploy
#               is BLOCKED by the health gate -> old version keeps serving
# After each bad scenario a revert commit is pushed and goes green again.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
need_env

WORKDIR="$ROOT/.demo/hello-app"
REMOTE="http://${DEMO_USER}:${DEMO_PASSWORD}@127.0.0.1:3000/${DEMO_USER}/hello-app.git"
GIT_ID=(-c user.name="CI Demo" -c user.email="demo@example.local")

prepare() {
  mkdir -p "$ROOT/.demo"
  if [ -d "$WORKDIR/.git" ]; then
    git -C "$WORKDIR" fetch -q origin
    git -C "$WORKDIR" reset -q --hard origin/main
  else
    git clone -q "$REMOTE" "$WORKDIR"
  fi
}

live_version() {
  curl -fsS --max-time 3 http://127.0.0.1:8081/ |
    python3 -c 'import sys, json; print(json.load(sys.stdin)["version"])'
}

push_and_expect() { # EXPECTED_STATE   (commit already created locally)
  local expect="$1" sha state
  git -C "$WORKDIR" push -q origin HEAD:main
  sha="$(git -C "$WORKDIR" rev-parse HEAD)"
  log "Pushed ${sha:0:7}. Waiting for the pipeline (watch it in the Gitea Actions tab)..."
  state="$(wait_pipeline "$sha" 300 || true)"
  echo "    pipeline result: ${state} (expected: ${expect})"
  [ "$state" = "$expect" ] || die "unexpected pipeline result"
}

commit_all() { git -C "$WORKDIR" "${GIT_ID[@]}" commit -q -am "$1"; }
revert_and_push() {
  log "Pushing a revert so the pipeline goes green again"
  git -C "$WORKDIR" "${GIT_ID[@]}" revert --no-edit HEAD >/dev/null
  push_and_expect success
}

scenario_good() {
  prepare
  local cur minor new
  cur="$(sed -n 's/^VERSION = "\(.*\)"/\1/p' "$WORKDIR/app/main.py")"
  minor="$(echo "$cur" | cut -d. -f2)"
  new="1.$((minor + 1)).0"
  log "SCENARIO good: version ${cur} -> ${new} (tests pass, deploy succeeds)"
  sed -i "s/^VERSION = \".*\"/VERSION = \"${new}\"/" "$WORKDIR/app/main.py"
  commit_all "Bump version to ${new}"
  push_and_expect success
  [ "$(live_version)" = "$new" ] || die "live version is not ${new}"
  ok "Live app now reports version ${new}"
}

scenario_bad_test() {
  prepare
  local before
  before="$(live_version)"
  log "SCENARIO bad-test: change the greeting so a unit test fails"
  sed -i 's/Hello, /Howdy, /' "$WORKDIR/app/main.py"
  commit_all "Change greeting (breaks unit test)"
  push_and_expect failure
  [ "$(live_version)" = "$before" ] || die "live version changed unexpectedly"
  ok "Pipeline stopped at the test stage. Live app still on ${before}"
  revert_and_push
}

scenario_bad_health() {
  prepare
  local before
  before="$(live_version)"
  log "SCENARIO bad-health: app binds to loopback only (tests cannot see it, the health gate can)"
  sed -i 's/^HOST = "0.0.0.0"/HOST = "127.0.0.1"/' "$WORKDIR/app/main.py"
  commit_all "Bind to loopback (breaks the container)"
  push_and_expect failure
  [ "$(live_version)" = "$before" ] || die "live version changed unexpectedly"
  ok "Deploy blocked by the health gate. Live app still on ${before}"
  revert_and_push
}

case "${1:-all}" in
  good) scenario_good ;;
  bad-test) scenario_bad_test ;;
  bad-health) scenario_bad_health ;;
  all) scenario_good; scenario_bad_test; scenario_bad_health ;;
  *) die "usage: $0 [good|bad-test|bad-health|all]" ;;
esac
echo
echo "Demo finished. Registry tags: $(curl -fsS http://127.0.0.1:5000/v2/hello-app/tags/list)"
