// Package connect4 is a staked Connect 4 game. A creator posts an offer with
// a ugnot stake; anyone (or a named opponent) accepts with the same stake;
// the winner takes the pot minus a flat house fee.
//
// The first mover is picked by a two-sided commit-reveal. The creator offers
// with sha256(passphrase), the acceptor accepts with sha256(seed). Then the
// creator reveals the passphrase (Reveal) and the acceptor the seed
// (RevealSeed), each within 90s, and the first mover is drawn from both. When
// a player commits, the other side's secret is still hidden, so neither can
// grind for an outcome, and once its secret is revealed nobody can change it;
// the only way out is to not reveal, which forfeits. Watching a pending Accept
// tells the creator nothing either, so it cannot cancel unfavourable games.
// A revealed secret is public: reusing one hands the other side the draw, so
// clients must generate a fresh secret for every game. The realm does not
// track used commitments, as that costs every game storage forever.
//
// Calls signed by an account session key (Quick play) may only Play, Reveal,
// RevealSeed, ClaimTimeout and Cancel: a stolen session key must not resign
// games, move stakes or act as the owner.
//
// Every move has a 90s clock measured in block time. Nothing on-chain fires
// by itself, so an expired clock is settled by anyone calling ClaimTimeout:
// whoever did not reveal in time forfeits, a game whose first mover never
// moved is void and both stakes are refunded, otherwise the player who ran
// out of time forfeits.
package connect4

import (
	"chain"
	"chain/banker"
	"chain/runtime"
	"chain/runtime/unsafe"
	"crypto/sha256"
	"encoding/hex"
	"strconv"
	"strings"
	"time"

	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/ownable/v0"
)

const (
	moveTimeout = 90 * time.Second
	maxOfferTTL = 60 // minutes
	feeCap      = minStake / 2
	minStake    = 1_000_000 // ugnot
	denom       = "ugnot"
)

type Status int

const (
	Open Status = iota
	Playing
	Won
	Draw
	Void
	Cancelled
)

func (s Status) String() string {
	return [...]string{"open", "playing", "won", "draw", "void", "cancelled"}[s]
}

type Game struct {
	ID        int
	Creator   address
	Opponent  address // optional; if set, only this address may accept
	Acceptor  address
	Stake     int64 // ugnot, per player
	Fee       int64 // ugnot house fee, fixed at offer time
	ExpiresAt int64 // unix nanoseconds: a time.Time field is a separate stored object
	// Commitment is the lowercase hex sha256 of the creator's passphrase;
	// SeedCommitment that of the acceptor's seed, given with Accept.
	Commitment     string
	SeedCommitment string
	// Passphrase is set by Reveal; the draw waits for RevealSeed.
	Passphrase string
	Revealed   bool

	Board    board
	Turn     byte // 0 = awaiting the reveals, 1 = creator, 2 = acceptor
	Moves    int
	LastCol  int // column and row of the last piece dropped, valid if Moves > 0
	LastRow  int
	LastMove int64 // unix nanoseconds
	Status   Status
	Winner   address
}

type Stats struct {
	Games, Wins, Draws int
	GnotWon            int64 // total net ugnot won: the opponent's stake minus the fee
}

var (
	games         []*book  // every game ever offered, by id: see store
	active        avl.Tree // key(id) -> *Game, only Open and Playing
	stats         avl.Tree // address -> Stats (a value: a pointer would be one more stored object)
	nextID        int
	fee           int64 = 100_000 // ugnot per decisive game
	feesCollected int64
	owner         *ownable.Ownable // the deployer; nil (no owner) if deployed some other way
	pendingOwner  address          // set by TransferOwnership, made owner by AcceptOwnership
	// testSession makes tests see every call as session-signed (no test hook sets one).
	testSession bool
)

// The deployer owns the realm: deploy from the multisig that should own it.
func init(cur realm) {
	if cur.Previous().IsUserCall() {
		owner = ownable.NewWithAddress(cur.Previous().Address())
	}
}

