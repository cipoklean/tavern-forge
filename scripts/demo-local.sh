#!/usr/bin/env bash
# End-to-end Gnome Tavern demo against a LOCAL gnodev (fallback for the demo video).
#
# usage: scripts/demo-local.sh
#
# What it does:
#   1. creates a throwaway gnokey home (/tmp/gnodev-keys) holding gnodev's
#      well-known public test1 dev key (premined by gnodev) and a second
#      throwaway recipient key "bob" (same public mnemonic, HD index 1);
#   2. starts gnodev in the background from the project root (log:
#      /tmp/gnodev-demo.log) with empty blocks every second, so block-height
#      cooldowns elapse without sending filler txs;
#   3. calls hello.Visit as a smoke test;
#   4. FORGE SECTION (skipped if ./forge/v0 is missing or does not load):
#      Gather, Craft ingot, Craft sword, Transfer one item to bob, then prints
#      the forge home page and both inventory pages from gnoweb.
#   gnodev is killed on exit.
#
# The test1 mnemonic is public (gno.land/pkg/integration/node_testing.go,
# DefaultAccount_Seed); never reuse it on a real network. This script never
# touches the default gnokey home (~/.config/gno).
#
# Environment overrides:
#   KEYHOME              throwaway gnokey home      (default: /tmp/gnodev-keys)
#   LOG                  gnodev log file            (default: /tmp/gnodev-demo.log)
#   TRANSFER_ID          item id sent to bob        (default: sword)
#   MAX_GATHERS          extra Gather rounds allowed per craft (default: 6)
#   COOLDOWN_MAX_BLOCKS  blocks to wait for a Gather cooldown  (default: 15)
#   PAUSE                seconds to pause between steps, for recording (default: 0)
#   BOOT_TIMEOUT         seconds to wait for gnodev            (default: 180)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NS="g1j9c3manpp89kdyhjjqqyugty70kjy5w4sw9y0m"
HELLO="gno.land/r/$NS/hello"
FORGE="gno.land/r/$NS/forge/v0"

KEYHOME="${KEYHOME:-/tmp/gnodev-keys}"
LOG="${LOG:-/tmp/gnodev-demo.log}"
TRANSFER_ID="${TRANSFER_ID:-sword}"
MAX_GATHERS="${MAX_GATHERS:-6}"
COOLDOWN_MAX_BLOCKS="${COOLDOWN_MAX_BLOCKS:-15}"
PAUSE="${PAUSE:-0}"
BOOT_TIMEOUT="${BOOT_TIMEOUT:-180}"

RPC_ADDR="127.0.0.1:26657"
RPC_URL="http://$RPC_ADDR"
WEB="http://127.0.0.1:8888"
CHAIN_ID="dev"
GAS_FEE="1000000ugnot"
GAS_WANTED="50000000"

# gnodev's default deployer / premined account (public test key).
TEST1_MNEMONIC="source bonus chronic canvas draft south burst lottery vacant surface solve popular case indicate oppose farm nothing bullet exhibit title speed wink action roast"
TEST1_ADDR="g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5"

GNODEV_PID=""

die() { printf '\ndemo: error: %s\n' "$*" >&2; exit 1; }
step() {
  printf '\n\033[1m==> %s\033[0m\n' "$*"
  if [ "$PAUSE" != 0 ]; then sleep "$PAUSE"; fi
}

