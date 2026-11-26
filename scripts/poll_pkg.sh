#!/usr/bin/env bash
# usage: scripts/poll_pkg.sh <pkgpath> ; logs to <repo>/poll.log until status != inert
P="${1:?usage: scripts/poll_pkg.sh <pkgpath>}"; R="${REMOTE:-https://rpc.onyx.testnets.gno.land:443}"
LOG="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/poll.log"
while :; do
  out=$(gnokey query vm/qpkgmeta_json -data "$P" -remote "$R" 2>&1 | sed -n 's/^data: //p')
  st=$(printf %s "$out" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("status","?"))' 2>/dev/null || echo err)
  echo "$(date -u +%FT%TZ) $P $st" >> "$LOG"
  [ "$st" != inert ] && [ "$st" != err ] && { echo "$out" >> "$LOG"; break; }
  sleep 60
done
