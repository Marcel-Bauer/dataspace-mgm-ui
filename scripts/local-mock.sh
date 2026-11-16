#!/usr/bin/env bash
#################################################################################
#  Copyright (c) 2026 Contributors to the Eclipse Foundation
#
#  See the NOTICE file(s) distributed with this work for additional
#  information regarding copyright ownership.
#
#  This program and the accompanying materials are made available under the
#  terms of the Apache License, Version 2.0 which is available at
#  https://www.apache.org/licenses/LICENSE-2.0.
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#  WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#  License for the specific language governing permissions and limitations
#  under the License.
#
#  AI Disclosure: This file was entirely AI-generated.
#  The AI-generated portions are made available under CC0-1.0 and not subject
#  to the project's license. The human contributor has reviewed and verified
#  that the code is correct.
#
#  SPDX-License-Identifier: Apache-2.0 AND CC0-1.0
#  Assisted-By: Claude Code (claude-opus-5-5)
#################################################################################
#
# Runs the portal locally in mock mode: every core package on its in-memory adapter (apps/portal/src/core/mock-container.ts),
# no backend, no BFF, no Keycloak, no Docker.
#
# Usage: scripts/local-mock.sh [command] [options]
#
# Commands
#   dev        (default) Vite dev server with hot reload                           → http://localhost:4200
#   preview    production build with mocks (dist/apps/portal-mock), served by `vite preview` → http://localhost:4300
#              (what a deployment serves, minus nginx; VITE_* are baked in at build time)
#   stop       stops the instance started with --background on that port
#   status     shows the instances started with --background
#   logs       follows the log of the instance on that port
#   persons    lists the test persons of MOCK_PERSONS
#
# Options
#   -p, --person <key>   test person signed in (default demo: Company Admin of Beispiel Maschinenbau GmbH, sees every
#                        company-side feature; `none` starts signed out; see `persons`)
#   -P, --port <port>    port (default 4200 for dev, 4300 for preview)
#   -b, --background     run detached; log and pid in tmp/local-mock/
#       --install        run `npm ci` first (done anyway when node_modules is missing)
#   -h, --help
#
# Examples
#   scripts/local-mock.sh                          # demo person, hot reload on :4200
#   scripts/local-mock.sh dev -p otto -P 4370 -b   # OSP Admin, detached on :4370
#   scripts/local-mock.sh preview                  # production bundle on mock data on :4300
#   scripts/local-mock.sh stop -P 4370
#
# The browser remembers the person of the last session (sessionStorage `portal.mock.person`) and it wins over
# --person: use a new tab or the person switch of the app after changing it.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="$ROOT/tmp/local-mock"
MOCK_CONTAINER="$ROOT/apps/portal/src/core/mock-container.ts"

command_name="dev"
person="demo"
port=""
background=false
install=false

die() { echo "local-mock: $*" >&2; exit 1; }
usage() { sed -n '/^# Runs the portal/,/^# --person/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

case "${1:-}" in
  dev|preview|stop|status|logs|persons) command_name="$1"; shift ;;