// Offer posts a game open for validFor minutes. The stake is the ugnot sent
// with the call. A non-empty opponent makes the offer private. commitment is
// the lowercase hex sha256 of a secret passphrase, revealed after Accept.
func Offer(cur realm, opponent address, validFor int, commitment string, maxFee int64) int {
	noSession("Offer")
	stake := received(cur)
	caller := cur.Previous().Address()
	if opponent == caller {
		panic("cannot challenge yourself")
	}
	if errs := validateOffer(stake, validFor, opponent, commitment); len(errs) > 0 {
		panic(errs[0])
	}
	// The fee is snapshotted into the game: maxFee is the most the creator
	// agreed to, so a fee raised while the offer was in flight is refused.
	if fee > maxFee {
		panic("the house fee is " + gnot(fee) + ", above your maximum of " + gnot(maxFee))
	}
	nextID++
	g := &Game{
		ID:        nextID,
		Creator:   caller,
		Opponent:  opponent,
		Stake:     stake,
		Fee:       fee,
		ExpiresAt: time.Now().Add(time.Duration(validFor) * time.Minute).UnixNano(),

		Commitment: commitment,
	}
	store(g)
	active.Set(key(g.ID), g)
	return g.ID
}

// validateOffer returns every rule an offer breaks. Offer panics with the
// first; the "new" page lists them all before anyone signs.
func validateOffer(stake int64, validFor int, opponent address, commitment string) []string {
	var errs []string
	if stake < minStake {
		errs = append(errs, "stake below minimum of "+gnot(minStake))
	}
	if stake <= fee {
		errs = append(errs, "stake must exceed the house fee of "+gnot(fee))
	}
	if validFor < 1 || validFor > maxOfferTTL {
		errs = append(errs, "validFor must be between 1 and 60 minutes")
	}
	// IsValid also accepts other spellings of an address, which would never
	// match the canonical one Accept compares against.
	if opponent != "" && !canonical(opponent) {
		errs = append(errs, "invalid opponent address (use the lower-case g1… form)")
	}
	if !isHexSHA256(commitment) {
		errs = append(errs, "commitment must be 64 lowercase hex chars (sha256 of your passphrase)")
	}
	return errs
}

// Accept joins an open offer by sending exactly its stake. seedCommitment is
// the lowercase hex sha256 of a secret seed, revealed after the creator's
// passphrase. The creator then has 90s to Reveal.
func Accept(cur realm, id int, seedCommitment string) {
	noSession("Accept")
	stake := received(cur)
	caller := cur.Previous().Address()
	g := mustGet(id)
	if g.Status != Open {
		panic("game is not open")
	}
	if !time.Now().Before(g.expires()) {
		panic("offer expired")
	}
	if caller == g.Creator {
		panic("cannot accept your own offer")
	}
	if g.Opponent != "" && caller != g.Opponent {
		panic("offer is reserved for another player")
	}
	if stake != g.Stake {
		panic("must send exactly " + strconv.FormatInt(g.Stake, 10) + denom)
	}
	if !isHexSHA256(seedCommitment) {
		panic("seedCommitment must be 64 lowercase hex chars (sha256 of your seed)")
	}
	g.Acceptor = caller
	g.SeedCommitment = seedCommitment
	g.Status = Playing
	g.LastMove = time.Now().UnixNano() // Turn stays 0 until Reveal
}

// Reveal discloses the creator's passphrase. It must come within 90s of
// Accept; the acceptor then has 90s to RevealSeed.
func Reveal(cur realm, id int, passphrase string) {
	noCoins()
	g := mustGet(id)
	if g.Status != Playing || g.Turn != 0 || g.Revealed {
		panic("game is not awaiting the creator's reveal")
	}
	if cur.Previous().Address() != g.Creator {
		panic("only the creator can reveal")
	}
	if time.Now().After(g.deadline()) {
		panic("reveal clock ran out")
	}
	if len(passphrase) > 128 {
		panic("passphrase longer than 128 bytes")
	}
	if sha256Hex(passphrase) != g.Commitment {
		panic("passphrase does not match the commitment")
	}
	g.Passphrase = passphrase
	g.Revealed = true
	g.LastMove = time.Now().UnixNano()
}

