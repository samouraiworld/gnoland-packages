// Package teams is the shared team registry on gno.land: any player forms a
// team here and any game reads it. A game that wants teams of its own holds a
// gno.land/p/samcrew/teams/v0 Registry instead.
package teams

import (
	pteams "gno.land/p/samcrew/teams/v0"
	"gno.land/r/sys/users"
)

// registry stays unexported: its methods trust the caller they are given, so a
// realm holding it could act as anyone.
var registry = pteams.NewRegistry()

// CreateTeam creates a team owned by the caller, who becomes its first member.
// An open team lets anyone join; otherwise players need an invite or the owner.
func CreateTeam(cur realm, name, description string, open bool) uint64 {
	return registry.Create(cur.Previous().Address(), name, description, open)
}

// SetDescription replaces the team's description. Owner only.
func SetDescription(cur realm, id uint64, description string) {
	registry.SetDescription(cur.Previous().Address(), id, description)
}

// SetOpen lets anyone join the team when open is true. Owner only.
func SetOpen(cur realm, id uint64, open bool) {
	registry.SetOpen(cur.Previous().Address(), id, open)
}

// Join adds the caller to an open team, or to any team that invited them.
func Join(cur realm, id uint64) {
	registry.Join(cur.Previous().Address(), id)
}

// Invite lets player call Join while the team is invite only. Owner only.
func Invite(cur realm, id uint64, player address) {
	registry.Invite(cur.Previous().Address(), id, player)
}

// CancelInvite withdraws an invite. The owner or the invited player may call it.
func CancelInvite(cur realm, id uint64, player address) {
	registry.CancelInvite(cur.Previous().Address(), id, player)
}

// AddMember puts player in the team without asking them. Owner only.
func AddMember(cur realm, id uint64, player address) {
	registry.AddMember(cur.Previous().Address(), id, player)
}

// RemoveMember takes player out of the team. Owner only.
func RemoveMember(cur realm, id uint64, player address) {
	registry.RemoveMember(cur.Previous().Address(), id, player)
}

// Leave takes the caller out of the team. The owner can leave only as the last
// member, which deletes the team and frees its name.
func Leave(cur realm, id uint64) {
	registry.Leave(cur.Previous().Address(), id)
}

// TransferOwnership hands the team to another member. Owner only.
func TransferOwnership(cur realm, id uint64, newOwner address) {
	registry.TransferOwnership(cur.Previous().Address(), id, newOwner)
}

// Exists reports whether a team with this id exists; a deleted team does not.
func Exists(id uint64) bool { return registry.Exists(id) }

// Name returns the team's display name.
func Name(id uint64) string { return registry.Name(id) }

// Owner returns the address allowed to manage the team.
func Owner(id uint64) address { return registry.Owner(id) }

// IsMember reports whether addr belongs to the team, false for an unknown team.
func IsMember(id uint64, addr address) bool { return registry.IsMember(id, addr) }

// Members returns the team's members in address order.
func Members(id uint64) []address { return registry.Members(id) }

// TeamsOf returns the ids of every team addr belongs to, oldest first.
func TeamsOf(addr address) []uint64 { return registry.TeamsOf(addr) }

func Render(path string) string {
	return registry.Render(path, username)
}

// username returns the name addr registered in r/sys/users, "" without one.
func username(addr address) string {
	if u := users.ResolveAddress(addr); u != nil {
		return "@" + u.Name()
	}
	return ""
}