esac
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--person) [[ $# -ge 2 ]] || die "$1 needs a value"; person="$2"; shift 2 ;;
    -P|--port) [[ $# -ge 2 ]] || die "$1 needs a value"; port="$2"; shift 2 ;;
    -b|--background) background=true; shift ;;
    --install) install=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
done

if [[ -z "$port" ]]; then
  if [[ "$command_name" == "preview" ]]; then port=4300; else port=4200; fi
fi
[[ "$port" =~ ^[0-9]+$ ]] || die "port must be a number: $port"
pid_file="$STATE_DIR/$port.pid"
log_file="$STATE_DIR/$port.log"

list_persons() {
  awk '/^export const MOCK_PERSONS/{f=1;next} f&&/^};/{exit} f' "$MOCK_CONTAINER" \
    | grep -oE "^  '?[a-z0-9-]+'?:" | tr -d " ':"
}

running_pid() {
  [[ -f "$pid_file" ]] || return 1
  local pid; pid="$(cat "$pid_file")"
  if kill -0 "$pid" 2>/dev/null; then echo "$pid"; else rm -f "$pid_file"; return 1; fi
}

case "$command_name" in
  persons)
    list_persons
    echo "none   (signed out)"
    exit 0 ;;
  status)
    shopt -s nullglob
    found=false
    for f in "$STATE_DIR"/*.pid; do
      p="$(basename "$f" .pid)"
      if kill -0 "$(cat "$f")" 2>/dev/null; then
        echo "running  http://localhost:$p  pid $(cat "$f")  $(head -1 "$STATE_DIR/$p.log" 2>/dev/null)"; found=true
      else
        rm -f "$f"
      fi
    done
    $found || echo "no instance started with --background is running"
    exit 0 ;;
  stop)
    pid="$(running_pid)" || die "nothing started with --background runs on :$port"
    # The pid is the leader of its own process group (set -m below): stop npm, nx and vite together.
    kill -- "-$pid" 2>/dev/null || kill "$pid"
    rm -f "$pid_file"
    echo "stopped :$port (pid $pid)"
    exit 0 ;;
  logs)
    [[ -f "$log_file" ]] || die "no log for :$port"
    exec tail -f "$log_file" ;;
esac

# ---- dev / preview ----

# Node is often only on the login shell's PATH (Homebrew, nvm, Volta).
if ! command -v npm >/dev/null 2>&1; then
  for d in /opt/homebrew/bin /usr/local/bin "$HOME/.volta/bin"; do
    [[ -x "$d/npm" ]] && PATH="$d:$PATH" && break
  done
fi
command -v npm >/dev/null 2>&1 || die "npm not found: install Node.js 24 or newer"
node_major="$(node -p 'process.versions.node.split(".")[0]')"
(( node_major >= 24 )) || die "Node.js 24 or newer is needed (found $(node -v))"

if [[ "$person" != "none" ]] && ! list_persons | grep -qx -- "$person"; then
  die "unknown person '$person'; one of: $(list_persons | tr '\n' ' ')none"
fi

if pid="$(running_pid)"; then die "already running on :$port (pid $pid); stop it with: $0 stop -P $port"; fi
if command -v lsof >/dev/null 2>&1 && lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
  die "port $port is in use; pick another with --port"
fi

cd "$ROOT"
if $install || [[ ! -d node_modules ]]; then
  echo "local-mock: npm ci"
  npm ci
fi

export VITE_USE_MOCKS=true
export VITE_MOCK_PERSON="$person"
export NX_DAEMON=false

if [[ "$command_name" == "dev" ]]; then
  run=(npx nx serve portal --port "$port")
  label="dev server (hot reload)"
else
  echo "local-mock: building the portal with mocks (person $person) → dist/apps/portal-mock"
  (cd apps/portal && npx vite build --mode production --outDir ../../dist/apps/portal-mock)
  run=(npx vite preview --outDir ../../dist/apps/portal-mock --port "$port" --strictPort)
  cd apps/portal
  label="production build"
fi

url="http://localhost:$port"
if $background; then
  mkdir -p "$STATE_DIR"
  echo "$command_name person=$person $(date '+%Y-%m-%d %H:%M')" > "$log_file"
  set -m  # own process group, so `stop` can end the whole tree
  nohup "${run[@]}" >>"$log_file" 2>&1 &
  echo $! > "$pid_file"
  set +m
  for _ in $(seq 1 60); do
    curl -fsS -o /dev/null "$url" 2>/dev/null && break
    kill -0 "$(cat "$pid_file")" 2>/dev/null || { tail -20 "$log_file"; die "it stopped, see $log_file"; }
    sleep 1
  done
  echo "local-mock: $label on mock data, person $person → $url"
  echo "            logs: $0 logs -P $port   stop: $0 stop -P $port"
else
  echo "local-mock: $label on mock data, person $person → $url (Ctrl+C stops it)"
  exec "${run[@]}"
fi
