package teams

import (
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
	carol = testutils.TestAddress("carol")
)

func TestCreateTeam(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(alice))
	id := CreateTeam(cross(cur), "Red Foxes", "We hunt at night", true)

	uassert.True(t, Exists(id))
	uassert.Equal(t, "Red Foxes", Name(id))
	uassert.Equal(t, alice, Owner(id))
	uassert.True(t, IsMember(id, alice))
	uassert.Equal(t, 1, len(Members(id)))
	uassert.True(t, containsID(TeamsOf(alice), id))

	testing.SetRealm(testing.NewUserRealm(bob))
	urequire.AbortsWithMessage(t, cur, "team name already taken", func(cur realm) {
		testing.SetRealm(testing.NewUserRealm(bob))
		CreateTeam(cross(cur), "red foxes", "", false)
	})
	for _, name := range []string{"ab", strings.Repeat("a", 33), " Lead", "Two  spaces", "Emoji🦊", "[link](x)"} {
		uassert.AbortsContains(t, cur, "team name", func(cur realm) {
			testing.SetRealm(testing.NewUserRealm(bob))
			CreateTeam(cross(cur), name, "", false)
		}, name)
	}
	upper := address(strings.ToUpper(carol.String()))
	uassert.True(t, upper.IsValid())
	urequire.AbortsWithMessage(t, cur, "invalid address", func(cur realm) {
		testing.SetRealm(testing.NewUserRealm(alice))
		AddMember(cross(cur), id, upper)
	})
	urequire.AbortsWithMessage(t, cur, "invalid address", func(cur realm) {
		testing.SetRealm(testing.NewUserRealm(alice))
		Invite(cross(cur), id, upper)
	})
	urequire.AbortsWithMessage(t, cur, "team description must fit on one line", func(cur realm) {
		testing.SetRealm(testing.NewUserRealm(bob))
		CreateTeam(cross(cur), "Blue Owls", "line\nbreak", false)
	})
	urequire.AbortsWithMessage(t, cur, "only the team owner can do this", func(cur realm) {
		testing.SetRealm(testing.NewUserRealm(bob))
		SetDescription(cross(cur), id, "hijacked")
	})

	testing.SetRealm(testing.NewUserRealm(alice))
	SetDescription(cross(cur), id, "We hunt at dawn")
	uassert.Equal(t, "We hunt at dawn", mustGet(id).description)
}

func TestJoinModes(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(alice))
	open := CreateTeam(cross(cur), "Open Door", "", true)
	closed := CreateTeam(cross(cur), "Locked Door", "", false)

	testing.SetRealm(testing.NewUserRealm(bob))
	Join(cross(cur), open)
	uassert.True(t, IsMember(open, bob))
	urequire.AbortsWithMessage(t, cur, "already a member", func(cur realm) {
		testing.SetRealm(testing.NewUserRealm(bob))
		Join(cross(cur), open)
	})
	urequire.AbortsWithMessage(t, cur, "this team is invite only", func(cur realm) {
		testing.SetRealm(testing.NewUserRealm(bob))
		Join(cross(cur), closed)
	})

	// An invite lets bob into the closed team and is spent on joining.
	testing.SetRealm(testing.NewUserRealm(alice))
	Invite(cross(cur), closed, bob)
	uassert.True(t, containsID(indexIDs(&invited, bob), closed))
	testing.SetRealm(testing.NewUserRealm(bob))
	Join(cross(cur), closed)
	uassert.True(t, IsMember(closed, bob))
	uassert.Equal(t, 0, len(indexIDs(&invited, bob)))

	// The owner can add carol directly, and nobody else can.
	testing.SetRealm(testing.NewUserRealm(bob))
	urequire.AbortsWithMessage(t, cur, "only the team owner can do this", func(cur realm) {
		testing.SetRealm(testing.NewUserRealm(bob))
		AddMember(cross(cur), closed, carol)
	})
	testing.SetRealm(testing.NewUserRealm(alice))
	AddMember(cross(cur), closed, carol)
	uassert.True(t, IsMember(closed, carol))

	// Opening the team lets anyone in.
	SetOpen(cross(cur), closed, true)
	dave := testutils.TestAddress("dave")
	testing.SetRealm(testing.NewUserRealm(dave))
	Join(cross(cur), closed)
	uassert.True(t, IsMember(closed, dave))
}

