package teams

import (
	"strings"
	"time"

	"gno.land/p/nt/avl/v0"
)

// CreateTeam creates a team owned by the caller, who becomes its first member.
// An open team lets anyone join; otherwise players need an invite or the owner.
func CreateTeam(cur realm, name, description string, open bool) uint64 {
	caller := cur.Previous().Address()
	validateName(name)
	validateDescription(description)
	key := strings.ToLower(name)
	if names.Has(key) {
		panic("team name already taken")
	}

	id := lastID.Next()
	t := &team{
		id:          id,
		name:        name,
		description: description,
		owner:       caller,
		open:        open,
		createdAt:   time.Now(),
		members:     avl.NewTree(),
		invites:     avl.NewTree(),
	}
	teams.Set(id.String(), t)
	names.Set(key, true)
	addMember(t, caller)
	return uint64(id)
}

// SetDescription replaces the team's description. Owner only.
func SetDescription(cur realm, id uint64, description string) {
	t := mustOwn(cur, id)
	validateDescription(description)
	t.description = description
}

// SetOpen lets anyone join the team when open is true. Owner only.
func SetOpen(cur realm, id uint64, open bool) {
	mustOwn(cur, id).open = open
}

// Join adds the caller to an open team, or to any team that invited them.
func Join(cur realm, id uint64) {
	caller := cur.Previous().Address()
	t := mustGet(id)
	if !t.open && !t.invites.Has(caller.String()) {
		panic("this team is invite only")
	}
	addMember(t, caller)
}

// Invite lets player call Join while the team is invite only. Owner only.
func Invite(cur realm, id uint64, player address) {
	t := mustOwn(cur, id)
	mustValidAddress(player)
	if t.members.Has(player.String()) {
		panic("already a member")
	}
	setInvite(t, player)
}

// CancelInvite withdraws an invite. The owner or the invited player may call it.
func CancelInvite(cur realm, id uint64, player address) {
	caller := cur.Previous().Address()
	t := mustGet(id)
	if caller != t.owner && caller != player {
		panic("only the owner or the invited player can cancel an invite")
	}
	if !dropInvite(t, player) {
		panic("no invite for this player")
	}
}

// AddMember puts player in the team without asking them. Owner only.
func AddMember(cur realm, id uint64, player address) {
	t := mustOwn(cur, id)
	mustValidAddress(player)
	addMember(t, player)
}

// RemoveMember takes player out of the team. Owner only.
func RemoveMember(cur realm, id uint64, player address) {
	removeMember(mustOwn(cur, id), player)
}

// Leave takes the caller out of the team. The owner can leave only as the last
// member, which deletes the team and frees its name.
func Leave(cur realm, id uint64) {
	removeMember(mustGet(id), cur.Previous().Address())
}

// TransferOwnership hands the team to another member. Owner only.
func TransferOwnership(cur realm, id uint64, newOwner address) {
	t := mustOwn(cur, id)
	if !t.members.Has(newOwner.String()) {
		panic("the new owner must be a member")
	}
	t.owner = newOwner
}

// mustValidAddress refuses the upper-case spelling of an address too: it
// decodes, but no caller ever matches the key it would be stored under.
func mustValidAddress(addr address) {
	if !addr.IsValid() || addr.String() != strings.ToLower(addr.String()) {
		panic("invalid address")
	}
}

func mustOwn(cur realm, id uint64) *team {
	t := mustGet(id)
	if cur.Previous().Address() != t.owner {
		panic("only the team owner can do this")
	}
	return t
}
