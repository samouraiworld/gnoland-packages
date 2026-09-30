// Package donate gives any address a donate page. A visitor sends coins with a
// short note, the coins reach the page's owner in the same transaction, and
// the page lists every donation.
package donate

import (
	"chain"
	"chain/banker"
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
	maxNote  = 280
	pageSize = 10
)

// amounts are the donate buttons, in ugnot.
var amounts = []int64{1_000_000, 5_000_000, 10_000_000}

type donation struct {
	donor  address
	amount chain.Coins
	note   string
	at     time.Time
}

type page struct {
	donations avl.Tree // seqid.ID.Binary() to *donation
	lastID    seqid.ID
	total     chain.Coins
}

var pages avl.Tree // owner address to *page

// Open creates the caller's donate page. Nobody can donate before it exists.
func Open(cur realm) {
	owner := cur.Previous().Address().String()
	if pages.Has(owner) {
		panic("your donate page is already open")
	}
	pages.Set(owner, &page{})
}

// Donate forwards every coin sent with the call to owner and records it with
// note, which may be empty. It returns the donation's number.
func Donate(cur realm, owner address, note string) uint64 {
	// Only a direct call puts the coins OriginSend reports in this realm.
	if !cur.Previous().IsUserCall() {
		panic("donate with a direct call")
	}
	p := mustPage(owner)
	note = mustText(note, maxNote)
	sent := unsafe.OriginSend()
	// Another denom is one anyone can issue, and it would sit in the total.
	if len(sent) != 1 || sent[0].Denom != "ugnot" || sent[0].Amount <= 0 {
		panic("send an amount of ugnot, and no other coin")
	}

	banker.NewBanker(banker.BankerTypeRealmSend, cur).SendCoins(cur.Address(), owner, sent)
	p.total = p.total.Add(sent)
	id := p.lastID.Next()
	p.donations.Set(id.Binary(), &donation{
		donor:  cur.Previous().Address(),
		amount: sent,
		note:   note,
		at:     time.Now(),
	})
	return uint64(id)
}

// RemoveNote clears the note of donation id on the caller's page. The amount
// stays in the list and in the total.
func RemoveNote(cur realm, id uint64) {
	p := mustPage(cur.Previous().Address())
	d, ok := p.donations.Get(seqid.ID(id).Binary()).(*donation)
	if !ok {
		panic("no such donation")
	}
	d.note = ""
}

func Render(path string) string {
	router := mux.NewRouter()
	router.HandleFunc("", renderHome)
	router.HandleFunc("{owner}", renderPage)
	return router.Render(path)
}

func renderHome(res *mux.ResponseWriter, req *mux.Request) {
	s := "# 💝 Donate\n\n"
	s += "A donate button for your profile. Visitors send coins with a short note, " +
		"and the coins reach you in the same transaction.\n\n"
	s += "1. " + md.Link("Open your donate page", txlink.Call("Open")) + ", once.\n"
	s += "2. Link it from your profile: `[💝 Donate](" + realmLink() + ":<your address>)`\n\n"
	s += md.Bold(strconv.Itoa(pages.Size())) + " pages open.\n"
	res.Write(s)
}

func renderPage(res *mux.ResponseWriter, req *mux.Request) {
	owner := address(req.GetVar("owner"))
	p, ok := pages.Get(owner.String()).(*page)
	if !ok {
		res.Write("# 💝 Donate\n\nThis address has no donate page yet. " +
			md.Link("Open yours", realmLink()) + ".\n")
		return
	}

	s := "# 💝 Donate to " + name(owner) + "\n\n"
	if p.donations.Size() > 0 {
		s += md.Bold(formatCoins(p.total)) + " received from " + count(p.donations.Size(), "donation") + ".\n\n"
	}
	buttons := make([]string, len(amounts))
	for i, a := range amounts {
		coin := chain.Coins{chain.NewCoin("ugnot", a)}
		url := txlink.NewLink("Donate").AddArgs("owner", owner.String()).SetSend(coin.String()).URL()
		buttons[i] = md.Bold(md.Link("💝 "+formatCoins(coin), url))
	}
	s += strings.Join(buttons, " · ") + "\n\n"
	s += "The next screen lets you change the amount and add a note.\n\n"

	s += "## Donations\n\n"
	if p.donations.Size() == 0 {
		s += "No donation yet. Be the first!\n"
		res.Write(s)
		return
	}
	pg := newPager(&p.donations).MustGetPageByPath(req.RawPath)
	for _, item := range pg.Items {
		d := item.Value.(*donation)
		id, _ := seqid.FromBinary(item.Key)
		s += "- " + md.Bold(name(d.donor)) + " gave " + md.Bold(formatCoins(d.amount)) +
			" on " + d.at.Format("2006-01-02")
		if d.note != "" {
			s += ": " + md.EscapeText(d.note)
		}
		s += " `#" + strconv.FormatUint(uint64(id), 10) + "`\n"
	}
	s += "\n" + pg.Picker(req.RawPath) + "\n"
	s += "The owner hides a note with " + md.Link("RemoveNote", txlink.Call("RemoveNote")) + " and its number.\n"
	res.Write(s)
}

// count writes n followed by noun, made plural unless n is 1.
func count(n int, noun string) string {
	if n != 1 {
		noun += "s"
	}
	return md.Bold(strconv.Itoa(n)) + " " + noun
}

func mustPage(owner address) *page {
	p, ok := pages.Get(owner.String()).(*page)
	if !ok {
		panic("this address has no donate page")
	}
	return p
}

// mustText trims s to single spaces and refuses it longer than max characters.
func mustText(s string, max int) string {
	s = strings.Join(strings.Fields(s), " ")
	if s != "" && md.EscapeText(s) == "" {
		panic("the text shows nothing")
	}
	if utf8.RuneCountInString(s) > max {
		panic("the text is longer than " + strconv.Itoa(max) + " characters")
	}
	return s
}

// formatCoins writes ugnot as GNOT, and any other denom as it is.
func formatCoins(cz chain.Coins) string {
	parts := make([]string, len(cz))
	for i, c := range cz {
		if c.Denom != "ugnot" {
			parts[i] = strconv.FormatInt(c.Amount, 10) + " " + md.EscapeText(c.Denom)
			continue
		}
		s := strconv.FormatInt(c.Amount/1_000_000, 10)
		if frac := c.Amount % 1_000_000; frac != 0 {
			// strconv has no zero padding, so the leading 1 keeps the fraction's zeros.
			s += "." + strings.TrimRight(strconv.FormatInt(frac+1_000_000, 10)[1:], "0")
		}
		parts[i] = s + " GNOT"
	}
	return strings.Join(parts, " + ")
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
