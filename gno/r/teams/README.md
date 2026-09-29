# `teams` - Player teams any game can read

Players form teams here, and a game realm reads who is in which team instead
of keeping its own roster.

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

## Usage in a game

```go
import "gno.land/r/samcrew/teams"

func Enter(cur realm, teamID uint64) {
	player := cur.Previous().Address()
	if !teams.IsMember(teamID, player) {
		panic("join the team first")
	}
	// ...
}
```

The reads are `Exists`, `Name`, `Owner`, `IsMember`, `Members` and `TeamsOf`.
None of them take a `realm` argument, so a game calls them without `cross`.

## Pages

- `/r/samcrew/teams`: every team, with a join link on the open ones.
- `/r/samcrew/teams:team/<id>`: one team, its members, pending invites and the
  owner's actions.
- `/r/samcrew/teams:player/<address>`: a player's teams and invites, with
  accept and decline links.
