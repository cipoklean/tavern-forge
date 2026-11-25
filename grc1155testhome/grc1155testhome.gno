// Package grc1155testhome is test scaffolding for the grc1155 attack
// filetests — never deployed. It plays the "home" realm that owns a token
// while each filetest's own PKGPATH realm plays the attacker: only a real
// cross-realm call can produce a cur whose PkgPath differs from the token's
// origRealm, which is the only way ErrForeignCallerTeller is reachable.
package grc1155testhome

import (
	"gno.land/p/g1j9c3manpp89kdyhjjqqyugty70kjy5w4sw9y0m/grc1155/v0"
)

var (
	token  *grc1155.Token
	ledger *grc1155.PrivateLedger
)

func init(cur realm) {
	token, ledger = grc1155.NewToken("Test Home", "HOME", "item/{id}", 0, cur)
}

func Mint(_ realm, to address, tid grc1155.TokenID, amount int64) error {
	return ledger.Mint(to, tid, amount)
}

// Token publishes the exported read surface — all a foreign realm can ever
// legitimately obtain.
func Token(_ realm) *grc1155.Token { return token }

// CallerTeller hands out the frame-relative teller; guardHome is what keeps
// it inert once it travels.
func CallerTeller(_ realm) grc1155.Teller { return ledger.CallerTeller() }

func BalanceOf(_ realm, owner address, tid grc1155.TokenID) int64 {
	balance, _ := token.BalanceOf(owner, tid)
	return balance
}
