#!/usr/bin/env bash
# usage: poll_pkg.sh <pkgpath> ; logs to ~/gnome-tavern/poll.log until status != inert
P="$1"; R=https://rpc.onyx.testnets.gno.land:443
while :; do
  out=$(gnokey query vm/qpkgmeta_json -data "$P" -remote "$R" 2>&1 | sed -n 's/^data: //p')
  st=$(printf %s "$out" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("status","?"))' 2>/dev/null || echo err)
  echo "$(date -u +%FT%TZ) $P $st" >> ~/gnome-tavern/poll.log
  [ "$st" != inert ] && [ "$st" != err ] && { echo "$out" >> ~/gnome-tavern/poll.log; break; }
  sleep 60
done