// RevealSeed discloses the acceptor's seed, which with the creator's
// passphrase picks the first mover. It must come within 90s of Reveal.
func RevealSeed(cur realm, id int, seed string) {
	noCoins()
	g := mustGet(id)
	if g.Status != Playing || g.Turn != 0 || !g.Revealed {
		panic("game is not awaiting the acceptor's seed")
	}
	if cur.Previous().Address() != g.Acceptor {
		panic("only the acceptor can reveal the seed")
	}
	if time.Now().After(g.deadline()) {
		panic("reveal clock ran out")
	}
	if sha256Hex(seed) != g.SeedCommitment {
		panic("seed does not match the commitment")
	}
	g.Turn = firstMover(g.Passphrase, seed, g)
	g.LastMove = time.Now().UnixNano()
}

// firstMover draws 1 (creator) or 2 (acceptor) from both secrets.
func firstMover(passphrase, seed string, g *Game) byte {
	h := sha256.Sum256([]byte(strings.Join([]string{
		passphrase, seed, strconv.Itoa(g.ID), g.Creator.String(), g.Acceptor.String(),
	}, "|")))
	return 1 + h[0]&1
}

// Play drops a piece in column (1-7). move is the game's move count the
// player saw (Moves before this piece): a resent or delayed move that the game
// has moved past is refused instead of being played on a later turn.
func Play(cur realm, id, column, move int) {
	noCoins()
	g := mustGet(id)
	if g.Status != Playing {
		panic("game is not in progress")
	}
	if g.Turn == 0 {
		panic("waiting for the creator to reveal")
	}
	if cur.Previous().Address() != g.player(g.Turn) {
		panic("not your turn")
	}
	if time.Now().After(g.deadline()) {
		panic("move clock ran out")
	}
	if move != g.Moves {
		panic("stale move: the game is at move " + strconv.Itoa(g.Moves))
	}
	if column < 1 || column > cols {
		panic("column must be between 1 and 7")
	}
	r := g.Board.drop(column-1, g.Turn)
	if r < 0 {
		panic("column is full")
	}
	g.Moves++
	g.LastCol, g.LastRow = column-1, r
	switch {
	case g.Board.wins(column-1, r):
		settleWin(cur, g, g.player(g.Turn))
	case g.Moves == cols*rows:
		settleDraw(cur, g)
	default:
		g.Turn = 3 - g.Turn
		g.LastMove = time.Now().UnixNano()
	}
}

// ClaimTimeout settles a game whose move clock ran out. Anyone may call it.
func ClaimTimeout(cur realm, id int) {
	noCoins()
	g := mustGet(id)
	if g.Status != Playing {
		panic("game is not in progress")
	}
	if !time.Now().After(g.deadline()) {
		panic("move clock has not run out")
	}
	if g.Turn == 0 { // whoever did not reveal in time forfeits
		if g.Revealed {
			settleWin(cur, g, g.Creator)
		} else {
			settleWin(cur, g, g.Acceptor)
		}
		return
	}
	if g.Moves == 0 {
		settleVoid(cur, g)
		return
	}
	settleWin(cur, g, g.player(3-g.Turn))
}

// Resign concedes a game in progress.
func Resign(cur realm, id int) {
	noCoins()
	noSession("Resign")
	g := mustGet(id)
	if g.Status != Playing {
		panic("game is not in progress")
	}
	switch cur.Previous().Address() {
	case g.Creator:
		settleWin(cur, g, g.Acceptor)
	case g.Acceptor:
		settleWin(cur, g, g.Creator)
	default:
		panic("not a player in this game")
	}
}

// Cancel withdraws an open offer and refunds the creator. The creator may
// cancel at any time; anyone may once the offer has expired.
func Cancel(cur realm, id int) {
	noCoins()
	g := mustGet(id)
	if g.Status != Open {
		panic("game is not open")
	}
	if cur.Previous().Address() != g.Creator && time.Now().Before(g.expires()) {
		panic("only the creator can cancel an unexpired offer")
	}
	finish(g, Cancelled)
	send(cur, g.Creator, g.Stake)
}