cleanup() {
  if [ -n "$GNODEV_PID" ] && kill -0 "$GNODEV_PID" 2>/dev/null; then
    echo
    echo "stopping gnodev (pid $GNODEV_PID)"
    kill "$GNODEV_PID" 2>/dev/null || true
    for _ in $(seq 1 20); do
      kill -0 "$GNODEV_PID" 2>/dev/null || break
      sleep 0.5
    done
    kill -9 "$GNODEV_PID" 2>/dev/null || true
    wait "$GNODEV_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM

for t in gno gnokey gnodev curl; do
  command -v "$t" >/dev/null || die "$t not found in PATH"
done

# ---------------------------------------------------------------- helpers

height() {
  curl -fs "$RPC_URL/status" 2>/dev/null |
    sed -n -E 's/.*"latest_block_height":[[:space:]]*"([0-9]+)".*/\1/p' | head -n1
}

# wait_blocks N: block until N new blocks have been committed.
wait_blocks() {
  local n="$1" h0 h
  h0="$(height)"
  [ -n "$h0" ] || die "cannot read block height from $RPC_URL/status"
  for _ in $(seq 1 $((n * 10 + 20))); do
    h="$(height)"
    if [ -n "$h" ] && [ "$h" -ge $((h0 + n)) ]; then return 0; fi
    sleep 0.5
  done
  die "chain stalled at height $h0 (gnodev not producing blocks?)"
}

# gk_call <simulate-mode> <key> <pkgpath> <func> [args...]
# Prints gnokey output into $CALL_OUT; returns gnokey's exit code.
CALL_OUT=""
gk_call() {
  local sim="$1" key="$2" pkg="$3" fn="$4"
  shift 4
  local args=()
  for a in "$@"; do args+=(-args "$a"); done
  set +e
  CALL_OUT="$(printf '\n' | gnokey maketx call \
    -pkgpath "$pkg" -func "$fn" ${args[@]+"${args[@]}"} \
    -gas-fee "$GAS_FEE" -gas-wanted "$GAS_WANTED" \
    -chainid "$CHAIN_ID" -remote "$RPC_ADDR" \
    -home "$KEYHOME" -insecure-password-stdin \
    -simulate "$sim" "$key" 2>&1)"
  local rc=$?
  set -e
  return "$rc"
}

show_ok() {
  printf '%s\n' "$CALL_OUT" | grep -v -e '^Enter password' -e '^TX HASH' -e '^INFO:' -e '^[[:space:]]*$' | sed 's/^/    /'
}

show_err() {
  {
    printf '%s\n' "$CALL_OUT" | grep -m 1 '^Data:' || true
    printf '%s\n' "$CALL_OUT" | grep -m 1 -o 'recovered: .*' || true
  } | cut -c1-300 | sed 's/^/    ! /'
}

# tx <label> <pkgpath> <func> [args...]: broadcast as test1, fail loudly.
tx() {
  local label="$1"
  shift
  printf '  $ gnokey maketx call -pkgpath %s -func %s' "$1" "$2"
  local a
  for a in "${@:3}"; do printf ' -args %q' "$a"; done
  printf ' test1\n'
  if gk_call test test1 "$@"; then
    show_ok
  else
    show_err
    die "$label failed"
  fi
}

# probe <func> [args...]: dry-run a forge call as test1 (no broadcast).
probe() { gk_call only test1 "$FORGE" "$@"; }

render() {
  local path="$1"
  printf '  $ curl -H "Accept: text/markdown" %s%s\n\n' "$WEB" "$path"
  curl -fsS -H 'Accept: text/markdown' "$WEB$path" | sed 's/^/    /' ||
    echo "    (page not available)"
  echo
}

# gather: Gather, waiting out the block-height cooldown if needed.
gather() {
  local i
  printf '  $ gnokey maketx call -pkgpath %s -func Gather test1\n' "$FORGE"
  for i in $(seq 1 "$COOLDOWN_MAX_BLOCKS"); do
    if gk_call test test1 "$FORGE" Gather; then
      echo "  Gather OK (attempt $i)"
      show_ok
      return 0
    fi
    if [ "$i" -eq 1 ]; then
      echo "  Gather refused (cooldown?), waiting for blocks..."
      show_err
    fi
    wait_blocks 1
  done
  show_err
  die "Gather still failing after $COOLDOWN_MAX_BLOCKS blocks"
}

# craft <recipe>: craft, gathering (and crafting ingots for higher recipes)
# until the recipe is affordable. Recipe costs are discovered by dry-run.
craft() {
  local recipe="$1" i
  for i in $(seq 0 "$MAX_GATHERS"); do
    if probe Craft "$recipe"; then
      tx "Craft $recipe" "$FORGE" Craft "$recipe"
      return 0
    fi
    if [ "$recipe" != ingot ] && probe Craft ingot; then
      echo "  not enough for $recipe yet; crafting an ingot first"
      tx "Craft ingot" "$FORGE" Craft ingot
      continue
    fi
    if [ "$i" -lt "$MAX_GATHERS" ]; then
      echo "  not enough materials for $recipe; gathering more"
      gather
    fi
  done
  show_err
  die "could not afford '$recipe' after $MAX_GATHERS extra gathers"
}

# ---------------------------------------------------------------- setup

step "Preflight"
for u in "$WEB/" "$RPC_URL/status"; do
  if curl -fs -o /dev/null --max-time 2 "$u"; then
    die "$u is already serving; stop the other gnodev/node first"
  fi
done
echo "  ports 8888 / 26657 free"

step "Throwaway keybase at $KEYHOME (test1 = gnodev premined dev key, bob = recipient)"
mkdir -p "$KEYHOME"
printf '%s\n\n' "$TEST1_MNEMONIC" |
  gnokey add test1 -recover -force -home "$KEYHOME" -insecure-password-stdin >/dev/null 2>&1 ||
  die "could not create test1 key in $KEYHOME"
printf '%s\n\n' "$TEST1_MNEMONIC" |
  gnokey add bob -recover -force -index 1 -home "$KEYHOME" -insecure-password-stdin >/dev/null 2>&1 ||
  die "could not create bob key in $KEYHOME"
addr_of() {
  gnokey list -home "$KEYHOME" | sed -n -E "s/^[0-9]+\. $1 \(local\) - addr: (g1[a-z0-9]+).*/\1/p"
}
A_ADDR="$(addr_of test1)"
B_ADDR="$(addr_of bob)"
[ "$A_ADDR" = "$TEST1_ADDR" ] || die "test1 address mismatch: got '$A_ADDR', want $TEST1_ADDR"
[ -n "$B_ADDR" ] || die "could not read bob's address"
echo "  test1: $A_ADDR"
echo "  bob  : $B_ADDR"

step "Starting gnodev from $ROOT (log: $LOG)"
cd "$ROOT"
# -home: use the throwaway keybase, so gnodev never reads ~/.config/gno.
# -empty-blocks: a block every second, so cooldowns measured in blocks elapse
#   on their own (gnodev otherwise only commits blocks when a tx arrives).
# -no-watch: no hot reload mid-demo.
gnodev local \
  -home "$KEYHOME" \
  -chain-id "$CHAIN_ID" \
  -no-watch \
  -empty-blocks -empty-blocks-interval 1 \
  -node-rpc-listener "$RPC_ADDR" \
  -web-listener "${WEB#http://}" \
  >"$LOG" 2>&1 &
GNODEV_PID=$!
echo "  pid $GNODEV_PID; waiting for gnoweb on $WEB ..."
ready=""
for i in $(seq 1 "$BOOT_TIMEOUT"); do
  kill -0 "$GNODEV_PID" 2>/dev/null || { tail -n 40 "$LOG" >&2; die "gnodev exited during startup"; }
  if curl -fs -o /dev/null --max-time 2 "$WEB/" && [ -n "$(height)" ]; then
    ready=1
    echo "  ready after ${i}s (height $(height))"
    break
  fi
  sleep 1
done
[ -n "$ready" ] || { tail -n 40 "$LOG" >&2; die "gnodev not ready after ${BOOT_TIMEOUT}s"; }

step "Checking test1 is funded on gnodev"
BAL="$(gnokey query "bank/balances/$A_ADDR" -remote "$RPC_ADDR" 2>&1 | sed -n -E 's/^data: "?([^"]*)"?$/\1/p')"
echo "  balance: ${BAL:-<none>}"
case "$BAL" in
  *[1-9]*ugnot*) ;;
  *) die "test1 is not funded on gnodev (balance '${BAL}')" ;;
esac

step "Checking blocks are produced without txs (cooldown handling)"
h1="$(height)"
wait_blocks 2
echo "  height $h1 -> $(height)"

# ---------------------------------------------------------------- smoke test

step "Smoke test: hello.Visit()"
tx "hello.Visit" "$HELLO" Visit
render "/r/$NS/hello"

# ================================================================ FORGE
# Interface (crossing funcs, cur realm first):
#   Gather()  Craft(recipe string: ingot|sword|shield)
#   Transfer(to address, id string, amount int64)
#   BatchTransfer(to address, ids string, amounts string)
# Render paths: ""  and  "inv/<addr>"
# ================================================================
if [ ! -f "$ROOT/forge/v0/gnomod.toml" ]; then
  step "FORGE SECTION SKIPPED: $ROOT/forge/v0 does not exist yet"
  exit 0
fi
if ! curl -fs -o /dev/null -H 'Accept: text/markdown' "$WEB/r/$NS/forge/v0"; then
  tail -n 30 "$LOG" >&2
  die "forge realm $FORGE does not render on gnodev (see $LOG)"
fi

step "Forge home page (before)"
render "/r/$NS/forge/v0"

step "Forge: Gather"
gather

step "Forge: Craft ingot"
craft ingot

step "Forge: Craft sword"
craft sword

step "Forge: Transfer 1 $TRANSFER_ID to bob ($B_ADDR)"
tx "Transfer" "$FORGE" Transfer "$B_ADDR" "$TRANSFER_ID" 1

step "Forge home page (after)"
render "/r/$NS/forge/v0"

step "test1 inventory"
render "/r/$NS/forge/v0:inv/$A_ADDR"

step "bob inventory"
render "/r/$NS/forge/v0:inv/$B_ADDR"

step "Demo complete"
