// Package guestbook gives any address a guestbook. Each visitor leaves one
// short message, and the owner removes any of them.
package guestbook

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
	"gno.land/p/nt/avl/pager/v0"
	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/mux/v0"
	"gno.land/p/nt/seqid/v0"
	"gno.land/r/sys/users"
)

const (
	maxMessage = 280
	pageSize   = 10
)

type entry struct {
	signer  address
	message string
	at      time.Time
}

type book struct {
	entries  avl.Tree // seqid.ID.Binary() to *entry
	bySigner avl.Tree // signer address to the key of their entry
	lastID   seqid.ID
}

var books avl.Tree // owner address to *book

// Open creates the caller's guestbook. Nobody can sign before it exists.
func Open(cur realm) {
	owner := cur.Previous().Address().String()
	if books.Has(owner) {
		panic("your guestbook is already open")
	}
	books.Set(owner, &book{})
}

// Sign leaves the caller's message in owner's guestbook. Signing again
// replaces the caller's earlier message and moves it to the top.
func Sign(cur realm, owner address, message string) {
	b := mustBook(owner)
	message = mustText(message, maxMessage)
	signer := cur.Previous().Address()
	b.remove(signer)
	key := b.lastID.Next().Binary()
	b.entries.Set(key, &entry{signer: signer, message: message, at: time.Now()})
	b.bySigner.Set(signer.String(), key)
}

// Remove deletes signer's message from the caller's guestbook.
func Remove(cur realm, signer address) {
	if !mustBook(cur.Previous().Address()).remove(signer) {
		panic("no message from this address")
	}
}

func (b *book) remove(signer address) bool {
	key, ok := b.bySigner.Remove(signer.String())
	if ok {
		b.entries.Remove(key.(string))
	}
	return ok
}

func Render(path string) string {
	router := mux.NewRouter()
	router.HandleFunc("", renderHome)
	router.HandleFunc("{owner}", renderBook)
	return router.Render(path)
}

func renderHome(res *mux.ResponseWriter, req *mux.Request) {
	s := "# ✍️ Guestbook\n\n"
	s += "A guestbook for your profile. Each visitor leaves one short message.\n\n"
	s += "1. " + md.Link("Open your guestbook", txlink.Call("Open")) + ", once.\n"
	s += "2. Link it from your profile: `[✍️ Guestbook](" + realmLink() + ":<your address>)`\n\n"
	s += md.Bold(strconv.Itoa(books.Size())) + " guestbooks open.\n"
	res.Write(s)
}

func renderBook(res *mux.ResponseWriter, req *mux.Request) {
	owner := address(req.GetVar("owner"))
	b, ok := books.Get(owner.String()).(*book)
	if !ok {
		res.Write("# ✍️ Guestbook\n\nThis address has no guestbook yet. " +
			md.Link("Open yours", realmLink()) + ".\n")
		return
	}

	s := "# ✍️ Guestbook of " + name(owner) + "\n\n"
	s += md.Bold(md.Link("✍️ Sign it", txlink.NewLink("Sign").AddArgs("owner", owner.String()).URL())) +
		" · signing again replaces your message.\n\n"
	s += "## Messages (" + strconv.Itoa(b.entries.Size()) + ")\n\n"
	if b.entries.Size() == 0 {
		s += "No message yet. Be the first!\n"
		res.Write(s)
		return
	}
	pg, at := pageOf(&b.entries, req.RawPath)
	for _, item := range pg.Items {
		e := item.Value.(*entry)
		remove := txlink.NewLink("Remove").AddArgs("signer", e.signer.String()).URL()
		s += "- " + md.Bold(name(e.signer)) + " on " + e.at.Format("2006-01-02") +
			": " + plain(e.message) + " · " + md.Link("remove", remove) + "\n"
	}
	s += "\n" + pg.Picker(at) + "\n"
	s += "Only the owner can remove a message.\n"
	res.Write(s)
}

func mustBook(owner address) *book {
	b, ok := books.Get(owner.String()).(*book)
	if !ok {
		panic("this address has no guestbook")
	}
	return b
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

// pageOf returns the page of tree the path's query asks for, newest first,
// and the path to build page links from. A query that does not parse shows
// the first page.
func pageOf(tree *avl.Tree, rawPath string) (*pager.Page, string) {
	p := pager.NewPager(tree, pageSize, true) // ids grow, so reversed is newest first
	p.SizeQueryParam = ""                     // a link cannot raise the page size
	if pg, err := p.GetPageByPath(rawPath); err == nil {
		return pg, rawPath
	}
	return p.GetPage(1), ""
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
