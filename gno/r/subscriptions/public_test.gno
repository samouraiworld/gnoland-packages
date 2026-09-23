package subscriptions

import (
	"chain"
	"chain/banker"
	"testing"
	"time"

	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/r/samcrew/normalizedcoins"
	"gno.land/r/tests/vm/test20"
)

func resetState() {
	users = avl.NewTree()
	services = avl.NewTree()
	id = 0
}

func mustPrefixCoins(native, grc20 chain.Coins) chain.Coins {
	coins, err := normalizedcoins.PrefixCoins(native, grc20)
	if err != nil {
		panic(err)
	}
	return coins
}

func TestNewService(cur realm, t *testing.T) {
	defer resetState()

	owner := testutils.TestAddress("owner")
	testing.SetOriginCaller(owner)
	testing.SetRealm(testing.NewUserRealm(owner))

	tests := []struct {
		name          string
		displayName   string
		description   string
		renewalPeriod time.Duration
		native        chain.Coins
		grc20         chain.Coins
		expectedPrice chain.Coins
		expectPanic   bool
		panicMsg      string
	}{
		{
			name:          "valid service with native coins",
			displayName:   "Premium Plan",
			description:   "Monthly subscription",
			renewalPeriod: 30 * 24 * time.Hour,
			native:        chain.NewCoins(chain.NewCoin("ugnot", 1000000)),
			grc20:         chain.Coins{},
			expectedPrice: mustPrefixCoins(chain.NewCoins(chain.NewCoin("ugnot", 1000000)), nil),
		},
		{
			name:          "valid service with GRC20 coins",
			displayName:   "GRC20 Plan",
			description:   "Weekly subscription",
			renewalPeriod: 7 * 24 * time.Hour,
			native:        chain.Coins{},
			grc20:         chain.NewCoins(chain.NewCoin("gno.land/r/demo/foo20", 5000000)),
			expectedPrice: mustPrefixCoins(nil, chain.NewCoins(chain.NewCoin("gno.land/r/demo/foo20", 5000000))),
		},
		{
			name:          "valid service with mixed coins",
			displayName:   "Mixed Plan",
			description:   "Daily subscription",
			renewalPeriod: 24 * time.Hour,
			native:        chain.NewCoins(chain.NewCoin("ugnot", 500000)),
			grc20:         chain.NewCoins(chain.NewCoin("gno.land/r/demo/foo20", 1000)),
			expectedPrice: mustPrefixCoins(chain.NewCoins(chain.NewCoin("ugnot", 500000)), chain.NewCoins(chain.NewCoin("gno.land/r/demo/foo20", 1000))),
		},
		{
			name:          "empty display name panics",
			displayName:   "",
			description:   "Some description",
			renewalPeriod: 24 * time.Hour,
			native:        chain.NewCoins(chain.NewCoin("ugnot", 1000)),
			grc20:         chain.Coins{},
			expectPanic:   true,
			panicMsg:      "display name cannot be empty",
		},
		{
			name:          "empty description panics",
			displayName:   "Valid Name",
			description:   "",
			renewalPeriod: 24 * time.Hour,
			native:        chain.NewCoins(chain.NewCoin("ugnot", 1000)),
			grc20:         chain.Coins{},
			expectPanic:   true,
			panicMsg:      "description cannot be empty",
		},
		{
			name:          "zero renewal period panics",
			displayName:   "Valid Name",
			description:   "Valid description",
			renewalPeriod: 0,
			native:        chain.NewCoins(chain.NewCoin("ugnot", 1000)),
			grc20:         chain.Coins{},
			expectPanic:   true,
			panicMsg:      "renewal period must be positive",
		},
		{
			name:          "negative renewal period panics",
			displayName:   "Valid Name",
			description:   "Valid description",
			renewalPeriod: -1 * time.Hour,
			native:        chain.NewCoins(chain.NewCoin("ugnot", 1000)),
			grc20:         chain.Coins{},
			expectPanic:   true,
			panicMsg:      "renewal period must be positive",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(cur realm, t *testing.T) {
			if tt.expectPanic {
				uassert.AbortsWithMessage(t, cur, tt.panicMsg, func() {
					NewService(cross(cur), tt.displayName, tt.description, tt.renewalPeriod, tt.native, tt.grc20)
				})
				return
			}

			NewService(cross(cur), tt.displayName, tt.description, tt.renewalPeriod, tt.native, tt.grc20)

			svc := getService(serviceKey(owner, tt.displayName))
			uassert.True(t, svc != nil, "service should exist")
			uassert.Equal(t, tt.displayName, svc.displayName)
			uassert.Equal(t, tt.description, svc.description)
			uassert.True(t, tt.renewalPeriod == svc.renewalPeriod, "renewal period should match")
			uassert.True(t, owner == svc.owner.Owner(), "owner should match")

			for i, expectedCoin := range tt.expectedPrice {
				uassert.Equal(t, expectedCoin.Denom, svc.price[i].Denom)
				uassert.Equal(t, expectedCoin.Amount, svc.price[i].Amount)
			}
		})
	}

	t.Run("duplicate display name panics", func(cur realm, t *testing.T) {
		resetState()
		testing.SetOriginCaller(owner)
		testing.SetRealm(testing.NewUserRealm(owner))

		NewService(cross(cur), "Unique Name", "First service", 24*time.Hour, chain.NewCoins(chain.NewCoin("ugnot", 1000)), chain.Coins{})

		uassert.AbortsWithMessage(t, cur, "service with the same display name already exists", func() {
			NewService(cross(cur), "Unique Name", "Second service", 48*time.Hour, chain.NewCoins(chain.NewCoin("ugnot", 2000)), chain.Coins{})
		})
	})
}

