# gnoland-packages

Samcrew's packages and realms for [gno.land](https://gno.land), in one
repository. A package that has its own repository is a submodule here.

| Directory | Import path | Origin |
| --- | --- | --- |
| [`gno/p/piechart/v0`](gno/p/piechart/v0) | `gno.land/p/samcrew/piechart/v0` | [gnolang/gno `examples/`](https://github.com/gnolang/gno/tree/7777db693/examples/gno.land/p/samcrew/piechart/v0) |
| [`gno/p/tablesort/v0`](gno/p/tablesort/v0) | `gno.land/p/samcrew/tablesort/v0` | [gnolang/gno `examples/`](https://github.com/gnolang/gno/tree/7777db693/examples/gno.land/p/samcrew/tablesort/v0) |
| [`gno/p/urlfilter/v0`](gno/p/urlfilter/v0) | `gno.land/p/samcrew/urlfilter/v0` | [gnolang/gno `examples/`](https://github.com/gnolang/gno/tree/7777db693/examples/gno.land/p/samcrew/urlfilter/v0) |
| [`gno/p/gauge`](gno/p/gauge) | `gno.land/p/samcrew/gauge` | [gnolang/gno `examples/quarantined/`](https://github.com/gnolang/gno/tree/7777db693/examples/quarantined/gno.land/p/samcrew/gauge) |
| [`gno/p/keccak256`](gno/p/keccak256) | `gno.land/p/samcrew/keccak256` | [gnolang/gno `examples/quarantined/`](https://github.com/gnolang/gno/tree/7777db693/examples/quarantined/gno.land/p/samcrew/keccak256) |
| [`gno/r/subscriptions`](gno/r/subscriptions) | `gno.land/r/samcrew/subscriptions` | [gnolang/gno#4931](https://github.com/gnolang/gno/pull/4931) |
| [`gno/r/normalizedcoins`](gno/r/normalizedcoins) | `gno.land/r/samcrew/normalizedcoins` | [gnolang/gno#4931](https://github.com/gnolang/gno/pull/4931) |
| [`gno/r/payrolls`](gno/r/payrolls) | `gno.land/r/demo/payrolls` | [gnolang/gno#3432](https://github.com/gnolang/gno/pull/3432) |
| [`gnodaokit`](https://github.com/samouraiworld/gnodaokit) | `gno.land/p/samcrew/daokit` and its siblings | submodule |

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

## CI

- **Gno test** builds gno at the revision gno.land mainnet runs
  ([`ci/gno-ref.env`](ci/gno-ref.env)) and tests every package under `gno/`
  with [`ci/gno-test.sh`](ci/gno-test.sh). A package with no test file is
  still compiled. Packages in [`ci/known-failing.txt`](ci/known-failing.txt)
  must fail, on the cause pinned there and nothing else; remove an entry in the
  pull request that fixes that package, or CI goes red.
- **Attribution** checks that no tracked file (the files inside submodules
  included), no commit message in the range a push or pull request adds (every
  commit, not only the tip), no branch or tag, and no pull request credits the
  assistant used to write the change.
