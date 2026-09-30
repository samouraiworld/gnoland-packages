# `guestbook` - A guestbook for any profile

An address opens its guestbook once, then links it from its profile. Each
visitor leaves one short message, and signing again replaces it.

## Usage

1. Call `Open` once from the address that owns the guestbook.
2. Link `/r/samcrew/guestbook:<your address>` from your profile.

The owner deletes a message with `Remove` and its author's address, which the
page fills in on each message's remove link.

## Pages

- `/r/samcrew/guestbook`: how to open a guestbook.
- `/r/samcrew/guestbook:<address>`: every message, newest first.