func TestNewServiceSimple(cur realm, t *testing.T) {
	defer resetState()

	owner := testutils.TestAddress("owner")
	testing.SetOriginCaller(owner)
	testing.SetRealm(testing.NewUserRealm(owner))

	t.Run("native only", func(cur realm, t *testing.T) {
		NewServiceSimple(cross(cur), "Native Plan", "Native subscription", 30*24*time.Hour, "ugnot", 1000000, "", 0)

		svc := getService(serviceKey(owner, "Native Plan"))
		uassert.True(t, svc != nil, "service should exist")
		uassert.Equal(t, "Native Plan", svc.displayName)
		uassert.Equal(t, int64(1000000), svc.price.AmountOf("/native/ugnot"))
	})

	t.Run("mixed coins", func(cur realm, t *testing.T) {
		NewServiceSimple(cross(cur), "Mixed Plan", "Mixed subscription", 7*24*time.Hour, "ugnot", 500000, "gno.land/r/demo/foo20", 1000)

		svc := getService(serviceKey(owner, "Mixed Plan"))
		uassert.True(t, svc != nil, "service should exist")
		uassert.Equal(t, "Mixed Plan", svc.displayName)
		uassert.Equal(t, int64(500000), svc.price.AmountOf("/native/ugnot"))
		uassert.Equal(t, int64(1000), svc.price.AmountOf("/grc20/r/demo/foo20"))
	})
}

