package ama

import (
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

func TestAskAndAnswer(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(alice))
	Open(cross(cur))

	testing.SetRealm(testing.NewUserRealm(bob))
	id := Ask(cross(cur), alice, "What is *your* favourite realm?")
	uassert.True(t, strings.Contains(Render(alice.String()+"/waiting"), `What is \*your\* favourite realm?`))
	uassert.True(t, strings.Contains(Render(alice.String()), "No answer yet"))

	testing.SetRealm(testing.NewUserRealm(alice))
	Answer(cross(cur), id, "r/samcrew/teams")
	page := Render(alice.String())
	uassert.True(t, strings.Contains(page, "## Answered (1)"), page)
	uassert.True(t, strings.Contains(page, "r/samcrew/teams"), page)
	uassert.True(t, strings.Contains(Render(alice.String()+"/waiting"), "Nothing waiting"))

	Answer(cross(cur), id, "r/samcrew/donate")
	uassert.True(t, strings.Contains(Render(alice.String()), "r/samcrew/donate"), "a second answer replaces the first")
	uassert.AbortsContains(t, cur, "longer than 1000", func() { Answer(cross(cur), id, strings.Repeat("a", 1001)) })
	uassert.AbortsContains(t, cur, "already open", func() { Open(cross(cur)) })

	Dismiss(cross(cur), id)
	uassert.True(t, strings.Contains(Render(alice.String()), "## Answered (0)"), "an answered question can be dismissed")
}

func TestOneWaitingQuestionEach(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(carol))
	id := Ask(cross(cur), alice, "first")
	uassert.AbortsContains(t, cur, "still waiting", func() { Ask(cross(cur), alice, "second") })

	testing.SetRealm(testing.NewUserRealm(alice))
	Dismiss(cross(cur), id)
	uassert.False(t, strings.Contains(Render(alice.String()+"/waiting"), "first"))

	testing.SetRealm(testing.NewUserRealm(carol))
	Ask(cross(cur), alice, "second")
}

func TestOnlyOwnerAnswers(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(bob))
	id := Ask(cross(cur), alice, "can bob answer this?")
	// bob's own page has no question with alice's number.
	Open(cross(cur))
	uassert.AbortsContains(t, cur, "no such question", func() { Answer(cross(cur), id, "yes") })
	uassert.AbortsContains(t, cur, "no such question", func() { Dismiss(cross(cur), id) })
	uassert.True(t, strings.Contains(Render(alice.String()+"/waiting"), "can bob answer this?"))

	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "no such question", func() { Answer(cross(cur), 999, "yes") })
	uassert.AbortsContains(t, cur, "empty", func() { Answer(cross(cur), id, "  ") })
}

func TestAskRefusals(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "no ask-me-anything page", func() { Ask(cross(cur), nobody, "hi") })
	uassert.AbortsContains(t, cur, "longer than 280", func() { Ask(cross(cur), alice, strings.Repeat("?", 281)) })
}

func TestPages(cur realm, t *testing.T) {
	uassert.True(t, strings.Contains(Render(""), "func=Open"))
	uassert.True(t, strings.Contains(Render(nobody.String()), "no page yet"))
	uassert.True(t, strings.Contains(Render(nobody.String()+"/waiting"), "no page yet"))
}
