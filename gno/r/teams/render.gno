package teams

import (
	"strconv"
	"strings"
	"time"

	"gno.land/p/moul/md/v0"
	"gno.land/p/moul/txlink/v0"
	"gno.land/p/nt/avl/pager/v0"
	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/mux/v0"
	"gno.land/p/nt/seqid/v0"
	"gno.land/p/nt/ufmt/v0"
	"gno.land/r/sys/users"
)

const (
	realmLink = "/r/samcrew/teams"
	pageSize  = 20
)

// palette gives each team a coloured dot, picked by its id.
var palette = []string{"🔴", "🔵", "🟢", "🟡", "🟣", "🟠", "🟤", "⚫"}

var router *mux.Router

func init() {
	router = mux.NewRouter()
	router.HandleFunc("", renderHome)
	router.HandleFunc("team/{id}", renderTeam)
	router.HandleFunc("player/{address}", renderPlayer)
}

func Render(path string) string {
	return router.Render(path)
}

func renderHome(res *mux.ResponseWriter, req *mux.Request) {
	s := "# ⚔️ Teams\n\n"
	s += "Build a team with your friends and bring it into any game on gno.land.\n\n"
	s += md.Columns([]string{
		stat(teams.Size(), "🛡️ teams"),
		stat(players.Size(), "🧑‍🤝‍🧑 players"),
		md.Bold(md.Link("➕ Create a team", txlink.Call("CreateTeam"))) + "\n\nPick a name, open it to all or keep it invite only.",
	}, false)
	s += "\n> 🔎 Your teams and invites are at `" + realmLink + ":player/<your address>`\n\n"
	s += "---\n\n"

	s += ufmt.Sprintf("## 🛡️ All teams (%d)\n\n", teams.Size())
	if teams.Size() == 0 {
		s += "No team yet. Create the first one!\n\n"
	} else {
		page := pagerFor(&teams, "page").MustGetPageByPath(req.RawPath)
		s += "| Team | Owner | Members | Joining | |\n"
		s += "| --- | --- | ---: | --- | --- |\n"
		for _, item := range page.Items {
			t := item.Value.(*team)
			join := ""
			if t.open {
				join = md.Link("🙋 Join", txlink.Call("Join", "id", idText(t.id)))
			}
			s += ufmt.Sprintf("| %s | %s | %d | %s | %s |\n",
				teamLink(t), playerLink(t.owner), t.members.Size(), joining(t), join)
		}
		s += "\n" + page.Picker(req.RawPath) + "\n\n"
	}
	s += "---\n\n"

	s += "## 🎮 Use teams in your game\n\n"
	s += "Import the realm and read the teams your players belong to.\n\n"
	s += md.LanguageCodeBlock("go", `import "gno.land/r/samcrew/teams"

if !teams.IsMember(teamID, player) {
	panic("join the team first")
}
for _, id := range teams.TeamsOf(player) {
	println(teams.Name(id))
}`) + "\n"
	res.Write(s)
}

func renderTeam(res *mux.ResponseWriter, req *mux.Request) {
	id, err := strconv.ParseUint(req.GetVar("id"), 10, 64)
	t := lookup(id)
	if err != nil || t == nil {
		res.Write(notFound("Team not found"))
		return
	}
	ids := idText(t.id)

	s := nav()
	s += "# " + chip(t.id) + " " + md.EscapeText(t.name) + "\n\n"
	if t.description == "" {
		s += "*No description yet.*\n\n"
	} else {
		s += md.Blockquote(md.EscapeText(t.description)) + "\n"
	}
	s += "📅 Created " + date(t.createdAt) + "\n\n"
	s += md.Columns([]string{
		"**👑 Owner**\n\n" + playerLink(t.owner),
		"**👥 Members**\n\n" + strconv.Itoa(t.members.Size()),
		"**🚪 Joining**\n\n" + joining(t),
	}, false)
	s += "\n---\n\n"

	s += "## ⚡ Actions\n\n"
	who := ", once the owner invited you"
	if t.open {
		who = ", open to everyone"
	}
	s += "- " + md.Link("🙋 Join this team", txlink.Call("Join", "id", ids)) + who + "\n"
	s += "- " + md.Link("🚪 Leave the team", txlink.Call("Leave", "id", ids)) + "\n\n"
	s += "### 👑 Owner tools\n\n" + md.BulletList([]string{
		md.Link("✉️ Invite a player", txlink.Call("Invite", "id", ids)),
		md.Link("➕ Add a player directly", txlink.Call("AddMember", "id", ids)),
		md.Link("➖ Remove a player", txlink.Call("RemoveMember", "id", ids)),
		md.Link(openToggleLabel(t), txlink.Call("SetOpen", "id", ids, "open", strconv.FormatBool(!t.open))),
		md.Link("✏️ Edit the description", txlink.Call("SetDescription", "id", ids)),
		md.Link("🤝 Hand over ownership", txlink.Call("TransferOwnership", "id", ids)),
	}) + "\n"
	s += "---\n\n"

	s += ufmt.Sprintf("## 👥 Members (%d)\n\n", t.members.Size())
	page := pagerFor(t.members, "page").MustGetPageByPath(req.RawPath)
	s += "| Player | Role | Joined |\n"
	s += "| --- | --- | --- |\n"
	for _, item := range page.Items {
		addr := address(item.Key)
		s += ufmt.Sprintf("| %s | %s | %s |\n", playerLink(addr), role(t, addr), date(item.Value.(time.Time)))
	}
	s += "\n" + page.Picker(req.RawPath) + "\n\n"

	if t.invites.Size() > 0 {
		s += "---\n\n"
		s += ufmt.Sprintf("## ✉️ Pending invites (%d)\n\n", t.invites.Size())
		s += "| Player | Invited | |\n"
		s += "| --- | --- | --- |\n"
		page := pagerFor(t.invites, "invites").MustGetPageByPath(req.RawPath)
		for _, item := range page.Items {
			cancel := md.Link("❌ Cancel", txlink.Call("CancelInvite", "id", ids, "player", item.Key))
			s += ufmt.Sprintf("| %s | %s | %s |\n", playerLink(address(item.Key)), date(item.Value.(time.Time)), cancel)
		}
		s += "\n" + page.Picker(req.RawPath) + "\n\n"
	}
	res.Write(s)
}

