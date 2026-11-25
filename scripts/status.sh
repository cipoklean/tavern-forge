#!/usr/bin/env bash
# Print the on-chain status (live | inert | absent) of Gno packages on onyx-1.
#
# usage: scripts/status.sh [pkgpath...]
#   default paths: hello, grc1155/v0, forge/v0 under the project namespace.
#
# Environment overrides:
#   REMOTE  RPC endpoint   (default: https://rpc.onyx.testnets.gno.land:443)
#   GNOWEB  gnoweb base    (default: https://latest.testnets.gno.land)
set -euo pipefail

REMOTE="${REMOTE:-https://rpc.onyx.testnets.gno.land:443}"
GNOWEB="${GNOWEB:-https://latest.testnets.gno.land}"
NS="g1j9c3manpp89kdyhjjqqyugty70kjy5w4sw9y0m"

command -v gnokey >/dev/null || { echo "status: gnokey not found in PATH" >&2; exit 1; }

if [ $# -eq 0 ]; then
  set -- \
    "gno.land/r/$NS/hello" \
    "gno.land/p/$NS/grc1155/v0" \
    "gno.land/r/$NS/forge/v0"
fi

rc=0
for p in "$@"; do
  if out="$(gnokey query vm/qpkgmeta_json -data "$p" -remote "$REMOTE" 2>&1)"; then
    st="$(printf '%s\n' "$out" | sed -n -E 's/.*"status":"([^"]*)".*/\1/p' | head -n1)"
    st="${st:-unknown}"
  else
    st="error"
    rc=1
    printf '%s\n' "$out" | head -n 3 | sed "s|^|  [$p] |" >&2
  fi
  printf '%-8s %-62s %s/%s\n' "$st" "$p" "$GNOWEB" "${p#gno.land/}"
done
exit "$rc"
