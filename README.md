# gnoland-packages

Samcrew's packages and realms for [gno.land](https://gno.land), in one
repository. A package that has its own repository is a submodule here.

| Directory | Import path | Origin |
| --- | --- | --- |
| [`gno/p/piechart`](gno/p/piechart) | `gno.land/p/samcrew/piechart/v0` | [gnolang/gno `examples/`](https://github.com/gnolang/gno/tree/7777db693/examples/gno.land/p/samcrew/piechart/v0) |
| [`gno/p/tablesort`](gno/p/tablesort) | `gno.land/p/samcrew/tablesort/v0` | [gnolang/gno `examples/`](https://github.com/gnolang/gno/tree/7777db693/examples/gno.land/p/samcrew/tablesort/v0) |
| [`gno/p/urlfilter`](gno/p/urlfilter) | `gno.land/p/samcrew/urlfilter/v0` | [gnolang/gno `examples/`](https://github.com/gnolang/gno/tree/7777db693/examples/gno.land/p/samcrew/urlfilter/v0) |
| [`gno/p/gauge`](gno/p/gauge) | `gno.land/p/samcrew/gauge` | [gnolang/gno `examples/quarantined/`](https://github.com/gnolang/gno/tree/7777db693/examples/quarantined/gno.land/p/samcrew/gauge) |
| [`gno/p/keccak256`](gno/p/keccak256) | `gno.land/p/samcrew/keccak256` | [gnolang/gno `examples/quarantined/`](https://github.com/gnolang/gno/tree/7777db693/examples/quarantined/gno.land/p/samcrew/keccak256) |
| [`gno/r/subscriptions`](gno/r/subscriptions) | `gno.land/r/samcrew/subscriptions` | [gnolang/gno#4931](https://github.com/gnolang/gno/pull/4931) |
| [`gno/r/normalizedcoins`](gno/r/normalizedcoins) | `gno.land/r/samcrew/normalizedcoins` | [gnolang/gno#4931](https://github.com/gnolang/gno/pull/4931) |
| [`gno/r/connect4`](gno/r/connect4) | `gno.land/r/samcrew/connect4` | new here |
| [`gno/r/payrolls`](gno/r/payrolls) | `gno.land/r/demo/payrolls` | [gnolang/gno#3432](https://github.com/gnolang/gno/pull/3432) |
| [`gnodaokit`](https://github.com/samouraiworld/gnodaokit) | `gno.land/p/samcrew/daokit` and its siblings | submodule |

## Versions

A package's version is the end of its `module` line in `gnomod.toml`, and the
directory does not repeat it: `gno/p/piechart` declares
`gno.land/p/samcrew/piechart/v0`. gno resolves a workspace import from the
module line, so the import path is unchanged and so is the realm address.

A breaking change is `gnopm bump piechart`, which edits that one line, then the
files change in place and git diffs them. Never copy a package to a `vN`
directory: that is the diff nobody can read.

```bash
go install moul.io/gnopm@latest
gnopm status     # what resolves, and whether anything is out of date
gnopm tool ci    # what CI runs
```

`gnomod.lock` is source, committed with the change that moves a version.
`gnodaokit` is a submodule, so its packages belong to its own repository and
are not in this lock.

## Work in progress

`payrolls` and `subscriptions` are still work in progress. Do not use them in
production.

## Test

Clone with the submodules, then run `gno test` from the repository root, where
`gnowork.toml` marks the workspace:

```bash
git clone --recurse-submodules https://github.com/samouraiworld/gnoland-packages.git
cd gnoland-packages
gno test ./gno/...
```
