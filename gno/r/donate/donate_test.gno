package donate

import (
	"chain"
	"chain/banker"
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

var (
	alice = testutils.TestAddress("alice")
	bob   = testutils.TestAddress("bob")
	carol = testutils.TestAddress("carol")
	// nobody never opens a page.
	nobody = testutils.TestAddress("nobody")
)

var self = chain.PackageAddress("gno.land/r/samcrew/donate")

// send makes the next call carry coins. The caller is set in the test itself:
// SetRealm in a helper reaches only the helper's frame.
func send(coins chain.Coins) {
	testing.IssueCoins(self, coins)
	testing.SetOriginSend(coins)
}

func TestDonateReachesOwner(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(alice))
	Open(cross(cur))

	bank := banker.NewReadonlyBanker()
	before := bank.GetCoin(alice, "ugnot")
	send(chain.Coins{chain.NewCoin("ugnot", 1_500_000)})
	testing.SetRealm(testing.NewUserRealm(bob))
	id := Donate(cross(cur), alice, "  keep   *going* ")

	uassert.Equal(t, uint64(1), id)
	uassert.Equal(t, before+1_500_000, bank.GetCoin(alice, "ugnot"))
	uassert.Equal(t, int64(0), bank.GetCoin(self, "ugnot"))
	uassert.Equal(t, "1500000ugnot", mustPage(alice).total.String())

	page := Render(alice.String())
	uassert.True(t, strings.Contains(page, "**1.5 GNOT** received from **1** donation."), page)
	uassert.True(t, strings.Contains(page, "- **"+name(bob)+"** gave **1.5 GNOT**"), page)
	uassert.True(t, strings.Contains(page, `keep \*going\*`), "the note is escaped and trimmed")
	uassert.True(t, strings.Contains(page, "func=Donate&.send=1000000ugnot&owner="+alice.String()), page)
}

func TestOwnerRemovesNote(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(carol))
	Open(cross(cur))
	send(chain.Coins{chain.NewCoin("ugnot", 2_000_000)})
	testing.SetRealm(testing.NewUserRealm(bob))
	id := Donate(cross(cur), carol, "spam link")

	// bob's own page has no donation with carol's number.
	Open(cross(cur))
	uassert.AbortsContains(t, cur, "no such donation", func() { RemoveNote(cross(cur), id) })
	uassert.True(t, strings.Contains(Render(carol.String()), "spam link"))

	testing.SetRealm(testing.NewUserRealm(carol))
	RemoveNote(cross(cur), id)
	page := Render(carol.String())
	uassert.False(t, strings.Contains(page, "spam link"), page)
	uassert.True(t, strings.Contains(page, "**2 GNOT**"), "the amount stays")
}

func TestDonateRefusals(cur realm, t *testing.T) {
	stranger := testutils.TestAddress("stranger")
	gnot := chain.Coins{chain.NewCoin("ugnot", 1)}

	send(gnot)
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "no donate page", func() { Donate(cross(cur), stranger, "") })
	uassert.AbortsContains(t, cur, "longer than 280", func() { Donate(cross(cur), alice, strings.Repeat("é", 281)) })
	// A realm in between could hand over coins it holds for someone else.
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/evil/proxy"))
	uassert.AbortsContains(t, cur, "direct call", func() { Donate(cross(cur), alice, "") })

	send(nil)
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "no other coin", func() { Donate(cross(cur), alice, "") })

	junk := chain.Coins{chain.NewCoin("/gno.land/r/evil/x:spam", 1)}
	send(junk)
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "no other coin", func() { Donate(cross(cur), alice, "") })
	send(append(junk, gnot...))
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "no other coin", func() { Donate(cross(cur), alice, "") })

	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "already open", func() { Open(cross(cur)) })
}

func TestPages(cur realm, t *testing.T) {
	uassert.True(t, strings.Contains(Render(""), "func=Open"))
	uassert.True(t, strings.Contains(Render(nobody.String()), "no donate page yet"))
}