// Renew reopens the caller's open offer for validFor minutes from now,
// expired or not. It keeps the stake, fee, opponent and commitment (still
// secret, as nobody accepted), so it costs no new storage where a fresh
// Offer would.
func Renew(cur realm, id, validFor int) {
	noCoins()
	noSession("Renew")
	g := mustGet(id)
	if g.Status != Open {
		panic("game is not open")
	}
	if cur.Previous().Address() != g.Creator {
		panic("only the creator can renew an offer")
	}
	if validFor < 1 || validFor > maxOfferTTL {
		panic("validFor must be between 1 and 60 minutes")
	}
	g.ExpiresAt = time.Now().Add(time.Duration(validFor) * time.Minute).UnixNano()
}

// SetFee changes the flat house fee, in ugnot, for new offers. Games already
// offered keep the fee they were created with.
func SetFee(cur realm, amount int64) {
	noCoins()
	noSession("SetFee")
	owner.AssertOwnedBy(cur.Previous().Address())
	// Capped so the owner can't raise the fee to take most of a stake by
	// changing it just before an offer lands.
	if amount < 0 || amount > feeCap {
		panic("fee must be between 0 and " + gnot(feeCap))
	}
	fee = amount
}

// WithdrawFees sends all collected fees to to.
func WithdrawFees(cur realm, to address) {
	noCoins()
	noSession("WithdrawFees")
	owner.AssertOwnedBy(cur.Previous().Address())
	amount := feesCollected
	feesCollected = 0
	send(cur, to, amount)
}

// TransferOwnership names the next owner, who becomes owner by calling
// AcceptOwnership. Two steps, so a mistyped or non-canonical address can
// never strand ownership (and the fees): only an address that signs can
// accept, and it is recorded as it signs.
func TransferOwnership(cur realm, newOwner address) {
	noCoins()
	noSession("TransferOwnership")
	owner.AssertOwnedBy(cur.Previous().Address())
	if !canonical(newOwner) {
		panic("invalid address (use the lower-case g1… form)")
	}
	pendingOwner = newOwner
}

// AcceptOwnership completes a TransferOwnership; only the named address may call it.
func AcceptOwnership(cur realm) {
	noCoins()
	noSession("AcceptOwnership")
	caller := cur.Previous().Address()
	if pendingOwner == "" || caller != pendingOwner {
		panic("no ownership transfer pending for this address")
	}
	owner = ownable.NewWithAddress(caller)
	pendingOwner = ""
}

// received returns the ugnot sent with a direct user call. OriginSend only
// describes a real payment to this realm when the caller is an EOA using
// maketx call; see docs/resources/effective-gno.md.
func received(cur realm) int64 {
	if !cur.Previous().IsUserCall() {
		panic("only user-call (maketx call) accepted")
	}
	sent := unsafe.OriginSend()
	if len(sent) != 1 || sent[0].Denom != denom {
		panic("send exactly one " + denom + " coin")
	}
	return sent[0].Amount
}

// noCoins guards calls that take no payment: coins sent with them would be
// stuck in the realm.
func noCoins() {
	if len(unsafe.OriginSend()) != 0 {
		panic("this function does not accept coins")
	}
}

// noSession refuses calls signed by an account session key.
func noSession(action string) {
	if _, _, _, ok := runtime.GetSessionInfo(); ok || testSession {
		panic(action + " needs the account's own key, not a session key")
	}
}

func sha256Hex(s string) string {
	h := sha256.Sum256([]byte(s))
	return hex.EncodeToString(h[:])
}

func isHexSHA256(s string) bool {
	if len(s) != 64 {
		return false
	}
	for _, c := range s {
		if (c < '0' || c > '9') && (c < 'a' || c > 'f') {
			return false
		}
	}
	return true
}

func settleWin(cur realm, g *Game, winner address) {
	loser := g.Creator
	if winner == g.Creator {
		loser = g.Acceptor
	}
	pot := 2 * g.Stake
	finish(g, Won)
	g.Winner = winner
	feesCollected += g.Fee
	w := statsOf(winner)
	w.Games++
	w.Wins++
	w.GnotWon += g.Stake - g.Fee
	stats.Set(winner.String(), w)
	topWins.bump(winner, int64(w.Wins))
	topGnot.bump(winner, w.GnotWon)
	l := statsOf(loser)
	l.Games++
	stats.Set(loser.String(), l)
	send(cur, winner, pot-g.Fee)
}

