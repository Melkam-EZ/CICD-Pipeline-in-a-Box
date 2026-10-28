#!/usr/bin/env bash
# Shared helpers. Sourced by the other scripts, not run directly.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

# Use plain docker if the current user may talk to the daemon, otherwise sudo.
if docker info >/dev/null 2>&1; then DOCKER="docker"; else DOCKER="sudo docker"; fi
DC="$DOCKER compose"
GITEA_URL="http://127.0.0.1:3000"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '  \033[1;32mok\033[0m   %s\n' "$*"; }
fail() { printf '  \033[1;31mFAIL\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

load_env() { set -a; . "$ROOT/.env"; set +a; }

set_env() { # KEY VALUE: replace the line in .env, or append it
  local k="$1" v="$2"
  if grep -q "^${k}=" "$ROOT/.env"; then
    sed -i "s|^${k}=.*|${k}=${v}|" "$ROOT/.env"
  else
    echo "${k}=${v}" >> "$ROOT/.env"
  fi
}

ensure_env() { # create .env with generated secrets on first run
  [ -f "$ROOT/.env" ] || cp "$ROOT/.env.example" "$ROOT/.env"
  load_env
  [ -n "${GITEA_SECRET_KEY:-}" ] || set_env GITEA_SECRET_KEY "$(openssl rand -hex 32)"
  [ -n "${DEMO_PASSWORD:-}" ]    || set_env DEMO_PASSWORD "$(openssl rand -hex 10)"
  load_env
}

need_env() { [ -f "$ROOT/.env" ] || die ".env not found. Run ./scripts/up.sh first."; load_env; }

wait_http() { # LABEL URL [SECONDS]
  local label="$1" url="$2" secs="${3:-60}" i
  for ((i = 0; i < secs; i++)); do
    if curl -fsS -o /dev/null --max-time 2 "$url" 2>/dev/null; then ok "$label is up"; return 0; fi
    sleep 1
  done
  fail "$label did not answer at $url within ${secs}s"
  return 1
}

# Gitea API call with the demo user's credentials: api METHOD /path [curl args...]
api() {
  local method="$1" path="$2"; shift 2
  curl -sS -u "${DEMO_USER}:${DEMO_PASSWORD}" -H 'Content-Type: application/json' \
    -X "$method" "${GITEA_URL}/api/v1${path}" "$@"
}

head_sha() {
  api GET "/repos/${DEMO_USER}/hello-app/branches/main" |
    python3 -c 'import sys, json; print(json.load(sys.stdin)["commit"]["id"])'
}

# Poll the commit status that Gitea Actions reports. Prints success|failure|error|timeout.
wait_pipeline() { # SHA [SECONDS]
  local sha="$1" secs="${2:-300}" i state
  for ((i = 0; i < secs; i += 3)); do
    state="$(api GET "/repos/${DEMO_USER}/hello-app/commits/${sha}/status" 2>/dev/null |
      python3 -c 'import sys, json
try:
    print(json.load(sys.stdin).get("state", ""))
except Exception:
    print("")' 2>/dev/null)"
    case "$state" in success | failure | error) echo "$state"; return 0 ;; esac
    sleep 3
  done
  echo "timeout"
  return 1
}