func TestSubscribe(cur realm, t *testing.T) {
	defer resetState()

	owner := testutils.TestAddress("owner")
	subscriber := testutils.TestAddress("subscriber")
	svcKey := serviceKey(owner, "Test Service")

	testing.SetOriginCaller(owner)
	testing.SetRealm(testing.NewUserRealm(owner))
	NewServiceSimple(cross(cur), "Test Service", "Test description", 24*time.Hour, "ugnot", 1000, "", 0)

	t.Run("successful subscription with native coins", func(cur realm, t *testing.T) {
		testing.SetOriginCaller(subscriber)
		testing.SetRealm(testing.NewUserRealm(subscriber))
		testing.SetOriginSend(chain.NewCoins(chain.NewCoin("ugnot", 5000)))

		Subscribe(cross(cur), svcKey, "", 0)

		svc := getService(svcKey)
		uassert.True(t, svc.subscribers.Has(subscriber.String()), "subscriber should be in service")

		userSubsRaw := users.Get(subscriber.String())
		uassert.True(t, userSubsRaw != nil, "user should have subscriptions")
		userSubs := userSubsRaw.(*avl.Tree)
		uassert.True(t, userSubs.Has(svcKey), "user should be subscribed to service")
	})

	t.Run("successful subscription with mixed coins", func(cur realm, t *testing.T) {
		resetState()

		subscriptionsAddr := chain.PackageAddress("gno.land/r/samcrew/subscriptions")
		tokenRealm := "gno.land/r/tests/vm/test20.TST"

		subscriber2 := testutils.TestAddress("subscriber2")
		test20.PrivateLedger.Mint(subscriber2, 10000)
		test20.PrivateLedger.Approve(subscriber2, subscriptionsAddr, 10000)

		testing.SetOriginCaller(owner)
		testing.SetRealm(testing.NewUserRealm(owner))
		NewServiceSimple(cross(cur), "Mixed Service", "Mixed description", 24*time.Hour, "ugnot", 1000, tokenRealm, 500)
		mixedSvcKey := serviceKey(owner, "Mixed Service")

		testing.SetOriginCaller(subscriber2)
		testing.SetRealm(testing.NewUserRealm(subscriber2))
		testing.SetOriginSend(chain.NewCoins(chain.NewCoin("ugnot", 2000)))

		Subscribe(cross(cur), mixedSvcKey, tokenRealm, 1000)

		svc := getService(mixedSvcKey)
		uassert.True(t, svc.subscribers.Has(subscriber2.String()), "subscriber should be in service")

		subRaw := svc.subscribers.Get(subscriber2.String())
		sub := subRaw.(*subscription)
		uassert.Equal(t, int64(2000), sub.vault.AmountOf("/native/ugnot"))
		uassert.Equal(t, int64(1000), sub.vault.AmountOf("/grc20/r/tests/vm/test20.TST"))
	})

	t.Run("empty service key panics", func(cur realm, t *testing.T) {
		testing.SetOriginCaller(subscriber)
		testing.SetRealm(testing.NewUserRealm(subscriber))

		uassert.AbortsWithMessage(t, cur, "service key cannot be empty", func() {
			Subscribe(cross(cur), "", "", 0)
		})
	})

	t.Run("service not found panics", func(cur realm, t *testing.T) {
		testing.SetOriginCaller(subscriber)
		testing.SetRealm(testing.NewUserRealm(subscriber))

		uassert.AbortsWithMessage(t, cur, "service not found", func() {
			Subscribe(cross(cur), "g1nonexistent:Non-existent Service", "", 0)
		})
	})

	t.Run("already subscribed panics", func(cur realm, t *testing.T) {
		resetState()
		testing.SetOriginCaller(owner)
		testing.SetRealm(testing.NewUserRealm(owner))
		NewServiceSimple(cross(cur), "Test Service", "Test description", 24*time.Hour, "ugnot", 1000, "", 0)
		testSvcKey := serviceKey(owner, "Test Service")

		testing.SetOriginCaller(subscriber)
		testing.SetRealm(testing.NewUserRealm(subscriber))
		testing.SetOriginSend(chain.NewCoins(chain.NewCoin("ugnot", 5000)))
		Subscribe(cross(cur), testSvcKey, "", 0)

		uassert.AbortsWithMessage(t, cur, "already subscribed", func() {
			Subscribe(cross(cur), testSvcKey, "", 0)
		})
	})

	t.Run("insufficient deposit panics", func(cur realm, t *testing.T) {
		resetState()
		testing.SetOriginCaller(owner)
		testing.SetRealm(testing.NewUserRealm(owner))
		NewServiceSimple(cross(cur), "Test Service", "Test description", 24*time.Hour, "ugnot", 1000, "", 0)
		testSvcKey := serviceKey(owner, "Test Service")

		subscriber2 := testutils.TestAddress("subscriber2")
		testing.SetOriginCaller(subscriber2)
		testing.SetRealm(testing.NewUserRealm(subscriber2))
		testing.SetOriginSend(chain.NewCoins(chain.NewCoin("ugnot", 500)))

		uassert.AbortsWithMessage(t, cur, "initial deposit must be positive and at least the service price", func() {
			Subscribe(cross(cur), testSvcKey, "", 0)
		})
	})

	t.Run("deposit in a denom the price does not name panics", func(cur realm, t *testing.T) {
		resetState()
		testing.SetOriginCaller(owner)
		testing.SetRealm(testing.NewUserRealm(owner))
		NewServiceSimple(cross(cur), "GRC20 Only", "Test description", 24*time.Hour, "", 0, "gno.land/r/tests/vm/test20.TST", 1000)
		testSvcKey := serviceKey(owner, "GRC20 Only")

		testing.SetOriginCaller(subscriber)
		testing.SetRealm(testing.NewUserRealm(subscriber))
		testing.SetOriginSend(chain.NewCoins(chain.NewCoin("ugnot", 5000)))

		uassert.AbortsWithMessage(t, cur, "initial deposit must be positive and at least the service price", func() {
			Subscribe(cross(cur), testSvcKey, "", 0)
		})
	})

	t.Run("native coins forwarded by another realm panic", func(cur realm, t *testing.T) {
		resetState()
		testing.SetOriginCaller(owner)
		testing.SetRealm(testing.NewUserRealm(owner))
		NewServiceSimple(cross(cur), "Test Service", "Test description", 24*time.Hour, "ugnot", 1000, "", 0)
		testSvcKey := serviceKey(owner, "Test Service")

		testing.SetOriginCaller(subscriber)
		testing.SetRealm(testing.NewCodeRealm("gno.land/r/test/proxy"))
		testing.SetOriginSend(chain.NewCoins(chain.NewCoin("ugnot", 5000)))

		uassert.AbortsWithMessage(t, cur, "native coins must be sent by a direct user call", func() {
			Subscribe(cross(cur), testSvcKey, "", 0)
		})
	})

	t.Run("GRC20 token not found panics", func(cur realm, t *testing.T) {
		resetState()
		testing.SetOriginCaller(owner)
		testing.SetRealm(testing.NewUserRealm(owner))
		NewServiceSimple(cross(cur), "Test Service", "Test description", 24*time.Hour, "ugnot", 1000, "", 0)
		testSvcKey := serviceKey(owner, "Test Service")

		testing.SetOriginCaller(subscriber)
		testing.SetRealm(testing.NewUserRealm(subscriber))
		testing.SetOriginSend(chain.NewCoins(chain.NewCoin("ugnot", 5000)))

		uassert.AbortsWithMessage(t, cur, "GRC20 token not found: gno.land/r/fake/token", func() {
			Subscribe(cross(cur), testSvcKey, "gno.land/r/fake/token", 1000)
		})
	})
}

