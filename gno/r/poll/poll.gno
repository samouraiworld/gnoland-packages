// Package poll gives any address one poll: the owner asks a question with a
// few choices, each visitor votes once, and the page shows the results.
package poll

import (
	"chain/runtime"
	"chain/runtime/unsafe"
	"strconv"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"

	"gno.land/p/moul/md/v0"
	"gno.land/p/moul/txlink/v0"
	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/mux/v0"
	"gno.land/r/sys/users"
)

const (
	maxQuestion = 280
	maxChoice   = 80
	maxChoices  = 10
	barWidth    = 10
)

type poll struct {
	question string
	choices  []string
	counts   []int
	votes    avl.Tree // voter address to the index of their choice
	closed   bool
	at       time.Time
}

var polls avl.Tree // owner address to *poll

// Create starts the caller's poll, replacing any earlier one and its votes.
// choices holds two to ten choices separated by semicolons.
func Create(cur realm, question, choices string) {
	question = mustText(question, maxQuestion)
	list := strings.Split(choices, ";")
	if len(list) < 2 || len(list) > maxChoices {
		panic("give between 2 and " + strconv.Itoa(maxChoices) + " choices, separated by ;")
	}
	for i, c := range list {
		if strings.TrimSpace(c) == "" {
			panic("choice " + strconv.Itoa(i+1) + " is empty: separate the choices with ;")
		}
		list[i] = mustText(c, maxChoice)
	}
	polls.Set(cur.Previous().Address().String(), &poll{
		question: question,
		choices:  list,
		counts:   make([]int, len(list)),
		at:       time.Now(),
	})
}

// Vote records the caller's vote for choice, numbered from 1, in owner's poll.
// Voting again moves the caller's vote.
func Vote(cur realm, owner address, choice int) {
	p := mustPoll(owner)
	if p.closed {
		panic("this poll is closed")
	}
	if choice < 1 || choice > len(p.choices) {
		panic("no such choice")
	}
	voter := cur.Previous().Address().String()
	if prev, ok := p.votes.Get(voter).(int); ok {
		p.counts[prev]--
	}
	p.votes.Set(voter, choice-1)
	p.counts[choice-1]++
}

// Close stops the caller's poll from taking votes. The results stay.
func Close(cur realm) {
	mustPoll(cur.Previous().Address()).closed = true
}

func Render(path string) string {
	router := mux.NewRouter()
	router.HandleFunc("", renderHome)
	router.HandleFunc("{owner}", renderPoll)
	return router.Render(path)
}

func renderHome(res *mux.ResponseWriter, req *mux.Request) {
	s := "# 📊 Poll\n\n"
	s += "A poll for your profile. Ask a question, give a few choices, and each visitor votes once.\n\n"
	s += "1. " + md.Link("Create your poll", txlink.Call("Create")) + ", choices separated by `;`. A new poll replaces the old one.\n"
	s += "2. Link it from your profile: `[📊 Poll](" + realmLink() + ":<your address>)`\n\n"
	s += md.Bold(strconv.Itoa(polls.Size())) + " polls.\n"
	res.Write(s)
}

func renderPoll(res *mux.ResponseWriter, req *mux.Request) {
	owner := address(req.GetVar("owner"))
	p, ok := polls.Get(owner.String()).(*poll)
	if !ok {
		res.Write("# 📊 Poll\n\nThis address has no poll yet. " + md.Link("Create yours", realmLink()) + ".\n")
		return
	}

	s := "# 📊 " + name(owner) + " asks\n\n"
	s += "## " + plain(p.question) + "\n\n"
	total := p.votes.Size()
	for i, c := range p.choices {
		s += md.Bold(strconv.Itoa(i+1)+". "+plain(c)) + " · " + votes(p.counts[i])
		if !p.closed {
			url := txlink.NewLink("Vote").AddArgs("owner", owner.String(), "choice", strconv.Itoa(i+1)).URL()
			s += " · " + md.Link("vote", url)
		}
		s += "\n\n" + bar(p.counts[i], total) + "\n\n"
	}
	s += votes(total) + " in all, since " + p.at.Format("2006-01-02") + "."
	if p.closed {
		s += " The poll is closed."
	} else {
		s += " Voting again moves your vote. The owner stops the votes with " + md.Link("Close", txlink.Call("Close")) + "."
	}
	res.Write(s + "\n")
}

func votes(n int) string {
	if n == 1 {
		return "1 vote"
	}
	return strconv.Itoa(n) + " votes"
}

// bar draws n out of total as barWidth blocks, with the percentage after.
func bar(n, total int) string {
	filled, pct := 0, 0
	if total > 0 {
		filled = (n*barWidth + total/2) / total
		pct = (n*100 + total/2) / total
	}
	return strings.Repeat("▰", filled) + strings.Repeat("▱", barWidth-filled) + " " + strconv.Itoa(pct) + "%"
}

func mustPoll(owner address) *poll {
	p, ok := polls.Get(owner.String()).(*poll)
	if !ok {
		panic("this address has no poll")
	}
	return p
}

// mustText trims s to single spaces and refuses it empty or longer than max
// characters.
func mustText(s string, max int) string {
	s = strings.Join(strings.Fields(s), " ")
	if !visible(s) {
		panic("the text is empty")
	}
	if utf8.RuneCountInString(s) > max {
		panic("the text is longer than " + strconv.Itoa(max) + " characters")
	}
	return s
}

// name links addr's profile, shown as its registered username or a short
// address.
func name(addr address) string {
	if u := users.ResolveAddress(addr); u != nil {
		return u.RenderLink("")
	}
	s := addr.String()
	return md.Link(s[:8]+"…"+s[len(s)-4:], "/u/"+s)
}

func realmLink() string {
	return strings.TrimPrefix(unsafe.CurrentRealm().PkgPath(), runtime.ChainDomain())
}

// plain escapes visitor text for the page, @ included, which gnoweb would
// otherwise turn into a profile link.
func plain(s string) string {
	return strings.ReplaceAll(md.EscapeText(s), "@", "\\@")
}

// visible reports whether s holds a character a reader can see.
func visible(s string) bool {
	for _, r := range s {
		switch r {
		case 0x115F, 0x1160, 0x2800, 0x3164, 0xFFA0: // letters and a symbol that draw nothing
			continue
		}
		if unicode.IsPrint(r) && !unicode.IsSpace(r) {
			return true
		}
	}
	return false
}
