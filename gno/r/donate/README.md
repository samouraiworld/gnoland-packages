# `donate` - A donate button for any profile

An address opens its donate page once, then links it from its profile.
Visitors pick an amount and add a short note, and the coins reach the owner in
the same transaction: the realm keeps the record and never holds the coins.

## Usage

1. Call `Open` once from the address that receives the donations.
2. Link `/r/samcrew/donate:<your address>` from your profile.

`Donate` takes GNOT only, since any realm can issue a coin of its own, and a
direct call only, `gnokey maketx call` or the page's link, since only then do
the coins sent with it sit in this realm. The owner clears
a note with `RemoveNote` and the donation's number; the amount stays listed.

## Pages

- `/r/samcrew/donate`: how to open a page.
- `/r/samcrew/donate:<address>`: the total received, three donate buttons of
  1, 5 and 10 GNOT, and every donation, newest first.