func TestUnsubscribe(cur realm, t *testing.T) {
	defer resetState()

	owner := testutils.TestAddress("owner")
	subscriber := testutils.TestAddress("subscriber")
	svcKey := serviceKey(owner, "Test Service")

	testing.SetOriginCaller(owner)
	testing.SetRealm(testing.NewUserRealm(owner))
	NewServiceSimple(cross(cur), "Test Service", "Test description", 24*time.Hour, "ugnot", 1000, "", 0)

	t.Run("successful unsubscribe", func(cur realm, t *testing.T) {
		subscriptionsAddr := chain.PackageAddress("gno.land/r/samcrew/subscriptions")
		depositAmount := chain.NewCoins(chain.NewCoin("ugnot", 5000))

		testing.SetOriginCaller(subscriber)
		testing.SetRealm(testing.NewUserRealm(subscriber))
		// Simulate a deposit usually made with -send flag in a real transaction
		testing.IssueCoins(subscriptionsAddr, depositAmount)
		testing.SetOriginSend(depositAmount)
		Subscribe(cross(cur), svcKey, "", 0)

		svc := getService(svcKey)
		uassert.True(t, svc.subscribers.Has(subscriber.String()), "subscriber should be in service before unsubscribe")
		uassert.True(t, users.Has(subscriber.String()), "user should have subscriptions before unsubscribe")

		b := banker.NewReadonlyBanker()
		ownerBefore := b.GetCoins(owner).AmountOf("ugnot")
		subscriberBefore := b.GetCoins(subscriber).AmountOf("ugnot")
		realmBefore := b.GetCoins(subscriptionsAddr).AmountOf("ugnot")

		Unsubscribe(cross(cur), svcKey)

		// The first period goes to the owner and the rest back to the subscriber.
		uassert.Equal(t, int64(1000), b.GetCoins(owner).AmountOf("ugnot")-ownerBefore)
		uassert.Equal(t, int64(4000), b.GetCoins(subscriber).AmountOf("ugnot")-subscriberBefore)
		uassert.Equal(t, int64(5000), realmBefore-b.GetCoins(subscriptionsAddr).AmountOf("ugnot"))

		uassert.False(t, svc.subscribers.Has(subscriber.String()), "subscriber should be removed from service")
		uassert.False(t, users.Has(subscriber.String()), "user should be removed from users tree")
	})

	t.Run("empty service key panics", func(cur realm, t *testing.T) {
		testing.SetOriginCaller(subscriber)
		testing.SetRealm(testing.NewUserRealm(subscriber))

		uassert.AbortsWithMessage(t, cur, "service key cannot be empty", func() {
			Unsubscribe(cross(cur), "")
		})
	})

	t.Run("service not found panics", func(cur realm, t *testing.T) {
		testing.SetOriginCaller(subscriber)
		testing.SetRealm(testing.NewUserRealm(subscriber))

		uassert.AbortsWithMessage(t, cur, "service not found", func() {
			Unsubscribe(cross(cur), "g1nonexistent:Non-existent Service")
		})
	})

	t.Run("not subscribed panics", func(cur realm, t *testing.T) {
		resetState()
		testing.SetOriginCaller(owner)
		testing.SetRealm(testing.NewUserRealm(owner))
		NewServiceSimple(cross(cur), "Test Service", "Test description", 24*time.Hour, "ugnot", 1000, "", 0)
		testSvcKey := serviceKey(owner, "Test Service")

		testing.SetOriginCaller(subscriber)
		testing.SetRealm(testing.NewUserRealm(subscriber))

		uassert.AbortsWithMessage(t, cur, "not subscribed to service: "+testSvcKey, func() {
			Unsubscribe(cross(cur), testSvcKey)
		})
	})
}

