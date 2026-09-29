package teams

import (
	"crypto/bech32"
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
	dave  = testutils.TestAddress("dave")
)

func TestCreate(cur realm, t *testing.T) {
	r := NewRegistry()
	id := r.Create(alice, "Red Foxes", "We hunt at night", true)

	uassert.True(t, r.Exists(id))
	uassert.Equal(t, "Red Foxes", r.Name(id))
	uassert.Equal(t, alice, r.Owner(id))
	uassert.True(t, r.IsMember(id, alice))
	uassert.Equal(t, 1, len(r.Members(id)))
	uassert.True(t, containsID(r.TeamsOf(alice), id))

	uassert.PanicsWithMessage(t, cur, "team name already taken", func() {
		r.Create(bob, "red foxes", "", false)
	})
	for _, name := range []string{"ab", strings.Repeat("a", 33), " Lead", "Two  spaces", "Emoji🦊", "[link](x)"} {
		uassert.PanicsContains(t, cur, "team name", func() {
			r.Create(bob, name, "", false)
		}, name)
	}
	uassert.PanicsWithMessage(t, cur, "team description must fit on one line", func() {
		r.Create(bob, "Blue Owls", "line\nbreak", false)
	})
	uassert.PanicsWithMessage(t, cur, "only the team owner can do this", func() {
		r.SetDescription(bob, id, "hijacked")
	})
	r.SetDescription(alice, id, "We hunt at dawn")
	uassert.Equal(t, "We hunt at dawn", r.mustGet(id).description)
}

func TestRegistriesAreSeparate(cur realm, t *testing.T) {
	a, b := NewRegistry(), NewRegistry()
	ida := a.Create(alice, "Same Name", "", true)
	idb := b.Create(bob, "Same Name", "", true)

	uassert.Equal(t, ida, idb)
	uassert.Equal(t, alice, a.Owner(ida))
	uassert.Equal(t, bob, b.Owner(idb))
	uassert.False(t, b.IsMember(idb, alice))
}

func TestAddresses(cur realm, t *testing.T) {
	r := NewRegistry()
	id := r.Create(alice, "Spellings", "", false)

	// Other spellings of carol's address decode, yet no signer produces them.
	for _, other := range []address{address(strings.ToUpper(carol.String())), bech32m(carol)} {
		uassert.True(t, other.IsValid())
		uassert.PanicsWithMessage(t, cur, "invalid address", func() {
			r.AddMember(alice, id, other)
		})
		uassert.PanicsWithMessage(t, cur, "invalid address", func() {
			r.Invite(alice, id, other)
		})
	}
	// Reads map every spelling to the member it names.
	uassert.True(t, r.IsMember(id, address(strings.ToUpper(alice.String()))))
	uassert.True(t, r.IsMember(id, bech32m(alice)))
	uassert.True(t, containsID(r.TeamsOf(bech32m(alice)), id))
}

func TestJoinModes(cur realm, t *testing.T) {
	r := NewRegistry()
	open := r.Create(alice, "Open Door", "", true)
	closed := r.Create(alice, "Locked Door", "", false)

	r.Join(bob, open)
	uassert.True(t, r.IsMember(open, bob))
	uassert.PanicsWithMessage(t, cur, "already a member", func() { r.Join(bob, open) })
	uassert.PanicsWithMessage(t, cur, "this team is invite only", func() { r.Join(bob, closed) })

	// An invite lets bob into the closed team and is spent on joining.
	r.Invite(alice, closed, bob)
	uassert.True(t, containsID(indexIDs(&r.invited, bob), closed))
	r.Join(bob, closed)
	uassert.True(t, r.IsMember(closed, bob))
	uassert.Equal(t, 0, len(indexIDs(&r.invited, bob)))

	// The owner can add carol directly, and nobody else can.
	uassert.PanicsWithMessage(t, cur, "only the team owner can do this", func() {
		r.AddMember(bob, closed, carol)
	})
	r.AddMember(alice, closed, carol)
	uassert.True(t, r.IsMember(closed, carol))

	// Opening the team lets anyone in.
	r.SetOpen(alice, closed, true)
	r.Join(dave, closed)
	uassert.True(t, r.IsMember(closed, dave))
}

