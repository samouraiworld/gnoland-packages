package subscriptions

import (
	"chain"
	"chain/runtime/unsafe"
	"errors"
	"time"

	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/seqid/v0"
	"gno.land/r/nt/grc20reg/v0"
	"gno.land/r/samcrew/normalizedcoins"
)

func init() {
	users = avl.NewTree()
	services = avl.NewTree()
}

type subscription struct {
	serviceID     seqid.ID
	vault         chain.Coins
	startedAt     time.Time
	lastChargedAt time.Time
	initialPaid   bool
}

// dueAmount calculates how much the subscriber owes based on elapsed time.
// If charge is true, it also deducts the amount from vault and updates lastChargedAt.
// Returns the amount due and whether the subscription can cover all periods.
func (sub *subscription) dueAmount(charge bool, renewalPeriod time.Duration, price chain.Coins) (chain.Coins, bool) {
	if renewalPeriod <= 0 {
		panic("renewal period must be positive")
	}

	elapsed := time.Now().Sub(sub.lastChargedAt)
	periodsElapsed := int64(elapsed / renewalPeriod)

	// If initial payment not yet made, add one period
	if !sub.initialPaid {
		periodsElapsed += 1
	}
	if periodsElapsed <= 0 {
		return chain.Coins{}, true
	}

	// Count the periods the vault covers, stopping at the first it cannot.
	due := chain.Coins{}
	covered := int64(0)
	for covered < periodsElapsed {
		next := normalizedcoins.AddCoins(due, price)
		if normalizedcoins.LessCoinsThan(sub.vault, next) {
			break
		}
		due = next
		covered++
	}

	// A charge takes every covered period, so the vault always matches what left the realm.
	if charge && covered > 0 {
		sub.vault = normalizedcoins.SubCoins(sub.vault, due)
		sub.lastChargedAt = sub.lastChargedAt.Add(time.Duration(covered) * renewalPeriod)
		sub.initialPaid = true
	}

	return due, covered == periodsElapsed
}

func (sub *subscription) isActive(renewalPeriod time.Duration, price chain.Coins) bool {
	_, ok := sub.dueAmount(false, renewalPeriod, price)
	return ok
}

func (sub *subscription) balance(renewalPeriod time.Duration, price chain.Coins) chain.Coins {
	dueAmount, _ := sub.dueAmount(false, renewalPeriod, price)
	return normalizedcoins.SubCoins(sub.vault, dueAmount)
}

// nativeSend returns the native coins attached to the transaction. They reach
// this realm only when a user calls it directly, so any other caller that
// attaches coins is refused.
func nativeSend(cur realm) chain.Coins {
	send := unsafe.OriginSend()
	if normalizedcoins.CoinsHasPositive(send) && !cur.Previous().IsUserCall() {
		panic("native coins must be sent by a direct user call")
	}
	return send
}

func topupNative(cur realm, svcKey string) {
	caller := cur.Previous().Address()
	send := nativeSend(cur)
	if !normalizedcoins.CoinsHasPositive(send) {
		panic("topup amount must be positive")
	}

	prefixedSend, err := normalizedcoins.PrefixCoins(send, nil)
	if err != nil {
		panic(err)
	}

	svc := mustGetService(svcKey)
	if !svc.subscribers.Has(caller.String()) {
		panic("not subscribed to service: " + svcKey)
	}
	subValue := svc.subscribers.Get(caller.String())
	sub := subValue.(*subscription)
	sub.vault = normalizedcoins.AddCoins(sub.vault, prefixedSend)
}

func topupGRC20(cur realm, svcKey string, fqName string, amount int64) {
	token := grc20reg.MustGet(fqName)
	if token == nil {
		panic(errors.New("token not found: " + fqName))
	}
	caller := cur.Previous().Address()

	anyAmount := amount == -1
	if !anyAmount && amount <= 0 {
		panic("topup amount must be positive or -1 for max")
	}

	if anyAmount {
		amount = int64(token.Allowance(caller, cur.Address()))
	}

	grc20Send := chain.NewCoins(chain.NewCoin(fqName, amount))
	prefixedSend, err := normalizedcoins.PrefixCoins(nil, grc20Send)
	if err != nil {
		panic(err)
	}

	grc20reg.TransferFrom(0, cur, fqName, caller, cur.Address(), amount)

	svc := mustGetService(svcKey)
	if !svc.subscribers.Has(caller.String()) {
		panic("not subscribed to service: " + svcKey)
	}
	subValue := svc.subscribers.Get(caller.String())
	sub := subValue.(*subscription)
	sub.vault = normalizedcoins.AddCoins(sub.vault, prefixedSend)
}
