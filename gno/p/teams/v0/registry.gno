// Package teams keeps a registry of player teams that a realm owns and games
// read. Each realm holding a Registry has its own teams and pays for their
// storage.
//
// Every method that changes a team takes the address acting as caller and
// trusts it, so the realm passes cur.Previous().Address() and never hands the
// *Registry to another realm: a realm holding the pointer could act as anyone.
package teams

import (
	"crypto/bech32"
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

// Registry holds a set of teams, their members and their pending invites.
type Registry struct {
	lastID  seqid.ID
	teams   avl.Tree // seqid string -> *team
	names   avl.Tree // lowercased name -> true
	players avl.Tree // address -> *avl.Tree of seqid string -> true
	invited avl.Tree // address -> *avl.Tree of seqid string -> true
}

// NewRegistry returns an empty registry.
func NewRegistry() *Registry {
	return &Registry{}
}

// Exists reports whether a team with this id exists; a deleted team does not.
func (r *Registry) Exists(id uint64) bool {
	return r.lookup(id) != nil
}

// Name returns the team's display name.
func (r *Registry) Name(id uint64) string {
	return r.mustGet(id).name
}

// Owner returns the address allowed to manage the team.
func (r *Registry) Owner(id uint64) address {
	return r.mustGet(id).owner
}

// IsMember reports whether addr belongs to the team, false for an unknown team.
func (r *Registry) IsMember(id uint64, addr address) bool {
	t := r.lookup(id)
	return t != nil && t.members.Has(normalize(addr).String())
}

// Members returns the team's members in address order.
func (r *Registry) Members(id uint64) []address {
	t := r.mustGet(id)
	out := make([]address, 0, t.members.Size())
	t.members.Iterate("", "", func(k string, _ any) bool {
		out = append(out, address(k))
		return false
	})
	return out
}

// TeamsOf returns the ids of every team addr belongs to, oldest first.
func (r *Registry) TeamsOf(addr address) []uint64 {
	return indexIDs(&r.players, normalize(addr))
}

// Create makes a team owned by caller, who becomes its first member. An open
// team lets anyone join; otherwise players need an invite or the owner.
func (r *Registry) Create(caller address, name, description string, open bool) uint64 {
	validateName(name)
	validateDescription(description)
	key := strings.ToLower(name)
	if r.names.Has(key) {
		panic("team name already taken")
	}

	id := r.lastID.Next()
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
	r.teams.Set(id.String(), t)
	r.names.Set(key, true)
	r.addMember(t, caller)
	return uint64(id)
}

// SetDescription replaces the team's description. Owner only.
func (r *Registry) SetDescription(caller address, id uint64, description string) {
	t := r.mustOwn(caller, id)
	validateDescription(description)
	t.description = description
}

// SetOpen lets anyone join the team when open is true. Owner only.
func (r *Registry) SetOpen(caller address, id uint64, open bool) {
	r.mustOwn(caller, id).open = open
}

// Join adds caller to an open team, or to any team that invited them.
func (r *Registry) Join(caller address, id uint64) {
	t := r.mustGet(id)
	if !t.open && !t.invites.Has(caller.String()) {
		panic("this team is invite only")
	}
	r.addMember(t, caller)
}

// Invite lets player call Join while the team is invite only. Owner only.
func (r *Registry) Invite(caller address, id uint64, player address) {
	t := r.mustOwn(caller, id)
	mustValidAddress(player)
	if t.members.Has(player.String()) {
		panic("already a member")
	}
	t.invites.Set(player.String(), time.Now())
	indexAdd(&r.invited, player, t.id)
}

// CancelInvite withdraws an invite. The owner or the invited player may call it.
func (r *Registry) CancelInvite(caller address, id uint64, player address) {
	t := r.mustGet(id)
	if caller != t.owner && caller != player {
		panic("only the owner or the invited player can cancel an invite")
	}
	if !r.dropInvite(t, player) {
		panic("no invite for this player")
	}
}

// AddMember puts player in the team without asking them. Owner only.
func (r *Registry) AddMember(caller address, id uint64, player address) {
	t := r.mustOwn(caller, id)
	mustValidAddress(player)
	r.addMember(t, player)
}

// RemoveMember takes player out of the team. Owner only.
func (r *Registry) RemoveMember(caller address, id uint64, player address) {
	r.removeMember(r.mustOwn(caller, id), player)
}

// Leave takes caller out of the team. The owner can leave only as the last
// member, which deletes the team and frees its name.
func (r *Registry) Leave(caller address, id uint64) {
	r.removeMember(r.mustGet(id), caller)
}

// TransferOwnership hands the team to another member. Owner only.
func (r *Registry) TransferOwnership(caller address, id uint64, newOwner address) {
	t := r.mustOwn(caller, id)
	if !t.members.Has(newOwner.String()) {
		panic("the new owner must be a member")
	}
	t.owner = newOwner
}

// lookup returns the team, or nil when no team has this id.
func (r *Registry) lookup(id uint64) *team {
	v := r.teams.Get(seqid.ID(id).String())
	if v == nil {
		return nil
	}
	return v.(*team)
}

func (r *Registry) mustGet(id uint64) *team {
	t := r.lookup(id)
	if t == nil {
		panic("team not found")
	}
	return t
}

func (r *Registry) mustOwn(caller address, id uint64) *team {
	t := r.mustGet(id)
	if caller != t.owner {
		panic("only the team owner can do this")
	}
	return t
}

func (r *Registry) addMember(t *team, addr address) {
	if t.members.Has(addr.String()) {
		panic("already a member")
	}
	t.members.Set(addr.String(), time.Now())
	indexAdd(&r.players, addr, t.id)
	r.dropInvite(t, addr)
}

// removeMember takes addr out of t. The owner may leave only as the last
// member, and that deletes the team.
func (r *Registry) removeMember(t *team, addr address) {
	if !t.members.Has(addr.String()) {
		panic("not a member")
	}
	if addr == t.owner && t.members.Size() > 1 {
		panic("the owner cannot leave while others remain, transfer ownership first")
	}
	t.members.Remove(addr.String())
	indexRemove(&r.players, addr, t.id)
	if t.members.Size() == 0 {
		r.deleteTeam(t)
	}
}

// deleteTeam frees the team's name and withdraws its pending invites.
func (r *Registry) deleteTeam(t *team) {
	t.invites.Iterate("", "", func(k string, _ any) bool {
		indexRemove(&r.invited, address(k), t.id)
		return false
	})
	r.names.Remove(strings.ToLower(t.name))
	r.teams.Remove(t.id.String())
}

func (r *Registry) dropInvite(t *team, addr address) bool {
	_, removed := t.invites.Remove(addr.String())
	if removed {
		indexRemove(&r.invited, addr, t.id)
	}
	return removed
}

// canonical returns the spelling of addr a signer produces, and false when addr
// does not decode.
func canonical(addr address) (address, bool) {
	hrp, data, err := bech32.DecodeToBase256(addr.String())
	if err != nil {
		return addr, false
	}
	s, err := bech32.EncodeFromBase256(hrp, data)
	if err != nil {
		return addr, false
	}
	return address(s), true
}

// normalize maps any spelling of an address to the one its members are stored
// under, and leaves an undecodable one as it is.
func normalize(addr address) address {
	c, _ := canonical(addr)
	return c
}

// mustValidAddress refuses every spelling but the one a signer produces: upper
// case and a bech32m checksum decode too, yet no caller matches the key.
func mustValidAddress(addr address) {
	if c, ok := canonical(addr); !ok || !addr.IsValid() || c != addr {
		panic("invalid address")
	}
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

// indexTree returns the seqid keys addr is linked to in index, empty if none.
func indexTree(index *avl.Tree, addr address) *avl.Tree {
	v := index.Get(addr.String())
	if v == nil {
		return avl.NewTree()
	}
	return v.(*avl.Tree)
}

// indexIDs returns the team ids addr is linked to in index, oldest first.
func indexIDs(index *avl.Tree, addr address) []uint64 {
	ids := indexTree(index, addr)
	out := make([]uint64, 0, ids.Size())
	ids.Iterate("", "", func(k string, _ any) bool {
		id, err := seqid.FromString(k)
		if err != nil {
			panic(err)
		}
		out = append(out, uint64(id))
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
	for _, c := range name {
		switch {
		case c >= 'a' && c <= 'z', c >= 'A' && c <= 'Z', c >= '0' && c <= '9':
		case c == ' ', c == '-', c == '_':
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
