# `ama` - Ask me anything, for any profile

An address opens its page once, then links it from its profile. Visitors ask
questions, and the owner's answers are shown under them.

## Usage

1. Call `Open` once from the address that answers.
2. Link `/r/samcrew/ama:<your address>` from your profile.

A visitor has one question waiting at a time. The owner publishes with
`Answer`, which also replaces an answer already given, and deletes a question
with `Dismiss`, answered or not.

## Pages

- `/r/samcrew/ama`: how to open a page.
- `/r/samcrew/ama:<address>`: the answered questions, newest first.
- `/r/samcrew/ama:<address>/waiting`: the questions still waiting, each with
  the owner's answer and dismiss links.