func settleDraw(cur realm, g *Game) {
	finish(g, Draw)
	for _, p := range []address{g.Creator, g.Acceptor} {
		s := statsOf(p)
		s.Games++
		s.Draws++
		stats.Set(p.String(), s)
		send(cur, p, g.Stake)
	}
}

func settleVoid(cur realm, g *Game) {
	finish(g, Void)
	send(cur, g.Creator, g.Stake)
	send(cur, g.Acceptor, g.Stake)
}

// ranking is a leaderboard, highest first, at most topN: Addrs[i] has
// Scores[i]. Kept at settlement so Render never walks every player's stats.
// Two slices rather than a slice of rows: each row struct would be one more
// stored object.
type ranking struct {
	Addrs  []address
	Scores []int64
}

var topWins, topGnot ranking

const topN = 10

// bump moves addr to its new score. Scores only grow, so a player already
// listed can only move up; ties keep the earlier holder first.
func (r *ranking) bump(addr address, score int64) {
	for i, a := range r.Addrs {
		if a == addr {
			r.Addrs = append(r.Addrs[:i], r.Addrs[i+1:]...)
			r.Scores = append(r.Scores[:i], r.Scores[i+1:]...)
			break
		}
	}
	i := len(r.Scores)
	for i > 0 && r.Scores[i-1] < score {
		i--
	}
	if i >= topN {
		return
	}
	r.Addrs = append(r.Addrs, "")
	copy(r.Addrs[i+1:], r.Addrs[i:])
	r.Addrs[i] = addr
	r.Scores = append(r.Scores, 0)
	copy(r.Scores[i+1:], r.Scores[i:])
	r.Scores[i] = score
	if len(r.Addrs) > topN {
		r.Addrs, r.Scores = r.Addrs[:topN], r.Scores[:topN]
	}
}

func finish(g *Game, s Status) {
	g.Status = s
	active.Remove(key(g.ID))
}

func send(cur realm, to address, amount int64) {
	if amount == 0 {
		return
	}
	banker.NewBanker(banker.BankerTypeRealmSend, cur).
		SendCoins(cur.Address(), to, chain.Coins{{denom, amount}})
}

func (g *Game) player(turn byte) address {
	if turn == 1 {
		return g.Creator
	}
	return g.Acceptor
}

func (g *Game) deadline() time.Time { return time.Unix(0, g.LastMove).Add(moveTimeout) }
func (g *Game) expires() time.Time  { return time.Unix(0, g.ExpiresAt) }

// statsOf returns a copy of addr's stats, zero if it has none; write changes
// back with stats.Set.
func statsOf(addr address) Stats {
	if v := stats.Get(addr.String()); v != nil {
		return v.(Stats)
	}
	return Stats{}
}

// key zero-pads ids so avl iteration order matches creation order.
func key(id int) string {
	s := strconv.Itoa(id)
	if len(s) < 10 {
		s = strings.Repeat("0", 10-len(s)) + s
	}
	return s
}

// Games are indexed by id-1 written in base 64: games[a][b][c]. Ids are
// sequential, so this is a dense array in three levels, and each write
// rewrites at most three 64-slot arrays however many games exist. An avl tree
// rewrites a whole root-to-leaf path instead: 10.5M gas for an Offer at 3,000
// games against 3.3M here at 10,000. games gains one entry per 4,096 games,
// so writes stay flat for the first 262,144 games and grow slowly after.
type (
	page [64]*Game
	book [64]*page
)

func store(g *Game) {
	i := g.ID - 1
	if i%4096 == 0 {
		games = append(games, &book{})
	}
	b := games[i/4096]
	if b[i/64%64] == nil {
		b[i/64%64] = &page{}
	}
	b[i/64%64][i%64] = g
}

func get(id int) *Game {
	if id < 1 || id > nextID {
		return nil
	}
	i := id - 1
	return games[i/4096][i/64%64][i%64]
}

func mustGet(id int) *Game {
	g := get(id)
	if g == nil {
		panic("game not found")
	}
	return g
}