func TestTopup(cur realm, t *testing.T) {
	defer resetState()

	owner := testutils.TestAddress("owner")
	subscriber := testutils.TestAddress("subscriber")
	subscriptionsAddr := chain.PackageAddress("gno.land/r/samcrew/subscriptions")
	svcKey := serviceKey(owner, "Test Service")

	testing.SetOriginCaller(owner)
	testing.SetRealm(testing.NewUserRealm(owner))
	NewServiceSimple(cross(cur), "Test Service", "Test description", 24*time.Hour, "ugnot", 1000, "", 0)

	t.Run("successful topup with native coins", func(cur realm, t *testing.T) {
		initialDeposit := chain.NewCoins(chain.NewCoin("ugnot", 2000))
		testing.SetOriginCaller(subscriber)
		testing.SetRealm(testing.NewUserRealm(subscriber))
		// Simulate a deposit usually made with -send flag in a real transaction
		testing.IssueCoins(subscriptionsAddr, initialDeposit)
		testing.SetOriginSend(initialDeposit)
		Subscribe(cross(cur), svcKey, "", 0)

		svc := getService(svcKey)
		subRaw := svc.subscribers.Get(subscriber.String())
		sub := subRaw.(*subscription)
		uassert.Equal(t, int64(2000), sub.vault.AmountOf("/native/ugnot"))

		topupAmount := chain.NewCoins(chain.NewCoin("ugnot", 3000))
		// Simulate a deposit usually made with -send flag in a real transaction
		testing.IssueCoins(subscriptionsAddr, topupAmount)
		testing.SetOriginSend(topupAmount)
		Topup(cross(cur), svcKey, "", 0)

		uassert.Equal(t, int64(5000), sub.vault.AmountOf("/native/ugnot"))
	})

	t.Run("empty service key panics", func(cur realm, t *testing.T) {
		testing.SetOriginCaller(subscriber)
		testing.SetRealm(testing.NewUserRealm(subscriber))

		uassert.AbortsWithMessage(t, cur, "service key cannot be empty", func() {
			Topup(cross(cur), "", "", 0)
		})
	})

	t.Run("not subscribed panics", func(cur realm, t *testing.T) {
		resetState()
		testing.SetOriginCaller(owner)
		testing.SetRealm(testing.NewUserRealm(owner))
		NewServiceSimple(cross(cur), "Test Service", "Test description", 24*time.Hour, "ugnot", 1000, "", 0)
		testSvcKey := serviceKey(owner, "Test Service")

		testing.SetOriginCaller(subscriber)
		testing.SetRealm(testing.NewUserRealm(subscriber))

		uassert.AbortsWithMessage(t, cur, "not subscribed to service: "+testSvcKey, func() {
			Topup(cross(cur), testSvcKey, "", 0)
		})
	})

	t.Run("GRC20 token not found panics", func(cur realm, t *testing.T) {
		resetState()
		testing.SetOriginCaller(owner)
		testing.SetRealm(testing.NewUserRealm(owner))
		NewServiceSimple(cross(cur), "Test Service", "Test description", 24*time.Hour, "ugnot", 1000, "", 0)
		testSvcKey := serviceKey(owner, "Test Service")

		initialDeposit := chain.NewCoins(chain.NewCoin("ugnot", 2000))
		testing.SetOriginCaller(subscriber)
		testing.SetRealm(testing.NewUserRealm(subscriber))
		testing.IssueCoins(subscriptionsAddr, initialDeposit)
		testing.SetOriginSend(initialDeposit)
		Subscribe(cross(cur), testSvcKey, "", 0)

		uassert.AbortsWithMessage(t, cur, "GRC20 token not found: gno.land/r/fake/token", func() {
			Topup(cross(cur), testSvcKey, "gno.land/r/fake/token", 1000)
		})
	})
}

