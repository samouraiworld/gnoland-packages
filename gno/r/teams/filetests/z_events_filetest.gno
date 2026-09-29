// PKGPATH: gno.land/r/samcrew/teamsevents
package teamsevents

import (
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/r/samcrew/teams"
)

// Every change emits one event naming the realm whose registry changed.
func main(cur realm) {
	alice := testutils.TestAddress("alice")
	bob := testutils.TestAddress("bob")

	testing.SetRealm(testing.NewUserRealm(alice))
	id := teams.CreateTeam(cross(cur), "Evented", "", "🦊", false)
	teams.Invite(cross(cur), id, bob)
	teams.SetOpen(cross(cur), id, true)

	testing.SetRealm(testing.NewUserRealm(bob))
	teams.Join(cross(cur), id)
	teams.Leave(cross(cur), id)

	testing.SetRealm(testing.NewUserRealm(alice))
	teams.Leave(cross(cur), id)
}

// Events:
// [
//   {
//     "type": "TeamCreated",
//     "attrs": [
//       {
//         "key": "realm",
//         "value": "gno.land/r/samcrew/teams"
//       },
//       {
//         "key": "team",
//         "value": "1"
//       },
//       {
//         "key": "name",
//         "value": "Evented"
//       },
//       {
//         "key": "owner",
//         "value": "g1v9kxjcm9ta047h6lta047h6lta047h6lzd40gh"
//       }
//     ],
//     "pkg_path": "gno.land/p/samcrew/teams/v0"
//   },
//   {
//     "type": "MemberJoined",
//     "attrs": [
//       {
//         "key": "realm",
//         "value": "gno.land/r/samcrew/teams"
//       },
//       {
//         "key": "team",
//         "value": "1"
//       },
//       {
//         "key": "player",
//         "value": "g1v9kxjcm9ta047h6lta047h6lta047h6lzd40gh"
//       },
//       {
//         "key": "via",
//         "value": "create"
//       }
//     ],
//     "pkg_path": "gno.land/p/samcrew/teams/v0"
//   },
//   {
//     "type": "InviteSent",
//     "attrs": [
//       {
//         "key": "realm",
//         "value": "gno.land/r/samcrew/teams"
//       },
//       {
//         "key": "team",
//         "value": "1"
//       },
//       {
//         "key": "player",
//         "value": "g1vfhkyh6lta047h6lta047h6lta047h6l03vdhu"
//       }
//     ],
//     "pkg_path": "gno.land/p/samcrew/teams/v0"
//   },
//   {
//     "type": "TeamUpdated",
//     "attrs": [
//       {
//         "key": "realm",
//         "value": "gno.land/r/samcrew/teams"
//       },
//       {
//         "key": "team",
//         "value": "1"
//       },
//       {
//         "key": "field",
//         "value": "open"
//       }
//     ],
//     "pkg_path": "gno.land/p/samcrew/teams/v0"
//   },
//   {
//     "type": "MemberJoined",
//     "attrs": [
//       {
//         "key": "realm",
//         "value": "gno.land/r/samcrew/teams"
//       },
//       {
//         "key": "team",
//         "value": "1"
//       },
//       {
//         "key": "player",
//         "value": "g1vfhkyh6lta047h6lta047h6lta047h6l03vdhu"
//       },
//       {
//         "key": "via",
//         "value": "join"
//       }
//     ],
//     "pkg_path": "gno.land/p/samcrew/teams/v0"
//   },
//   {
//     "type": "MemberLeft",
//     "attrs": [
//       {
//         "key": "realm",
//         "value": "gno.land/r/samcrew/teams"
//       },
//       {
//         "key": "team",
//         "value": "1"
//       },
//       {
//         "key": "player",
//         "value": "g1vfhkyh6lta047h6lta047h6lta047h6l03vdhu"
//       },
//       {
//         "key": "via",
//         "value": "leave"
//       }
//     ],
//     "pkg_path": "gno.land/p/samcrew/teams/v0"
//   },
//   {
//     "type": "MemberLeft",
//     "attrs": [
//       {
//         "key": "realm",
//         "value": "gno.land/r/samcrew/teams"
//       },
//       {
//         "key": "team",
//         "value": "1"
//       },
//       {
//         "key": "player",
//         "value": "g1v9kxjcm9ta047h6lta047h6lta047h6lzd40gh"
//       },
//       {
//         "key": "via",
//         "value": "leave"
//       }
//     ],
//     "pkg_path": "gno.land/p/samcrew/teams/v0"
//   },
//   {
//     "type": "TeamDeleted",
//     "attrs": [
//       {
//         "key": "realm",
//         "value": "gno.land/r/samcrew/teams"
//       },
//       {
//         "key": "team",
//         "value": "1"
//       },
//       {
//         "key": "name",
//         "value": "Evented"
//       }
//     ],
//     "pkg_path": "gno.land/p/samcrew/teams/v0"
//   }
// ]