func TestCancelInvite(cur realm, t *testing.T) {
	r := NewRegistry()
	id := r.Create(alice, "Invite Only", "", false)
	r.Invite(alice, id, bob)
	r.Invite(alice, id, carol)

	uassert.PanicsWithMessage(t, cur, "only the owner or the invited player can cancel an invite", func() {
		r.CancelInvite(carol, id, bob)
	})
	r.CancelInvite(carol, id, carol)
	uassert.PanicsWithMessage(t, cur, "this team is invite only", func() { r.Join(carol, id) })

	r.CancelInvite(alice, id, bob)
	uassert.PanicsWithMessage(t, cur, "no invite for this player", func() {
		r.CancelInvite(alice, id, bob)
	})
	uassert.Equal(t, 0, len(indexIDs(&r.invited, bob)))
}

func TestLeaveAndOwnership(cur realm, t *testing.T) {
	r := NewRegistry()
	id := r.Create(alice, "Hand Over", "", true)
	r.Join(bob, id)
	r.Join(carol, id)

	const ownerStays = "the owner cannot leave while others remain, transfer ownership first"
	uassert.PanicsWithMessage(t, cur, ownerStays, func() { r.Leave(alice, id) })
	uassert.PanicsWithMessage(t, cur, ownerStays, func() { r.RemoveMember(alice, id, alice) })
	r.RemoveMember(alice, id, carol)
	uassert.False(t, r.IsMember(id, carol))
	uassert.False(t, containsID(r.TeamsOf(carol), id))

	uassert.PanicsWithMessage(t, cur, "the new owner must be a member", func() {
		r.TransferOwnership(alice, id, carol)
	})
	r.TransferOwnership(alice, id, bob)
	uassert.Equal(t, bob, r.Owner(id))
	r.Leave(alice, id)
	uassert.False(t, r.IsMember(id, alice))
	uassert.PanicsWithMessage(t, cur, "not a member", func() { r.Leave(carol, id) })
}

func TestLastMemberDeletesTeam(cur realm, t *testing.T) {
	// A player handed a team without asking can still get out: once alone,
	// leaving deletes the team.
	r := NewRegistry()
	id := r.Create(alice, "Short Lived", "", false)
	r.AddMember(alice, id, bob)
	r.Invite(alice, id, carol)
	r.TransferOwnership(alice, id, bob)
	r.Leave(alice, id)
	r.Leave(bob, id)

	uassert.False(t, r.Exists(id))
	uassert.False(t, r.IsMember(id, bob))
	uassert.False(t, containsID(r.TeamsOf(bob), id))
	uassert.False(t, containsID(indexIDs(&r.invited, carol), id))
	uassert.True(t, strings.Contains(r.Render("team/"+strconv.FormatUint(id, 10), nil), "Team not found"))

	// The name is free again, under a new id.
	again := r.Create(bob, "short lived", "", false)
	uassert.NotEqual(t, id, again)
}

func TestRender(cur realm, t *testing.T) {
	r := NewRegistry()
	id := r.Create(alice, "Render Crew", "Markdown *is* escaped", false)
	r.Invite(alice, id, bob)
	ids := strconv.FormatUint(id, 10)

	home := r.Render("", nil)
	uassert.True(t, strings.Contains(home, "[Render Crew]("), home)
	uassert.True(t, strings.Contains(home, ":team/"+ids+")"), home)

	page := r.Render("team/"+ids, nil)
	uassert.True(t, strings.Contains(page, "✉️ Invite only"), page)
	uassert.True(t, strings.Contains(page, "## ✉️ Pending invites (1)"), page)
	uassert.False(t, strings.Contains(page, "*is*"), page)

	player := r.Render("player/"+bob.String(), nil)
	uassert.True(t, strings.Contains(player, "## ✉️ Invites (1)"), player)

	// nameOf replaces the short address wherever a player is shown.
	named := r.Render("team/"+ids, func(a address) string {
		if a == alice {
			return "@alice"
		}
		return ""
	})
	uassert.True(t, strings.Contains(named, "[@alice]("), named)

	uassert.True(t, strings.Contains(r.Render("team/999", nil), "Team not found"))
	uassert.True(t, strings.Contains(r.Render("team/abc", nil), "Team not found"))
	uassert.True(t, strings.Contains(r.Render("player/nope", nil), "Not a valid address"))
}