func TestWithdraw(cur realm, t *testing.T) {
	defer resetState()

	owner := testutils.TestAddress("owner")
	subscriber := testutils.TestAddress("subscriber")
	subscriptionsAddr := chain.PackageAddress("gno.land/r/samcrew/subscriptions")
	svcKey := serviceKey(owner, "Test Service")

	testing.SetOriginCaller(owner)
	testing.SetRealm(testing.NewUserRealm(owner))
	NewServiceSimple(cross(cur), "Test Service", "Test description", 24*time.Hour, "ugnot", 1000, "", 0)

	t.Run("successful withdraw", func(cur realm, t *testing.T) {
		initialDeposit := chain.NewCoins(chain.NewCoin("ugnot", 5000))
		testing.SetOriginCaller(subscriber)
		testing.SetRealm(testing.NewUserRealm(subscriber))
		// Simulate a deposit usually made with -send flag in a real transaction
		testing.IssueCoins(subscriptionsAddr, initialDeposit)
		testing.SetOriginSend(initialDeposit)
		Subscribe(cross(cur), svcKey, "", 0)

		svc := getService(svcKey)
		subRaw := svc.subscribers.Get(subscriber.String())
		sub := subRaw.(*subscription)
		uassert.Equal(t, int64(5000), sub.vault.AmountOf("/native/ugnot"))

		Withdraw(cross(cur), svcKey, "/native/ugnot", 2000)

		uassert.Equal(t, int64(3000), sub.vault.AmountOf("/native/ugnot"))
	})

	t.Run("empty service key panics", func(cur realm, t *testing.T) {
		testing.SetOriginCaller(subscriber)
		testing.SetRealm(testing.NewUserRealm(subscriber))

		uassert.AbortsWithMessage(t, cur, "service key cannot be empty", func() {
			Withdraw(cross(cur), "", "/native/ugnot", 1000)
		})
	})

	t.Run("empty denomination panics", func(cur realm, t *testing.T) {
		testing.SetOriginCaller(subscriber)
		testing.SetRealm(testing.NewUserRealm(subscriber))

		uassert.AbortsWithMessage(t, cur, "denomination cannot be empty", func() {
			Withdraw(cross(cur), svcKey, "", 1000)
		})
	})

	t.Run("zero amount panics", func(cur realm, t *testing.T) {
		testing.SetOriginCaller(subscriber)
		testing.SetRealm(testing.NewUserRealm(subscriber))

		uassert.AbortsWithMessage(t, cur, "withdrawal amount must be positive", func() {
			Withdraw(cross(cur), svcKey, "/native/ugnot", 0)
		})
	})

	t.Run("negative amount panics", func(cur realm, t *testing.T) {
		testing.SetOriginCaller(subscriber)
		testing.SetRealm(testing.NewUserRealm(subscriber))

		uassert.AbortsWithMessage(t, cur, "withdrawal amount must be positive", func() {
			Withdraw(cross(cur), svcKey, "/native/ugnot", -100)
		})
	})

	t.Run("not subscribed panics", func(cur realm, t *testing.T) {
		resetState()
		testing.SetOriginCaller(owner)
		testing.SetRealm(testing.NewUserRealm(owner))
		NewServiceSimple(cross(cur), "Test Service", "Test description", 24*time.Hour, "ugnot", 1000, "", 0)
		testSvcKey := serviceKey(owner, "Test Service")

		testing.SetOriginCaller(subscriber)
		testing.SetRealm(testing.NewUserRealm(subscriber))

		uassert.AbortsWithMessage(t, cur, "not subscribed to service: "+testSvcKey, func() {
			Withdraw(cross(cur), testSvcKey, "/native/ugnot", 1000)
		})
	})

	t.Run("insufficient available balance panics", func(cur realm, t *testing.T) {
		resetState()
		testing.SetOriginCaller(owner)
		testing.SetRealm(testing.NewUserRealm(owner))
		NewServiceSimple(cross(cur), "Test Service", "Test description", 24*time.Hour, "ugnot", 1000, "", 0)
		testSvcKey := serviceKey(owner, "Test Service")

		initialDeposit := chain.NewCoins(chain.NewCoin("ugnot", 2000))
		testing.SetOriginCaller(subscriber)
		testing.SetRealm(testing.NewUserRealm(subscriber))
		testing.IssueCoins(subscriptionsAddr, initialDeposit)
		testing.SetOriginSend(initialDeposit)
		Subscribe(cross(cur), testSvcKey, "", 0)

		uassert.AbortsWithMessage(t, cur, "insufficient available balance to withdraw", func() {
			Withdraw(cross(cur), testSvcKey, "/native/ugnot", 5000)
		})
	})
}

