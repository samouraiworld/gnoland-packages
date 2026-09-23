#!/usr/bin/env bash
# Runs `gno test` on every package under gno/, one package at a time, with the
# gno binary given in $GNO (default: `gno` on PATH).
#
# A package listed in ci/known-failing.txt is expected to FAIL. If it starts to
# pass, this script fails too, so the list cannot go stale: remove the entry in
# the pull request that fixes the package.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
gno="${GNO:-gno}"
known="$root/ci/known-failing.txt"
log="$(mktemp "${TMPDIR:-/tmp}/gno-test.XXXXXX")"
trap 'rm -f -- "$log"' EXIT

is_known() {
  grep -v '^[[:space:]]*#' "$known" | grep -qxF -- "$1"
}

# Every listed entry must still name a package, or a rename would silently
# turn an expected failure into an untested path.
while IFS= read -r entry; do
  case "$entry" in ''|'#'*) continue ;; esac
  [ -f "$root/$entry/gnomod.toml" ] || {
    echo "::error file=ci/known-failing.txt::$entry is not a package (no gnomod.toml)"
    exit 1
  }
done < "$known"

pass=0 expected=0 bad=0
cd "$root"
for dir in $(find gno -name gnomod.toml -exec dirname {} \; | LC_ALL=C sort); do
  if "$gno" test "./$dir" > "$log" 2>&1; then status=ok; else status=fail; fi
  if is_known "$dir"; then
    if [ "$status" = ok ]; then
      echo "::error file=$dir/gnomod.toml::$dir now passes: remove it from ci/known-failing.txt"
      bad=$((bad + 1))
    else
      echo "  expected failure  $dir"
      expected=$((expected + 1))
    fi
  elif [ "$status" = ok ]; then
    echo "  ok                $dir"
    pass=$((pass + 1))
  else
    echo "::error file=$dir/gnomod.toml::gno test failed for $dir"
    sed 's/^/    /' "$log"
    bad=$((bad + 1))
  fi
done

echo
echo "$pass passed, $expected failed as expected (ci/known-failing.txt), $bad unexpected"
[ "$bad" -eq 0 ]
