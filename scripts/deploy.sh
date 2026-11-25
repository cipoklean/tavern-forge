#!/usr/bin/env bash
# Deploy one Gno package directory to the onyx-1 testnet with `gnokey maketx addpkg`.
#
# usage: scripts/deploy.sh <pkgdir>
#
# Steps: read the module path from <pkgdir>/gnomod.toml, run `gno lint` and
# `gno test` on the directory, refuse if the path already exists on chain
# (live or inert), then broadcast addpkg. gnokey prompts for the key password.
#
# Environment overrides:
#   KEY          gnokey key name            (default: dev)
#   GAS_WANTED   gas limit                  (default: 200000000; onyx min gas price is 1ugnot per 1000 gas)
#   GAS_FEE      flat gas fee               (default: 250000ugnot)
#   MAX_DEPOSIT  max storage deposit        (default: 30000000ugnot)
#   CHAIN_ID     chain id                   (default: onyx-1)
#   REMOTE       RPC endpoint               (default: https://rpc.onyx.testnets.gno.land:443)
#   GNOWEB       gnoweb base URL            (default: https://latest.testnets.gno.land)
#   GNOKEY_HOME  gnokey home, passed only if set (default: gnokey's own default)
set -euo pipefail

KEY="${KEY:-dev}"
GAS_WANTED="${GAS_WANTED:-200000000}"
GAS_FEE="${GAS_FEE:-250000ugnot}"
MAX_DEPOSIT="${MAX_DEPOSIT:-30000000ugnot}"
CHAIN_ID="${CHAIN_ID:-onyx-1}"
REMOTE="${REMOTE:-https://rpc.onyx.testnets.gno.land:443}"
GNOWEB="${GNOWEB:-https://latest.testnets.gno.land}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

die() { printf 'deploy: error: %s\n' "$*" >&2; exit 1; }
step() { printf '\n==> %s\n' "$*"; }

[ $# -eq 1 ] || die "usage: $0 <pkgdir>   (e.g. $0 grc1155/v0)"
command -v gno >/dev/null || die "gno not found in PATH"
command -v gnokey >/dev/null || die "gnokey not found in PATH"

[ -d "$1" ] || die "package directory not found: $1"
PKGDIR="$(cd "$1" && pwd)"
MOD="$PKGDIR/gnomod.toml"
[ -f "$MOD" ] || die "no gnomod.toml in $PKGDIR"

# module = "gno.land/..."
PKGPATH="$(sed -n -E 's/^[[:space:]]*module[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "$MOD" | head -n1)"
[ -n "$PKGPATH" ] || die "could not read module path from $MOD"
case "$PKGPATH" in
  gno.land/p/*|gno.land/r/*) ;;
  *) die "unexpected module path '$PKGPATH' in $MOD" ;;
esac

printf 'package : %s\n' "$PKGPATH"
printf 'dir     : %s\n' "$PKGDIR"
printf 'chain   : %s via %s\n' "$CHAIN_ID" "$REMOTE"
printf 'key     : %s\n' "$KEY"

# Run lint/test from the workspace root so gnowork.toml resolves sibling
# packages (e.g. forge importing grc1155).
cd "$ROOT"
REL="$PKGDIR"
case "$PKGDIR" in
  "$ROOT"/*) REL="./${PKGDIR#"$ROOT"/}" ;;
esac

step "gno lint $REL"
gno lint "$REL" || die "gno lint failed; not deploying"

step "gno test $REL"
gno test "$REL" || die "gno test failed; not deploying"

step "checking on-chain status"
if ! META="$(gnokey query vm/qpkgmeta_json -data "$PKGPATH" -remote "$REMOTE" 2>&1)"; then
  printf '%s\n' "$META" >&2
  die "status query failed; refusing to deploy blind"
fi
STATUS="$(printf '%s\n' "$META" | sed -n -E 's/.*"status":"([^"]*)".*/\1/p' | head -n1)"
case "$STATUS" in
  absent)
    echo "status: absent -> ok to deploy" ;;
  live|inert)
    echo "status: $STATUS -> already on chain, not deploying."
    printf '%s\n' "$META" | sed -n 's/^data: //p'
    echo "view: $GNOWEB/${PKGPATH#gno.land/}"
    if [ "$STATUS" = inert ]; then
      echo "(inert = waiting for an approver to enable it)"
    fi
    exit 1 ;;
  *)
    printf '%s\n' "$META" >&2
    die "unrecognised status '${STATUS:-<none>}'; refusing to deploy" ;;
esac

ARGS=(
  -pkgpath "$PKGPATH"
  -pkgdir "$PKGDIR"
  -gas-fee "$GAS_FEE"
  -gas-wanted "$GAS_WANTED"
  -max-deposit "$MAX_DEPOSIT"
  -chainid "$CHAIN_ID"
  -remote "$REMOTE"
)
if [ -n "${GNOKEY_HOME:-}" ]; then
  ARGS+=(-home "$GNOKEY_HOME")
fi

step "gnokey maketx addpkg (you will be prompted for the '$KEY' password)"
printf 'gnokey maketx addpkg'; printf ' %q' "${ARGS[@]}" "$KEY"; printf '\n\n'
gnokey maketx addpkg "${ARGS[@]}" "$KEY"

step "submitted"
echo "Onyx parks new packages as inert until an approver enables them."
echo "check: scripts/status.sh $PKGPATH"
echo "view : $GNOWEB/${PKGPATH#gno.land/}"