func TestCancelInvite(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(alice))
	id := CreateTeam(cross(cur), "Invite Only", "", false)
	Invite(cross(cur), id, bob)
	Invite(cross(cur), id, carol)

	testing.SetRealm(testing.NewUserRealm(carol))
	urequire.AbortsWithMessage(t, cur, "only the owner or the invited player can cancel an invite", func(cur realm) {
		testing.SetRealm(testing.NewUserRealm(carol))
		CancelInvite(cross(cur), id, bob)
	})
	CancelInvite(cross(cur), id, carol)
	urequire.AbortsWithMessage(t, cur, "this team is invite only", func(cur realm) {
		testing.SetRealm(testing.NewUserRealm(carol))
		Join(cross(cur), id)
	})

	testing.SetRealm(testing.NewUserRealm(alice))
	CancelInvite(cross(cur), id, bob)
	urequire.AbortsWithMessage(t, cur, "no invite for this player", func(cur realm) {
		testing.SetRealm(testing.NewUserRealm(alice))
		CancelInvite(cross(cur), id, bob)
	})
	uassert.Equal(t, 0, len(indexIDs(&invited, bob)))
}

func TestLeaveAndOwnership(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(alice))
	id := CreateTeam(cross(cur), "Hand Over", "", true)
	testing.SetRealm(testing.NewUserRealm(bob))
	Join(cross(cur), id)
	testing.SetRealm(testing.NewUserRealm(carol))
	Join(cross(cur), id)

	testing.SetRealm(testing.NewUserRealm(alice))
	urequire.AbortsWithMessage(t, cur, "the owner cannot leave, transfer ownership first", func(cur realm) {
		testing.SetRealm(testing.NewUserRealm(alice))
		Leave(cross(cur), id)
	})
	urequire.AbortsWithMessage(t, cur, "the owner cannot leave, transfer ownership first", func(cur realm) {
		testing.SetRealm(testing.NewUserRealm(alice))
		RemoveMember(cross(cur), id, alice)
	})
	RemoveMember(cross(cur), id, carol)
	uassert.False(t, IsMember(id, carol))
	uassert.False(t, containsID(TeamsOf(carol), id))

	urequire.AbortsWithMessage(t, cur, "the new owner must be a member", func(cur realm) {
		testing.SetRealm(testing.NewUserRealm(alice))
		TransferOwnership(cross(cur), id, carol)
	})
	TransferOwnership(cross(cur), id, bob)
	uassert.Equal(t, bob, Owner(id))
	Leave(cross(cur), id)
	uassert.False(t, IsMember(id, alice))

	testing.SetRealm(testing.NewUserRealm(carol))
	urequire.AbortsWithMessage(t, cur, "not a member", func(cur realm) {
		testing.SetRealm(testing.NewUserRealm(carol))
		Leave(cross(cur), id)
	})
}

func TestRender(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(alice))
	id := CreateTeam(cross(cur), "Render Crew", "Markdown *is* escaped", false)
	Invite(cross(cur), id, bob)
	ids := strconv.FormatUint(id, 10)

	// Teams list oldest first, so this one sits on the last page.
	last := (teams.Size() + pageSize - 1) / pageSize
	home := Render("?page=" + strconv.Itoa(last))
	uassert.True(t, strings.Contains(home, "[Render Crew](/r/samcrew/teams:team/"+ids+")"), home)

	page := Render("team/" + ids)
	uassert.True(t, strings.Contains(page, "# "), page)
	uassert.True(t, strings.Contains(page, "✉️ Invite only"), page)
	uassert.True(t, strings.Contains(page, "## ✉️ Pending invites (1)"), page)
	uassert.False(t, strings.Contains(page, "*is*"), page)

	player := Render("player/" + bob.String())
	uassert.True(t, strings.Contains(player, "## ✉️ Invites (1)"), player)

	uassert.True(t, strings.Contains(Render("team/999"), "Team not found"))
	uassert.True(t, strings.Contains(Render("team/abc"), "Team not found"))
	uassert.True(t, strings.Contains(Render("player/nope"), "Not a valid address"))
}

func TestRenderPaging(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(alice))
	carlo := testutils.TestAddress("carlo")
	for i := 0; i < pageSize+1; i++ {
		id := CreateTeam(cross(cur), "Paged "+strconv.Itoa(i), "", false)
		AddMember(cross(cur), id, carlo)
		Invite(cross(cur), id, bob)
	}

	player := Render("player/" + carlo.String())
	uassert.True(t, strings.Contains(player, "?page=2"), player)
	uassert.Equal(t, pageSize, strings.Count(player, "🧑 Member"))

	// The invites picker keeps the page the teams table is on.
	invites := Render("player/" + bob.String() + "?page=3&invites=2")
	uassert.True(t, strings.Contains(invites, "?invites=1&page=3"), invites)
	uassert.Equal(t, indexTree(&invited, bob).Size()-pageSize, strings.Count(invites, "✅ Accept"), invites)
}

func containsID(ids []uint64, id uint64) bool {
	for _, x := range ids {
		if x == id {
			return true
		}
	}
	return false
}