func TestRenderPaging(cur realm, t *testing.T) {
	r := NewRegistry()
	for i := 0; i < pageSize+1; i++ {
		id := r.Create(alice, "Paged "+strconv.Itoa(i), "", false)
		r.AddMember(alice, id, carol)
		r.Invite(alice, id, bob)
	}

	player := r.Render("player/"+carol.String(), nil)
	uassert.True(t, strings.Contains(player, "?page=2"), player)
	uassert.Equal(t, pageSize, strings.Count(player, "🧑 Member"))
	// A link cannot raise the page size.
	big := r.Render("player/"+carol.String()+"?size=100", nil)
	uassert.Equal(t, pageSize, strings.Count(big, "🧑 Member"))

	// The invites picker keeps the page the teams table is on.
	invites := r.Render("player/"+bob.String()+"?page=3&invites=2", nil)
	uassert.True(t, strings.Contains(invites, "?invites=1&page=3"), invites)
	uassert.Equal(t, 1, strings.Count(invites, "✅ Accept"), invites)
}

func TestHomeListsNewestFirst(cur realm, t *testing.T) {
	r := NewRegistry()
	r.Create(alice, "Oldest Crew", "", true)
	r.Create(alice, "Newest Crew", "", true)

	home := r.Render("", nil)
	uassert.True(t, strings.Index(home, "Newest Crew") < strings.Index(home, "Oldest Crew"), home)
}

func TestSearch(cur realm, t *testing.T) {
	r := NewRegistry()
	for i := 0; i < pageSize+1; i++ {
		r.Create(alice, "Wolf Pack "+strconv.Itoa(100+i), "", true)
	}
	r.Create(alice, "Red Foxes", "", true)

	// A prefix matches whatever the case, and nothing outside the prefix.
	first := r.Render("search?q=WOLF", nil)
	uassert.True(t, strings.Contains(first, "(21)"), first)
	uassert.Equal(t, pageSize, strings.Count(first, "Wolf Pack "), first)
	uassert.False(t, strings.Contains(first, "Red Foxes"), first)
	uassert.True(t, strings.Contains(first, "?page=2&q=WOLF"), first)

	second := r.Render("search?q=wolf&page=2", nil)
	uassert.Equal(t, 1, strings.Count(second, "Wolf Pack "), second)
	uassert.True(t, strings.Contains(second, "Wolf Pack 120"), second)

	uassert.True(t, strings.Contains(r.Render("search?q=red", nil), "Red Foxes"))
	uassert.True(t, strings.Contains(r.Render("search?q=zebra", nil), "No team found."))
	uassert.True(t, strings.Contains(r.Render("search", nil), "Type the start"))
	uassert.True(t, strings.Contains(r.Render("search?q=wolf&page=9", nil), "(21)"))

	// What the viewer typed is shown back escaped, in the heading and the box.
	odd := r.Render(`search?q="><img src=x>`, nil)
	uassert.True(t, strings.Contains(odd, `\<img`), odd)
	uassert.True(t, strings.Contains(odd, `value="&#34;&gt;&lt;img`), odd)
	uassert.Equal(t, 0, strings.Count(odd, `"><img`)+strings.Count(odd, " <img"), odd)
}

// bech32m spells addr with the bech32m checksum instead of bech32.
func bech32m(addr address) address {
	hrp, data, err := bech32.DecodeToBase256(addr.String())
	if err != nil {
		panic(err)
	}
	five, err := bech32.ConvertBits(data, 8, 5, true)
	if err != nil {
		panic(err)
	}
	s, err := bech32.EncodeM(hrp, five)
	if err != nil {
		panic(err)
	}
	return address(s)
}

func containsID(ids []uint64, id uint64) bool {
	for _, x := range ids {
		if x == id {
			return true
		}
	}
	return false
}
