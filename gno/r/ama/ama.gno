// Package ama gives any address an ask-me-anything page. Visitors ask
// questions, and the owner's answers are shown under them.
package ama

import (
	"chain/runtime"
	"chain/runtime/unsafe"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"gno.land/p/moul/md/v0"
	"gno.land/p/moul/txlink/v0"
	"gno.land/p/nt/avl/pager/v0"
	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/mux/v0"
	"gno.land/p/nt/seqid/v0"
	"gno.land/r/sys/users"
)

const (
	maxQuestion = 280
	maxAnswer   = 1000
	pageSize    = 10
)

type question struct {
	asker  address
	text   string
	answer string
	at     time.Time
}

type page struct {
	answered avl.Tree // seqid.ID.Binary() to *question
	waiting  avl.Tree // seqid.ID.Binary() to *question
	byAsker  avl.Tree // askers with a question waiting, to true
	lastID   seqid.ID
}

var pages avl.Tree // owner address to *page

// Open creates the caller's page. Nobody can ask before it exists.
func Open(cur realm) {
	owner := cur.Previous().Address().String()
	if pages.Has(owner) {
		panic("your page is already open")
	}
	pages.Set(owner, &page{})
}

// Ask puts the caller's question on owner's waiting list and returns its
// number. A visitor has one question waiting at a time.
func Ask(cur realm, owner address, text string) uint64 {
	p := mustPage(owner)
	text = mustText(text, maxQuestion)
	asker := cur.Previous().Address()
	if p.byAsker.Has(asker.String()) {
		panic("your last question is still waiting for an answer")
	}
	id := p.lastID.Next()
	p.waiting.Set(id.Binary(), &question{asker: asker, text: text, at: time.Now()})
	p.byAsker.Set(asker.String(), true)
	return uint64(id)
}

// Answer publishes the caller's answer to question id on their page, or
// replaces an answer already published.
func Answer(cur realm, id uint64, answer string) {
	p := mustPage(cur.Previous().Address())
	answer = mustText(answer, maxAnswer)
	key := seqid.ID(id).Binary()
	if q, ok := p.answered.Get(key).(*question); ok {
		q.answer = answer
		return
	}
	q := p.take(key)
	q.answer = answer
	p.answered.Set(key, q)
}

// Dismiss deletes question id from the caller's page, answered or not.
func Dismiss(cur realm, id uint64) {
	p := mustPage(cur.Previous().Address())
	key := seqid.ID(id).Binary()
	if _, ok := p.answered.Remove(key); !ok {
		p.take(key)
	}
}

// take removes question key from the waiting list, which frees its asker to
// ask again.
func (p *page) take(key string) *question {
	v, ok := p.waiting.Remove(key)
	if !ok {
		panic("no such question")
	}
	q := v.(*question)
	p.byAsker.Remove(q.asker.String())
	return q
}

func Render(path string) string {
	router := mux.NewRouter()
	router.HandleFunc("", renderHome)
	router.HandleFunc("{owner}", renderAnswered)
	router.HandleFunc("{owner}/waiting", renderWaiting)
	return router.Render(path)
}

func renderHome(res *mux.ResponseWriter, req *mux.Request) {
	s := "# 🙋 Ask me anything\n\n"
	s += "A question box for your profile. Visitors ask, and your answers are shown under their questions.\n\n"
	s += "1. " + md.Link("Open your page", txlink.Call("Open")) + ", once.\n"
	s += "2. Link it from your profile: `[🙋 Ask me anything](" + realmLink() + ":<your address>)`\n\n"
	s += md.Bold(strconv.Itoa(pages.Size())) + " pages open.\n"
	res.Write(s)
}

func renderAnswered(res *mux.ResponseWriter, req *mux.Request) {
	owner, p := pageFor(res, req)
	if p == nil {
		return
	}
	s := "# 🙋 Ask " + name(owner) + " anything\n\n"
	s += md.Bold(md.Link("🙋 Ask a question", txlink.NewLink("Ask").AddArgs("owner", owner.String()).URL())) +
		" · " + md.Link(strconv.Itoa(p.waiting.Size())+" waiting", realmLink()+":"+owner.String()+"/waiting") + "\n\n"
	s += "## Answered (" + strconv.Itoa(p.answered.Size()) + ")\n\n"
	if p.answered.Size() == 0 {
		s += "No answer yet.\n"
		res.Write(s)
		return
	}
	pg := newPager(&p.answered).MustGetPageByPath(req.RawPath)
	for _, item := range pg.Items {
		q := item.Value.(*question)
		s += "### " + md.EscapeText(q.text) + "\n\n"
		id := number(item.Key)
		s += "_" + name(q.asker) + " asked on " + q.at.Format("2006-01-02") + "_ `#" + id + "`\n\n"
		s += md.EscapeText(q.answer) + "\n\n"
		s += md.Link("answer again", txlink.NewLink("Answer").AddArgs("id", id).URL()) + " · " +
			md.Link("dismiss", txlink.NewLink("Dismiss").AddArgs("id", id).URL()) + "\n\n"
	}
	s += pg.Picker(req.RawPath) + "\n"
	s += "Only the owner can answer or dismiss.\n"
	res.Write(s)
}

func renderWaiting(res *mux.ResponseWriter, req *mux.Request) {
	owner, p := pageFor(res, req)
	if p == nil {
		return
	}
	s := "# 🙋 Waiting for " + name(owner) + "\n\n"
	s += md.Link("← Answered questions", realmLink()+":"+owner.String()) + "\n\n"
	if p.waiting.Size() == 0 {
		s += "Nothing waiting.\n"
		res.Write(s)
		return
	}
	pg := newPager(&p.waiting).MustGetPageByPath(req.RawPath)
	for _, item := range pg.Items {
		q := item.Value.(*question)
		id := number(item.Key)
		s += "- " + md.EscapeText(q.text) + " · " + name(q.asker) + " · " +
			md.Link("answer", txlink.NewLink("Answer").AddArgs("id", id).URL()) + " · " +
			md.Link("dismiss", txlink.NewLink("Dismiss").AddArgs("id", id).URL()) + "\n"
	}
	s += "\n" + pg.Picker(req.RawPath) + "\n"
	s += "Only the owner can answer or dismiss.\n"
	res.Write(s)
}

// number turns a tree key back into the question number a visitor types.
func number(key string) string {
	id, _ := seqid.FromBinary(key)
	return strconv.FormatUint(uint64(id), 10)
}

// pageFor returns the owner the path names and their page, or writes a
// missing page and returns nil.
func pageFor(res *mux.ResponseWriter, req *mux.Request) (address, *page) {
	owner := address(req.GetVar("owner"))
	p, ok := pages.Get(owner.String()).(*page)
	if !ok {
		res.Write("# 🙋 Ask me anything\n\nThis address has no page yet. " +
			md.Link("Open yours", realmLink()) + ".\n")
		return owner, nil
	}
	return owner, p
}

func mustPage(owner address) *page {
	p, ok := pages.Get(owner.String()).(*page)
	if !ok {
		panic("this address has no ask-me-anything page")
	}
	return p
}

// mustText trims s to single spaces and refuses it empty or longer than max
// characters.
func mustText(s string, max int) string {
	s = strings.Join(strings.Fields(s), " ")
	// EscapeText drops zero-width characters, which Fields keeps.
	if s == "" || md.EscapeText(s) == "" {
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

func newPager(tree *avl.Tree) *pager.Pager {
	p := pager.NewPager(tree, pageSize, true) // ids grow, so reversed is newest first
	p.SizeQueryParam = ""                     // a link cannot raise the page size
	return p
}