func TestIsSubscribed(cur realm, t *testing.T) {
	defer resetState()

	owner := testutils.TestAddress("owner")
	subscriber := testutils.TestAddress("subscriber")
	subscriptionsAddr := chain.PackageAddress("gno.land/r/samcrew/subscriptions")
	svcKey := serviceKey(owner, "Test Service")

	testing.SetOriginCaller(owner)
	testing.SetRealm(testing.NewUserRealm(owner))
	NewServiceSimple(cross(cur), "Test Service", "Test description", 24*time.Hour, "ugnot", 1000, "", 0)

	t.Run("service not found returns false", func(cur realm, t *testing.T) {
		result := IsSubscribed(cross(cur), "g1nonexistent:Non-existent Service", subscriber.String())
		uassert.False(t, result, "should return false for non-existent service")
	})

	t.Run("not subscribed returns false", func(cur realm, t *testing.T) {
		result := IsSubscribed(cross(cur), svcKey, subscriber.String())
		uassert.False(t, result, "should return false for non-subscriber")
	})

	t.Run("subscribed and active returns true", func(cur realm, t *testing.T) {
		initialDeposit := chain.NewCoins(chain.NewCoin("ugnot", 5000))
		testing.SetOriginCaller(subscriber)
		testing.SetRealm(testing.NewUserRealm(subscriber))
		// Simulate a deposit usually made with -send flag in a real transaction
		testing.IssueCoins(subscriptionsAddr, initialDeposit)
		testing.SetOriginSend(initialDeposit)
		Subscribe(cross(cur), svcKey, "", 0)

		result := IsSubscribed(cross(cur), svcKey, subscriber.String())
		uassert.True(t, result, "should return true for active subscriber")
	})

	t.Run("subscribed but inactive returns false", func(cur realm, t *testing.T) {
		resetState()
		testing.SetOriginCaller(owner)
		testing.SetRealm(testing.NewUserRealm(owner))
		NewServiceSimple(cross(cur), "Test Service", "Test description", 1*time.Hour, "ugnot", 1000, "", 0)
		testSvcKey := serviceKey(owner, "Test Service")

		initialDeposit := chain.NewCoins(chain.NewCoin("ugnot", 1500))
		testing.SetOriginCaller(subscriber)
		testing.SetRealm(testing.NewUserRealm(subscriber))
		testing.IssueCoins(subscriptionsAddr, initialDeposit)
		testing.SetOriginSend(initialDeposit)
		Subscribe(cross(cur), testSvcKey, "", 0)

		testing.SkipHeights(720 * 3)

		result := IsSubscribed(cross(cur), testSvcKey, subscriber.String())
		uassert.False(t, result, "should return false for inactive subscriber")
	})
}

