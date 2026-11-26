# Tavern Forge

A GRC1155-compatible multi-token package for Gno.land, and a small crafting realm that runs on it.

> GRC1155 is the only common token standard without a usable package on Gno mainnet: the canonical `p/nt/grc1155` sits in `examples/quarantined`, and `p/nt` paths cannot be added after genesis without a hardfork. This project ships a replacement under its own namespace, `grc1155/v0`, built on the GRC721 v0 Teller/PrivateLedger capability model. It also ships **Tavern Forge** (`forge/v0`, symbol `FORGE`), a realm where players gather materials, craft items, and trade them, so the package is exercised on testnet.

- **Track / goal:** Gnome Tavern hackathon (DoraHacks, Gno.land). Live on Gno.land testnet Onyx (`onyx-1`).
- **Library:** `gno.land/p/g1j9c3manpp89kdyhjjqqyugty70kjy5w4sw9y0m/grc1155/v0`: multi-token ledger, capability tellers, real events, per-token URI and supply, paged enumeration.
- **Demo realm:** `gno.land/r/g1j9c3manpp89kdyhjjqqyugty70kjy5w4sw9y0m/forge/v0`: Gather, Craft, Transfer, leaderboard, inventory pages.
- **Live:** [grc1155/v0 on gnoweb](https://latest.testnets.gno.land/p/g1j9c3manpp89kdyhjjqqyugty70kjy5w4sw9y0m/grc1155/v0) — `live` on Onyx, addpkg height 1,402,513 · [forge/v0 on gnoweb](https://latest.testnets.gno.land/r/g1j9c3manpp89kdyhjjqqyugty70kjy5w4sw9y0m/forge/v0) — `live` on Onyx, addpkg height 1,408,069
- **Docs:** [library README](./grc1155/v0/README.md) · [upstream issue #6202](https://github.com/gnolang/gno/issues/6202)
- **Demo video:** <!-- TODO-VERIFY: demo video link -->

---

## Why This Matters

Facts below come from [gnolang/gno#6202](https://github.com/gnolang/gno/issues/6202) and the [quarantined source](https://github.com/gnolang/gno/tree/master/examples/quarantined/gno.land/p/nt/grc1155/v0).

- **GRC1155 is the only token standard not available on Gno mainnet.** Its canonical package, `gno.land/p/nt/grc1155/v0`, sits in `examples/quarantined/`.
- **The quarantined package has five gaps** ([#6202](https://github.com/gnolang/gno/issues/6202)):
  1. Events are constructed and then dropped, so indexers see no transfers.
  2. The "safe" transfer acceptance checks are `return true` stubs.
  3. It authorizes with `unsafe.OriginCaller()`, so any realm a user calls can move that user's tokens. You can see this in [`basic_grc1155_token.gno`](https://github.com/gnolang/gno/tree/master/examples/quarantined/gno.land/p/nt/grc1155/v0).
  4. The implementation type is unexported, so other packages cannot extend it.
  5. It has a single global URI and no per-token supply or enumeration.
- **It cannot be fixed in place.** `p/nt` paths cannot be added after genesis without a hardfork ([#6202](https://github.com/gnolang/gno/issues/6202)). A working GRC1155 has to live under a user namespace.

Games, collectibles, tickets, and in-game resources all need many fungible and non-fungible ids under one contract. This package gives Gno realms that, using the same security model as `gno.land/p/nt/grc721/v0`.

---

## How It Works

```
  Player
    │  (browser / wallet / CLI)
    ▼
┌──────────────────────────────┐
│ gnoweb  ·  Adena  ·  gnokey  │  read: Render pages      write: signed MsgCall
└──────────────┬───────────────┘
               │ Gather / Craft / Transfer / BatchTransfer
               ▼
┌──────────────────────────────────────────────────────────┐
│ r/.../forge/v0   (Tavern Forge, symbol FORGE)            │
│  - user-call-only Gather, 10-block cooldown              │
│  - recipes: ingot, sword, shield                         │
│  - leaderboard (renown)                                  │
│  - holds *PrivateLedger (never exported)                 │
└──────────────┬───────────────────────────────────────────┘
               │ ledger.Mint / Burn (recipes)
               │ CallerTeller.TransferFrom / BatchTransferFrom (loot)
               ▼
┌──────────────────────────────────────────────────────────┐
│ p/.../grc1155/v0                                         │
│  Token (public reads) ── PrivateLedger (issuer writes)   │
│  Tellers: Caller (home-guarded) · Realm · RealmSub ·     │
│           Readonly · Impersonate · IsCanonicalTeller     │
│  avl.Tree: balances · supplies · uris · approvals        │
└──────────────┬──────────────────────────────┬────────────┘
               │ chain.Emit                   │ reads
               ▼                              ▼
   NewToken · TransferSingle ·       Render: home, :item/<id>,
   TransferBatch · ApprovalForAll ·  :inv/<address>, leaderboard
   URI  (indexers / tx results)      (back to gnoweb)
```

1. A player opens the forge's gnoweb page and triggers an action. gnoweb shows the call form and the matching `gnokey` command, and Adena can sign the same call.
2. The forge realm checks the rule (cooldown, recipe inputs) and changes balances through its `*PrivateLedger`: it mints materials, then burns inputs and mints outputs when crafting.
3. Player-to-player transfers go through `ledger.CallerTeller()`. The teller resolves the acting account as `cur.Previous()` and refuses to run outside the forge realm (`ErrForeignCallerTeller`).
4. Every state change emits a `chain.Emit` event. `Render` reads the `Token` view to draw the item, inventory, and leaderboard pages.

---

## Architecture & Capability Mapping Table

| Capability / module | Where | What it powers |
|---|---|---|
| `NewToken(name, symbol, defaultURI, 0, cur)` | `grc1155/v0/token.gno` | Creates the forge's `Token` + `PrivateLedger`. Records the creating realm's path as the unforgeable home realm and emits `NewToken`. |
| `PrivateLedger.Mint` / `MintBatch` / `Burn` / `BurnBatch` | `grc1155/v0/token.gno` | Gather (mint wood + ore) and Craft (burn inputs, mint output). Batch ops are validated all-or-nothing, including duplicate ids, and arithmetic is overflow-checked. |
| `PrivateLedger.CallerTeller()` (home-guarded) | `grc1155/v0/tellers.gno` | Forge `Transfer` / `BatchTransfer`: the player moves their own loot. If the teller leaks it is inert outside the forge realm. |
| `Token.RealmTeller` / `RealmSubTeller` | `grc1155/v0/tellers.gno` | Lets another realm hold and move tokens as itself, or as a slug-derived sub-account, after the owner approves it with `SetApprovalForAll`. |
| `Token.ReadonlyTeller` | `grc1155/v0/tellers.gno` | Read-only handle that can be shared. Every write returns `ErrReadonly`. |
| `PrivateLedger.ImpersonateTeller(addr)` | `grc1155/v0/tellers.gno` | Admin-grade teller, available only to the ledger holder. Not used by the forge. |
| `IsCanonicalTeller(t)` | `grc1155/v0/types.gno` | Rejects tellers forged by embedding. It checks that the teller is authentic, not which account it acts for. |
| `BalanceOf`, `BalanceOfBatch`, `IsApprovedForAll`, `TotalSupply`, `Exists` | `grc1155/v0/token.gno` | Inventory pages, item pages, and recipe input checks. |
| `HoldingsOf(owner, offset, limit)`, `HoldingsAfter(owner, after, limit)`, `TokenIDs(offset, limit)` | `grc1155/v0/token.gno` | Paged enumeration (page size capped at 50) for `:inv/<address>` and the item list. |
| `URI(tid)`, `SetURI`, `SetDefaultURI` | `grc1155/v0/token.gno` | Per-token URI override, falling back to a `{id}` template. The forge points it at its own `:item/{id}` pages. |
| `chain.Emit` events (`NewToken`, `TransferSingle`, `TransferBatch`, `ApprovalForAll`, `URI`, with `operator` attribute) | `grc1155/v0/token.gno` | Indexer-visible history of mints, burns, transfers, approvals, and URI changes. |
| `Extension` hooks (`RegisterExtension`) | `grc1155/v0/types.gno`, `token.gno` | Issuer-only `OnMint` / `OnTransfer` / `OnBurn` hooks that let a realm extend behavior without forking the package. |
| `TokenID` charset `[A-Za-z0-9_.-]`, max 64 chars | `grc1155/v0/types.gno`, `token.gno` | Ids are always safe to render in markdown and to embed in storage keys. |
| Forge `Gather` | `forge/v0` | 2 wood + 1 ore per call, 10-block cooldown, direct user calls only. |
| Forge `Craft` | `forge/v0` | ingot = 2 ore. sword = 1 ingot + 2 wood. shield = 1 ingot + 3 wood. |
| Forge leaderboard | `forge/v0` | Renown: ingot 1, sword 3, shield 3. |
| Forge `Render` | `forge/v0` | Home page with clickable actions, `:item/<id>` pages, and `:inv/<address>` inventory showing items by display name. |

The forge's crossing functions all take `cur realm` first: `Gather(cur)`, `Craft(cur, recipe string)`, `Transfer(cur, to address, id string, amount int64)`, `BatchTransfer(cur, to address, ids string, amounts string)` (comma-separated), and `SetApprovalForAll(cur, operator address, approved bool)`. Gather and Craft accept direct user calls only.

---

## Try It in 5 Minutes (Quickstart / Judge Walkthrough)

### On testnet (Onyx, `onyx-1`)

1. **Open the forge:** <https://latest.testnets.gno.land/r/g1j9c3manpp89kdyhjjqqyugty70kjy5w4sw9y0m/forge/v0>. The home page lists the actions, the recipes, and the leaderboard.
2. **Get test tokens:** go to <https://faucet.gno.land>, choose **Onyx**, and fund your address. You can use an Adena wallet set to Onyx, or a local key (`gnokey add mykey`).
3. **Gather:** click the Gather action on the home page and sign with Adena, or run the generated command. Onyx's minimum gas price is 1ugnot per 1000 gas, so `-gas-wanted 20000000` pairs with `-gas-fee 25000ugnot`:
   ```sh
   gnokey maketx call \
     -pkgpath gno.land/r/g1j9c3manpp89kdyhjjqqyugty70kjy5w4sw9y0m/forge/v0 \
     -func Gather \
     -gas-fee 25000ugnot -gas-wanted 20000000 \
     -chainid onyx-1 -remote https://rpc.onyx.testnets.gno.land:443 \
     -broadcast mykey
   ```
   Each call gives 2 Oak Wood + 1 Iron Ore and works once every 10 blocks.
4. **Craft:** gather twice (4 wood, 2 ore), then craft an `ingot` (2 ore), then a `sword` (1 ingot + 2 wood). Each craft burns the inputs and mints the output in a single transaction:
   ```sh
   gnokey maketx call -pkgpath gno.land/r/g1j9c3manpp89kdyhjjqqyugty70kjy5w4sw9y0m/forge/v0 \
     -func Craft -args ingot \
     -gas-fee 25000ugnot -gas-wanted 20000000 \
     -chainid onyx-1 -remote https://rpc.onyx.testnets.gno.land:443 -broadcast mykey
   # then the same with: -func Craft -args sword
   ```
   `shield` (1 ingot + 3 wood) works the same way.
5. **View inventory:** open `https://latest.testnets.gno.land/r/g1j9c3manpp89kdyhjjqqyugty70kjy5w4sw9y0m/forge/v0:inv/<your-address>`. Items are listed by display name and link to their `:item/<id>` pages.
6. **Transfer:** send loot to another address — one stack with `Transfer`, several with `BatchTransfer` (comma-separated `ids` and `amounts`):
   ```sh
   gnokey maketx call -pkgpath gno.land/r/g1j9c3manpp89kdyhjjqqyugty70kjy5w4sw9y0m/forge/v0 \
     -func Transfer -args <their-address> -args sword -args 1 \
     -gas-fee 25000ugnot -gas-wanted 20000000 \
     -chainid onyx-1 -remote https://rpc.onyx.testnets.gno.land:443 -broadcast mykey
   # BatchTransfer example: -func BatchTransfer -args <their-address> -args wood,ore -args 2,1
   ```
   `SetApprovalForAll` (`-args <operator-address> -args true`) lets an operator move your items. The leaderboard updates from crafted renown.

### Locally (no testnet needed)

1. Install the toolchain from gno master (see [Local Development & Verification](#local-development--verification)).
2. `make dev` starts `gnodev local` with both packages loaded. gnoweb is at <http://127.0.0.1:8888/r/g1j9c3manpp89kdyhjjqqyugty70kjy5w4sw9y0m/forge/v0>.
3. `make demo` runs `scripts/demo-local.sh`, which scripts the full Gather → Craft → Transfer loop against the local gnodev node.

---

## Safety, Privacy & Guardrails

1. **No `Safe*` functions.** EIP-1155's receiver-acceptance check (`onERC1155Received`) needs a registry of receiver contracts. A `SafeTransferFrom` alias without one would claim safety that does not exist, which is the quarantined package's gap 2. Callers get plain `TransferFrom` / `BatchTransferFrom`.
2. **No origin-based authorization.** The package never reads `unsafe.OriginCaller()` or `unsafe.PreviousRealm()`. `CallerTeller` resolves the actor per frame from the `realm` value it is passed (`rlm.Previous()`), and every write checks `rlm.IsCurrent()` (`ErrSpoofedRealm`).
3. **Home-guarded tellers.** `CallerTeller` is only reachable from `*PrivateLedger`, which `NewToken` hands only to the creating realm. Its writes also check that the invoking realm is the token's home realm (`guardHome`). A teller value that leaks to another realm returns `ErrForeignCallerTeller`. Foreign realms move tokens only through owner approval plus their own `RealmTeller`.
4. **User-call-only Gather.** Gather accepts direct user calls only, so a realm cannot farm materials in a loop on a user's behalf. The 10-block cooldown limits issuance per address.
5. **No free-form user text is rendered.** Render pages show token ids (charset `[A-Za-z0-9_.-]`, enforced by the package), fixed display names, numbers, and addresses. Players never supply names, descriptions, or messages that reach markdown.
6. **No coins or payments in the forge.** The forge does not use the banker, does not read `OriginSend`, and holds no `ugnot`. Gas is the only cost.
7. **All-or-nothing batches.** Batches are validated before any write: length match, non-empty, at most 64 entries, no duplicate ids, positive amounts, and overflow-checked totals. A failing batch changes nothing and fires no hooks or events.
8. **Extension hooks are an issuer trust grant.** Only the ledger holder can attach a hook. An attached hook can veto movements by panicking, and it adds gas to every movement. The forge attaches none.
9. **Testnet only.** Deployed to Onyx (`onyx-1`) for the hackathon. The tokens have no monetary value and the code has not been audited for mainnet.

---

## Engineering Highlights (Verified)

Measured on the `grc1155/v0` package with `gno version: master.1+70e39c2`:

- **Tests:** `gno test -v ./...` in `grc1155/v0` passes everything: **35 top-level unit tests** (25 in `token_test.gno`, 10 in `tellers_test.gno`), **149 subtests**, and **6 filetests**. `forge/v0` adds **6 top-level tests** with no subtests or filetests. 0 failures, about 2.5 s per package.
- **Attack filetests:** four of the six filetests are adversarial. They run cross-realm against the `grc1155testhome` scaffold realm:
  - `attack_forged_teller` (embedding forgery vs `IsCanonicalTeller`)
  - `attack_leaked_teller` (exported `CallerTeller` used from a foreign realm → `ErrForeignCallerTeller`)
  - `attack_spoofed_realm` (stale or foreign `realm` value → `ErrSpoofedRealm`)
  - `attack_token_surface` (what a foreign realm can do with the public `*Token`)

  The other two are `batch_atomicity` and `events`.
- **Import footprint (deployed files):** the library has one `/p/` dependency, `gno.land/p/nt/avl/v0`, plus stdlibs `chain`, `errors`, `math/overflow`, `strconv`, `strings`. The forge adds only `grc1155/v0` itself, so the transitive `/p/` closure of both packages is exactly those two. Test-only imports are `p/nt/testutils/v0`, `p/nt/uassert/v0`, `p/nt/urequire/v0`, and `testing`.
- **Size:** 1,141 lines of deployed library Gno (`token.gno` 776, `tellers.gno` 205, `types.gno` 160), 1,951 lines of library tests, and 855 lines of forge code (`forge.gno` 341, `render.gno` 190, `forge_test.gno` 324).
- **Bounds:** `MaxBatchSize` 64, `MaxTokenIDLen` 64, `MaxURILen` 256, `MaxNameLen` 64, `MaxSymbolLen` 11, and enumeration page size 50.
- **Gameplay gas** (measured on local gnodev, `GAS USED` from `gnokey maketx call`): Gather 8.70M–9.82M, Craft ingot 10.97M, Craft sword 12.34M, Transfer 8.64M, BatchTransfer 8.85M. The quickstart's `-gas-wanted 20000000` covers the largest with ~60% headroom.
- **Deployment:** `grc1155/v0` is `live` on Onyx — addpkg at height 1,402,513, tx `rub+pZWMnmS0w+i1ZmvA/uoAmnI8kxOBHFIw2J+6LCw=`, gas used 147,439,491, approved by the testnet approver about an hour after submission. `forge/v0` was submitted at height 1,408,069 (tx `xp3IcT1yvnm/+Xlu86IaMh98vRQit+TWMCmJ21FIzc8=`, gas used 37,861,420) and went `live` about an hour after submission. A `hello` realm in this namespace has reported `live` since height 1,397,552.

---

## Repository Structure

```
gnome-tavern/
├── README.md
├── Makefile                      # fmt / fmt-check / lint / test / dev / demo / deploy-* / status
├── gnowork.toml                  # gno workspace root
├── .gitignore
├── grc1155/v0/                   # p/.../grc1155/v0 — the library (live on Onyx)
│   ├── README.md
│   ├── gnomod.toml
│   ├── types.gno                 # Teller, Extension, Token, PrivateLedger, errors, limits
│   ├── token.gno                 # NewToken, reads, Mint/Burn/Transfer, URI, events
│   ├── tellers.gno               # Caller/Readonly/Realm/RealmSub/Impersonate tellers, guardHome
│   ├── token_test.gno
│   ├── tellers_test.gno
│   └── filetests/
│       ├── attack_forged_teller_filetest.gno
│       ├── attack_leaked_teller_filetest.gno
│       ├── attack_spoofed_realm_filetest.gno
│       ├── attack_token_surface_filetest.gno
│       ├── batch_atomicity_filetest.gno
│       └── events_filetest.gno
├── grc1155testhome/              # test-only "home" realm for the attack filetests (never deployed)
│   ├── gnomod.toml
│   └── grc1155testhome.gno
├── forge/v0/                     # r/.../forge/v0 — Tavern Forge demo realm
│   ├── gnomod.toml
│   ├── forge.gno                 # Gather, Craft, Transfer, BatchTransfer, SetApprovalForAll, renown
│   ├── render.gno                # home, item/<id>, inv/<address> pages
│   └── forge_test.gno
├── hello/                        # namespace deployment smoke test (live on Onyx)
│   ├── gnomod.toml
│   ├── hello.gno
│   └── hello_test.gno
├── scripts/
│   ├── deploy.sh                 # deploy one package dir to Onyx
│   ├── status.sh                 # print live | inert | absent for hello, grc1155, forge
│   └── demo-local.sh             # scripted Gather → Craft → Transfer demo on local gnodev
└── poll_pkg.sh                   # polls vm/qpkgmeta_json until a package leaves "inert"
```

---

## Local Development & Verification

Install the toolchain (`gno`, `gnokey`, `gnodev`) from gno master:

```sh
git clone https://github.com/gnolang/gno.git
cd gno && make install
```

From the repository root:

```sh
make fmt      # gno fmt over all packages
make lint     # gno lint
make test     # gno test over grc1155/v0, forge/v0 and hello
make dev      # gnodev local → gnoweb at http://127.0.0.1:8888
make demo     # scripts/demo-local.sh: scripted Gather → Craft → Transfer on local gnodev
```

Run the library tests directly:

```sh
cd grc1155/v0 && gno test -v ./...
```

Deploy to Onyx. Fund the key first at <https://faucet.gno.land> (choose Onyx). `KEY` is a key name in your local `gnokey` keybase.

```sh
make deploy-lib   KEY=mykey   # scripts/deploy.sh → gno.land/p/g1j9c3…/grc1155/v0
make deploy-forge KEY=mykey   # scripts/deploy.sh → gno.land/r/g1j9c3…/forge/v0 (after the lib is live)
make status                   # scripts/status.sh → package status on Onyx (inert / live)
```

New packages on Onyx stay `inert` until they are approved. `make status`, or `./poll_pkg.sh <pkgpath>`, reports when a package goes `live`.

---

## Disclaimer / Attribution

- This project is not affiliated with or endorsed by Gno.land or NewTendermint. It is a hackathon entry.
- The capability model (Teller, PrivateLedger, CallerTeller with home-realm guard, RealmTeller, IsCanonicalTeller) is adapted from `gno.land/p/nt/grc721/v0` in [gnolang/gno](https://github.com/gnolang/gno). The method names follow EIP-1155. The gap analysis comes from [gnolang/gno#6202](https://github.com/gnolang/gno/issues/6202).
- gnolang/gno is distributed under the **GNO Network General Public License** (a fork of the GNU AGPL v3; see [LICENSE.md](https://github.com/gnolang/gno/blob/master/LICENSE.md)). Work derived from it is subject to those terms.
- Testnet deployment only. No warranty.
