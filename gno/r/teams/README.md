# `teams` - Player teams any game can read

Players form teams here, and a game realm reads who is in which team instead
of keeping its own roster. The rules for joining, leaving and handing a team
over are those of the registry it holds,
[`gno.land/p/samcrew/teams/v0`](../../p/teams/v0), and a game that wants teams
of its own holds one of those instead.

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
`Name`, `Owner` and `Members` abort on an id with no team, a deleted one
included, so a game holding an old id checks `Exists` first. The slices
`Members` and `TeamsOf` return belong to this realm: copy one before sorting or
writing into it. A game calling a function that changes a team acts as itself,
never as its player. Every change emits an event whose `realm` attribute reads
`gno.land/r/samcrew/teams`, listed in the registry's README.

## Pages

- `/r/samcrew/teams`: the newest teams first, a join link on the open ones,
  and a search box.
- `/r/samcrew/teams:search?q=<text>`: the teams whose name starts with the
  text, in any case, or the team with that id, `12` or `#12`. Every team shows
  its id beside its name.
- `/r/samcrew/teams:team/<id>`: one team, its members, pending invites and the
  owner's actions.
- `/r/samcrew/teams:player/<address>`: a player's teams and invites, with
  accept and decline links. A registered username shows in place of the
  address.
