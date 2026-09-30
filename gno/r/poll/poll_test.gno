package poll

import (
	"strconv"
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
	dave   = testutils.TestAddress("dave")
)

func TestVoteAndMove(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(alice))
	Create(cross(cur), "Best *realm*?", " teams ; donate;poll ")

	testing.SetRealm(testing.NewUserRealm(bob))
	Vote(cross(cur), alice, 1)
	testing.SetRealm(testing.NewUserRealm(carol))
	Vote(cross(cur), alice, 2)
	testing.SetRealm(testing.NewUserRealm(dave))
	Vote(cross(cur), alice, 2)
	Vote(cross(cur), alice, 3)
	uassert.Equal(t, "[1 1 1]", counts(alice), "dave's second vote moves the first")

	page := Render(alice.String())
	uassert.True(t, strings.Contains(page, `## Best \*realm\*?`), page)
	uassert.True(t, strings.Contains(page, "**2. donate** · 1 vote"), page)
	uassert.True(t, strings.Contains(page, "\n▰▰▰▱▱▱▱▱▱▱ 33%\n"), page)
	uassert.True(t, strings.Contains(page, "3 votes in all"), page)
	uassert.True(t, strings.Contains(page, "func=Vote&choice=3&owner="+alice.String()), page)
}

func TestCloseAndReplace(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(carol))
	Create(cross(cur), "Tea or coffee?", "tea;coffee")
	Close(cross(cur))
	uassert.False(t, strings.Contains(Render(carol.String()), "func=Vote"), "a closed poll has no vote links")

	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "closed", func() { Vote(cross(cur), carol, 1) })

	testing.SetRealm(testing.NewUserRealm(carol))
	Create(cross(cur), "Cats or dogs?", "cats;dogs")
	testing.SetRealm(testing.NewUserRealm(bob))
	Vote(cross(cur), carol, 2)
	uassert.Equal(t, "[0 1]", counts(carol), "a new poll starts from no votes")
}

func TestRefusals(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "no poll", func() { Vote(cross(cur), dave, 1) })
	uassert.AbortsContains(t, cur, "no poll", func() { Close(cross(cur)) })
	uassert.AbortsContains(t, cur, "no such choice", func() { Vote(cross(cur), alice, 0) })
	uassert.AbortsContains(t, cur, "no such choice", func() { Vote(cross(cur), alice, 4) })
	uassert.AbortsContains(t, cur, "between 2 and 10", func() { Create(cross(cur), "Only one?", "yes") })
	uassert.AbortsContains(t, cur, "between 2 and 10", func() { Create(cross(cur), "Too many?", strings.Repeat("x;", 10)+"x") })
	uassert.AbortsContains(t, cur, "choice 2 is empty", func() { Create(cross(cur), "Blank?", "yes;;no") })
	uassert.AbortsContains(t, cur, "choice 3 is empty", func() { Create(cross(cur), "Trailing?", "tea;coffee;") })
	uassert.AbortsContains(t, cur, "longer than 280", func() { Create(cross(cur), strings.Repeat("?", 281), "a;b") })
	uassert.AbortsContains(t, cur, "longer than 80", func() { Create(cross(cur), "Long?", "a;"+strings.Repeat("b", 81)) })
	uassert.AbortsContains(t, cur, "empty", func() { Create(cross(cur), "\u200b", "a;b") })
}

func TestPages(cur realm, t *testing.T) {
	uassert.True(t, strings.Contains(Render(""), "func=Create"))
	uassert.True(t, strings.Contains(Render(nobody.String()), "no poll yet"))
}

// counts returns the votes of owner's poll per choice, as "[1 0 2]".
func counts(owner address) string {
	s := make([]string, 0, len(mustPoll(owner).counts))
	for _, n := range mustPoll(owner).counts {
		s = append(s, strconv.Itoa(n))
	}
	return "[" + strings.Join(s, " ") + "]"
}
