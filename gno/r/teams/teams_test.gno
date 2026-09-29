package teams

import (
	"chain"
	"strconv"
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
)

var (
	alice = testutils.TestAddress("alice")
	bob   = testutils.TestAddress("bob")
)

// The realm passes each caller through as the one acting, so the registry's
// owner checks hold for calls that arrive here.
func TestCallerIsWhoCalls(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(alice))
	id := CreateTeam(cross(cur), "Wired", "", false)
	uassert.Equal(t, alice, Owner(id))
	Invite(cross(cur), id, bob)

	urequire.AbortsWithMessage(t, cur, "only the team owner can do this", func(cur realm) {
		testing.SetRealm(testing.NewUserRealm(bob))
		SetOpen(cross(cur), id, true)
	})

	testing.SetRealm(testing.NewUserRealm(bob))
	Join(cross(cur), id)
	uassert.True(t, IsMember(id, bob))
	uassert.True(t, len(TeamsOf(bob)) > 0)
	Leave(cross(cur), id)
	uassert.False(t, IsMember(id, bob))
}

// A game realm calling in acts as itself, never as the user who called it.
func TestRealmCallerActsAsItself(cur realm, t *testing.T) {
	game := testing.NewCodeRealm("gno.land/r/samcrew/somegame")
	testing.SetRealm(game)
	id := CreateTeam(cross(cur), "Game Owned", "", true)
	uassert.Equal(t, chain.PackageAddress("gno.land/r/samcrew/somegame"), Owner(id))
}

func TestRenderLinksHere(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(alice))
	id := CreateTeam(cross(cur), "Linked", "", true)
	ids := strconv.FormatUint(id, 10)

	// gnoweb renders as the realm itself, and the links take its path.
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/samcrew/teams"))
	page := Render("team/" + ids)
	uassert.True(t, strings.Contains(page, "/r/samcrew/teams$help&func=Join&id="+ids), page)
	uassert.True(t, strings.Contains(page, "(/r/samcrew/teams:player/"+alice.String()+")"), page)
	uassert.True(t, strings.Contains(Render(""), `import "gno.land/r/samcrew/teams"`))
}