func renderPlayer(res *mux.ResponseWriter, req *mux.Request) {
	addr := address(strings.ToLower(req.GetVar("address")))
	if !addr.IsValid() {
		res.Write(notFound("Not a valid address"))
		return
	}

	s := nav()
	s += "# 🧑 " + playerLink(addr) + "\n\n"

	teamIDs := indexTree(&players, addr)
	s += ufmt.Sprintf("## 🛡️ Teams (%d)\n\n", teamIDs.Size())
	if teamIDs.Size() == 0 {
		s += "Not in any team yet. " + md.Link("Browse the teams", realmLink) + " or create one.\n\n"
	} else {
		page := pagerFor(teamIDs, "page").MustGetPageByPath(req.RawPath)
		s += "| Team | Role | Members |\n"
		s += "| --- | --- | ---: |\n"
		for _, item := range page.Items {
			t := teams.Get(item.Key).(*team)
			s += ufmt.Sprintf("| %s | %s | %d |\n", teamLink(t), role(t, addr), t.members.Size())
		}
		s += "\n" + page.Picker(req.RawPath) + "\n\n"
	}

	inviteIDs := indexTree(&invited, addr)
	if inviteIDs.Size() > 0 {
		page := pagerFor(inviteIDs, "invites").MustGetPageByPath(req.RawPath)
		s += "---\n\n"
		s += ufmt.Sprintf("## ✉️ Invites (%d)\n\n", inviteIDs.Size())
		s += "| Team | | |\n"
		s += "| --- | --- | --- |\n"
		for _, item := range page.Items {
			t := teams.Get(item.Key).(*team)
			ids := idText(t.id)
			s += ufmt.Sprintf("| %s | %s | %s |\n", teamLink(t),
				md.Link("✅ Accept", txlink.Call("Join", "id", ids)),
				md.Link("❌ Decline", txlink.Call("CancelInvite", "id", ids, "player", addr.String())))
		}
		s += "\n" + page.Picker(req.RawPath) + "\n\n"
	}
	res.Write(s)
}

func nav() string {
	return md.Link("⬅️ All teams", realmLink) + "\n\n"
}

func notFound(msg string) string {
	return nav() + "# 🤷 " + msg + "\n"
}

func stat(n int, label string) string {
	return md.Bold(strconv.Itoa(n)) + "\n\n" + label
}

// pagerFor reads the page number from param, so each table on a page keeps
// its own page.
func pagerFor(tree *avl.Tree, param string) *pager.Pager {
	p := pager.NewPager(tree, pageSize, false)
	p.PageQueryParam = param
	return p
}

func role(t *team, addr address) string {
	if addr == t.owner {
		return "👑 Owner"
	}
	return "🧑 Member"
}

func joining(t *team) string {
	if t.open {
		return "🔓 Open"
	}
	return "✉️ Invite only"
}

func openToggleLabel(t *team) string {
	if t.open {
		return "🔒 Make it invite only"
	}
	return "🔓 Open it to everyone"
}

func teamLink(t *team) string {
	return chip(t.id) + " " + md.Link(t.name, realmLink+":team/"+idText(t.id))
}

// playerLink shows the registered username when there is one.
func playerLink(addr address) string {
	s := addr.String()
	name := s
	if u := users.ResolveAddress(addr); u != nil {
		name = "@" + u.Name()
	} else if len(s) > 13 {
		name = s[:7] + "…" + s[len(s)-4:]
	}
	return md.Link(name, realmLink+":player/"+s)
}

func chip(id seqid.ID) string {
	return palette[int(id)%len(palette)]
}

func idText(id seqid.ID) string {
	return strconv.FormatUint(uint64(id), 10)
}

func date(t time.Time) string {
	return t.UTC().Format("2006-01-02")
}
