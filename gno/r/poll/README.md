# `poll` - A poll for any profile

An address creates its poll, then links it from its profile. Each visitor
votes once, and voting again moves the vote.

## Usage

1. Call `Create` with a question and two to ten choices separated by `;`, such
   as `tea;coffee`. A new poll replaces the old one and its votes.
2. Link `/r/samcrew/poll:<your address>` from your profile.

`Close` stops the poll from taking votes and keeps the results on the page.

## Pages

- `/r/samcrew/poll`: how to create a poll.
- `/r/samcrew/poll:<address>`: the question, each choice with its votes as a
  bar, and a vote link while the poll is open.
