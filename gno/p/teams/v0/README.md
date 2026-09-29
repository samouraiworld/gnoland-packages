# `teams` - Team registry a realm owns

A `Registry` holds teams, their members and their pending invites. The realm
that holds one owns those teams and pays for their storage, so each game can run
teams of its own. [`gno.land/r/samcrew/teams`](../../../r/teams) is the shared
one any game can read.

## Joining

A team's owner picks how players get in, and all three ways work at once:

- **Open**: anyone calls `Join`.
- **Invite**: the owner calls `Invite`, then the player calls `Join`. Either
  side can withdraw it with `CancelInvite`.
- **Direct**: the owner calls `AddMember`, with no step from the player.

`SetOpen` switches a team between open and invite only. While others remain,
the owner stays until `TransferOwnership` hands the team to another member. The
last member to `Leave` deletes the team: its name is free again, its pending
invites are withdrawn, and `Exists` reads false for its id.

## Usage in a game realm

```go
import pteams "gno.land/p/samcrew/teams/v0"

var registry = pteams.NewRegistry() // unexported, never handed out

func CreateTeam(cur realm, name, description, avatar string, open bool) uint64 {
	if cur.Previous().Address() == banned {
		panic("not in this game")
	}
	return registry.Create(cur.Previous().Address(), name, description, avatar, open)
}

func Render(path string) string { return registry.Render(path, nil) }
```

Every method that changes a team takes the address acting and trusts it. Pass
`cur.Previous().Address()`, and keep the `*Registry` unexported: another realm
holding it could act as anyone. A game's own rules, a size cap or a ban list,
go in its functions before the call.

`Render` serves four pages: the newest teams first with a search box,
`search?q=<text>` for the teams whose name starts with the text in any case,
or the team with that id when the text is a number, `team/<id>` and
`player/<address>`. Every team shows its id, and every table 20 rows a page.
Their buttons link to the calling realm's functions by name, so a realm serving
them exposes `CreateTeam(name, description, avatar, open)`, `Join(id)`, `Leave(id)`,
`Invite(id, player)`, `CancelInvite(id, player)`, `AddMember(id, player)`,
`RemoveMember(id, player)`, `SetOpen(id, open)`, `SetDescription(id,
description)`, `SetAvatar(id, avatar)` and `TransferOwnership(id, newOwner)`. An
avatar is one emoji, and a team without one shows a coloured dot. The second argument names a
player, a registered username for one; nil shows a short address.

## Reads

`Exists`, `Name`, `Owner`, `IsMember`, `Members` and `TeamsOf`. `Name`, `Owner`
and `Members` panic on an id with no team, a deleted one included, so check
`Exists` first. Every read takes any spelling of an address that decodes, upper
case included, and every write refuses all but the one a signer produces.

## Events

Every change emits one event, each carrying `realm`, the realm whose registry
changed, and `team`, the id: `TeamCreated` with `name` and `owner`,
`TeamUpdated` with `field`, `MemberJoined` and `MemberLeft` with `player` and
`via`, `InviteSent` and `InviteCanceled` with `player`, `OwnershipTransferred`
with `from` and `to`, and `TeamDeleted` with `name`. The VM stamps each with
this package's path, so `realm` is what tells one game's registry from another.
