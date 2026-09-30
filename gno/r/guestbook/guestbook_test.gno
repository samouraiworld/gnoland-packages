package guestbook

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
)

func TestSignAndReplace(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(alice))
	Open(cross(cur))

	testing.SetRealm(testing.NewUserRealm(bob))
	Sign(cross(cur), alice, "first **try**")
	testing.SetRealm(testing.NewUserRealm(carol))
	Sign(cross(cur), alice, "hello from carol")
	testing.SetRealm(testing.NewUserRealm(bob))
	Sign(cross(cur), alice, "  second   try ")

	page := Render(alice.String())
	uassert.True(t, strings.Contains(page, "## Messages (2)"), page)
	uassert.False(t, strings.Contains(page, "first"), "the second signature replaces the first")
	second, third := strings.Index(page, "second try"), strings.Index(page, "hello from carol")
	uassert.True(t, second >= 0 && second < third, "the newest message comes first")
}

func TestOwnerRemoves(cur realm, t *testing.T) {
	// carol's own guestbook has no message from bob.
	testing.SetRealm(testing.NewUserRealm(carol))
	Open(cross(cur))
	uassert.AbortsContains(t, cur, "no message", func() { Remove(cross(cur), bob) })
	uassert.True(t, mustBook(alice).bySigner.Has(bob.String()))

	testing.SetRealm(testing.NewUserRealm(alice))
	Remove(cross(cur), bob)
	uassert.False(t, mustBook(alice).bySigner.Has(bob.String()))
	uassert.True(t, mustBook(alice).bySigner.Has(carol.String()))
	uassert.AbortsContains(t, cur, "no message", func() { Remove(cross(cur), bob) })
}

func TestSignRefusals(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "no guestbook", func() { Sign(cross(cur), nobody, "hi") })
	uassert.AbortsContains(t, cur, "empty", func() { Sign(cross(cur), alice, "   ") })
	uassert.AbortsContains(t, cur, "longer than 280", func() { Sign(cross(cur), alice, strings.Repeat("x", 281)) })

	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "already open", func() { Open(cross(cur)) })
}

func TestMarkupIsEscaped(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(bob))
	Sign(cross(cur), alice, "[click](https://evil.example) <gno-form>")
	page := Render(alice.String())
	uassert.False(t, strings.Contains(page, "[click](https"), page)
	uassert.False(t, strings.Contains(page, "<gno-form>"), page)
}

func TestPaging(cur realm, t *testing.T) {
	owner := testutils.TestAddress("owner")
	testing.SetRealm(testing.NewUserRealm(owner))
	Open(cross(cur))
	for i := 0; i < 11; i++ {
		testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("signer" + strconv.Itoa(i))))
		Sign(cross(cur), owner, "message "+strconv.Itoa(i))
	}
	first, second := Render(owner.String()), Render(owner.String()+"?page=2")
	uassert.True(t, strings.Contains(first, "message 10") && !strings.Contains(first, "message 0 "), first)
	uassert.True(t, strings.Contains(second, "message 0 ") && !strings.Contains(second, "message 10"), second)
	uassert.True(t, strings.Contains(first, "func=Remove&signer="+testutils.TestAddress("signer3").String()), first)
}

func TestPages(cur realm, t *testing.T) {
	uassert.True(t, strings.Contains(Render(""), "func=Open"))
	uassert.True(t, strings.Contains(Render(nobody.String()), "no guestbook yet"))
}
