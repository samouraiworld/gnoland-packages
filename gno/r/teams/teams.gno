// Package teams lets players form teams that any game realm can read.
package teams

import (
	"strings"
	"time"

	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/seqid/v0"
)

const (
	minNameLen        = 3
	maxNameLen        = 32
	maxDescriptionLen = 280
)

type team struct {
	id          seqid.ID
	name        string
	description string
	owner       address
	open        bool // anyone may join without an invite
	createdAt   time.Time
	members     *avl.Tree // address -> time.Time joined
	invites     *avl.Tree // address -> time.Time invited
}

var (
	lastID  seqid.ID
	teams   avl.Tree // seqid string -> *team
	names   avl.Tree // lowercased name -> seqid string
	players avl.Tree // address -> *avl.Tree of seqid string -> true
	invited avl.Tree // address -> *avl.Tree of seqid string -> true
)

// Exists reports whether a team with this id was created.
func Exists(id uint64) bool {
	return teams.Has(seqid.ID(id).String())
}

// Name returns the team's display name.
func Name(id uint64) string {
	return mustGet(id).name
}

// Owner returns the address allowed to manage the team.
func Owner(id uint64) address {
	return mustGet(id).owner
}

// IsMember reports whether addr belongs to the team, false for an unknown team.
func IsMember(id uint64, addr address) bool {
	v := teams.Get(seqid.ID(id).String())
	return v != nil && v.(*team).members.Has(addr.String())
}

// Members returns the team's members in address order.
func Members(id uint64) []address {
	t := mustGet(id)
	out := make([]address, 0, t.members.Size())
	t.members.Iterate("", "", func(k string, _ any) bool {
		out = append(out, address(k))
		return false
	})
	return out
}

// TeamsOf returns the ids of every team addr belongs to, oldest first.
func TeamsOf(addr address) []uint64 {
	return indexIDs(&players, addr)
}

func mustGet(id uint64) *team {
	v := teams.Get(seqid.ID(id).String())
	if v == nil {
		panic("team not found")
	}
	return v.(*team)
}

func mustParseID(s string) seqid.ID {
	id, err := seqid.FromString(s)
	if err != nil {
		panic(err)
	}
	return id
}

func addMember(t *team, addr address) {
	t.members.Set(addr.String(), time.Now())
	indexAdd(&players, addr, t.id)
	dropInvite(t, addr)
}

func removeMember(t *team, addr address) {
	t.members.Remove(addr.String())
	indexRemove(&players, addr, t.id)
}

func setInvite(t *team, addr address) {
	t.invites.Set(addr.String(), time.Now())
	indexAdd(&invited, addr, t.id)
}

func dropInvite(t *team, addr address) bool {
	_, removed := t.invites.Remove(addr.String())
	indexRemove(&invited, addr, t.id)
	return removed
}

// indexAdd records that addr is linked to team id in a per-address index.
func indexAdd(index *avl.Tree, addr address, id seqid.ID) {
	v := index.Get(addr.String())
	if v == nil {
		v = avl.NewTree()
		index.Set(addr.String(), v)
	}
	v.(*avl.Tree).Set(id.String(), true)
}

func indexRemove(index *avl.Tree, addr address, id seqid.ID) {
	v := index.Get(addr.String())
	if v == nil {
		return
	}
	ids := v.(*avl.Tree)
	ids.Remove(id.String())
	if ids.Size() == 0 {
		index.Remove(addr.String())
	}
}

// indexIDs returns the team ids addr is linked to in index, oldest first.
func indexIDs(index *avl.Tree, addr address) []uint64 {
	v := index.Get(addr.String())
	if v == nil {
		return nil
	}
	ids := v.(*avl.Tree)
	out := make([]uint64, 0, ids.Size())
	ids.Iterate("", "", func(k string, _ any) bool {
		out = append(out, uint64(mustParseID(k)))
		return false
	})
	return out
}

func validateName(name string) {
	if len(name) < minNameLen || len(name) > maxNameLen {
		panic("team name must be 3 to 32 characters")
	}
	if strings.TrimSpace(name) != name || strings.Contains(name, "  ") {
		panic("team name cannot start, end or repeat spaces")
	}
	for _, r := range name {
		switch {
		case r >= 'a' && r <= 'z', r >= 'A' && r <= 'Z', r >= '0' && r <= '9':
		case r == ' ', r == '-', r == '_':
		default:
			panic("team name may only use letters, digits, spaces, - and _")
		}
	}
}

func validateDescription(description string) {
	if len(description) > maxDescriptionLen {
		panic("team description must be 280 bytes or fewer")
	}
	if strings.ContainsAny(description, "\r\n") {
		panic("team description must fit on one line")
	}
}