func TestServiceClaimVault(cur realm, t *testing.T) {
	defer resetState()

	owner := testutils.TestAddress("owner")
	subscriber := testutils.TestAddress("subscriber")
	subscriptionsAddr := chain.PackageAddress("gno.land/r/samcrew/subscriptions")
	svcKey := serviceKey(owner, "Test Service")

	testing.SetOriginCaller(owner)
	testing.SetRealm(testing.NewUserRealm(owner))
	NewServiceSimple(cross(cur), "Test Service", "Test description", 24*time.Hour, "ugnot", 1000, "", 0)

	t.Run("successful claim", func(cur realm, t *testing.T) {
		initialDeposit := chain.NewCoins(chain.NewCoin("ugnot", 5000))
		testing.SetOriginCaller(subscriber)
		testing.SetRealm(testing.NewUserRealm(subscriber))
		// Simulate a deposit usually made with -send flag in a real transaction
		testing.IssueCoins(subscriptionsAddr, initialDeposit)
		testing.SetOriginSend(initialDeposit)
		Subscribe(cross(cur), svcKey, "", 0)

		testing.SkipHeights(720 * 25)

		b := banker.NewReadonlyBanker()
		ownerBalanceBefore := b.GetCoins(owner)

		testing.SetOriginCaller(owner)
		testing.SetRealm(testing.NewUserRealm(owner))
		ServiceClaimVault(cross(cur), svcKey)

		ownerBalanceAfter := b.GetCoins(owner)
		uassert.True(t, ownerBalanceAfter.AmountOf("ugnot") > ownerBalanceBefore.AmountOf("ugnot"), "owner should have more ugnot after claim")
	})

	t.Run("service not found panics", func(cur realm, t *testing.T) {
		testing.SetOriginCaller(owner)
		testing.SetRealm(testing.NewUserRealm(owner))

		uassert.AbortsWithMessage(t, cur, "service not found", func() {
			ServiceClaimVault(cross(cur), "g1nonexistent:Non-existent Service")
		})
	})

	t.Run("not owner panics", func(cur realm, t *testing.T) {
		resetState()
		testing.SetOriginCaller(owner)
		testing.SetRealm(testing.NewUserRealm(owner))
		NewServiceSimple(cross(cur), "Test Service", "Test description", 24*time.Hour, "ugnot", 1000, "", 0)
		testSvcKey := serviceKey(owner, "Test Service")

		notOwner := testutils.TestAddress("not_owner")
		testing.SetOriginCaller(notOwner)
		testing.SetRealm(testing.NewUserRealm(notOwner))

		uassert.AbortsWithMessage(t, cur, "ownable: caller is not owner", func() {
			ServiceClaimVault(cross(cur), testSvcKey)
		})
	})

	t.Run("no funds to claim panics", func(cur realm, t *testing.T) {
		resetState()
		testing.SetOriginCaller(owner)
		testing.SetRealm(testing.NewUserRealm(owner))
		NewServiceSimple(cross(cur), "Test Service", "Test description", 24*time.Hour, "ugnot", 1000, "", 0)
		testSvcKey := serviceKey(owner, "Test Service")

		testing.SetOriginCaller(owner)
		testing.SetRealm(testing.NewUserRealm(owner))

		uassert.AbortsWithMessage(t, cur, "no funds to claim", func() {
			ServiceClaimVault(cross(cur), testSvcKey)
		})
	})
}

func TestClaimChargesCoveredPeriodsOfInactiveSubscriber(cur realm, t *testing.T) {
	defer resetState()

	owner := testutils.TestAddress("claimowner")
	subscriber := testutils.TestAddress("claimsubscriber")
	subscriptionsAddr := chain.PackageAddress("gno.land/r/samcrew/subscriptions")
	b := banker.NewReadonlyBanker()

	testing.SetOriginCaller(owner)
	testing.SetRealm(testing.NewUserRealm(owner))
	NewServiceSimple(cross(cur), "Hourly", "desc", time.Hour, "ugnot", 1000, "", 0)
	svcKey := serviceKey(owner, "Hourly")

	// 2500 covers two periods and not a third.
	testing.SetOriginCaller(subscriber)
	testing.SetRealm(testing.NewUserRealm(subscriber))
	deposit := chain.NewCoins(chain.NewCoin("ugnot", 2500))
	testing.IssueCoins(subscriptionsAddr, deposit)
	testing.SetOriginSend(deposit)
	Subscribe(cross(cur), svcKey, "", 0)

	testing.SkipHeights(720 * 4)

	testing.SetOriginCaller(owner)
	testing.SetRealm(testing.NewUserRealm(owner))
	ServiceClaimVault(cross(cur), svcKey)

	svc := getService(svcKey)
	sub := svc.subscribers.Get(subscriber.String()).(*subscription)
	uassert.Equal(t, int64(2000), b.GetCoins(owner).AmountOf("ugnot"))
	uassert.Equal(t, int64(500), sub.vault.AmountOf("/native/ugnot"))
	uassert.Equal(t, int64(500), b.GetCoins(subscriptionsAddr).AmountOf("ugnot"))

	// A second claim finds nothing left to charge.
	uassert.AbortsWithMessage(t, cur, "no funds to claim", func() {
		ServiceClaimVault(cross(cur), svcKey)
	})

	// The subscriber can still leave, and gets back what the vault holds.
	testing.SetOriginCaller(subscriber)
	testing.SetRealm(testing.NewUserRealm(subscriber))
	testing.SetOriginSend(chain.Coins{})
	Unsubscribe(cross(cur), svcKey)
	uassert.Equal(t, int64(500), b.GetCoins(subscriber).AmountOf("ugnot"))
	uassert.Equal(t, int64(0), b.GetCoins(subscriptionsAddr).AmountOf("ugnot"))
}
