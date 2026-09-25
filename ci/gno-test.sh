#!/usr/bin/env bash
# Runs `gno test` on every package under gno/, one package at a time, with the
# gno binary given in $GNO (default: `gno` on PATH).
#
# A package passes only when gno prints `ok` for it. A package with no test
# file is still compiled: see "No test file" below.
#
# A package listed in ci/known-failing.txt is expected to FAIL. If it starts to
# pass, this script fails too, so the list cannot go stale: remove the entry in
# the pull request that fixes the package.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
gno="${GNO:-gno}"
log="$(mktemp "${TMPDIR:-/tmp}/gno-test.XXXXXX")"
known="$(mktemp "${TMPDIR:-/tmp}/gno-known.XXXXXX")"
probe=""
cleanup() {
  rm -f -- "$log" "$known"
  if [ -n "$probe" ]; then rm -f -- "$probe"; fi
}
trap cleanup EXIT
# An untrapped signal ends bash without running the EXIT trap, which would
# leave a probe file (below) in the tree.
trap 'exit 130' INT
trap 'exit 143' TERM

# One reading of ci/known-failing.txt for every use below: surrounding
# whitespace and a CR are stripped, and blank lines and comments (indented or
# not) are dropped, so the validation and the lookup cannot disagree.
sed -e 's/\r$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
  "$root/ci/known-failing.txt" | grep -v -e '^$' -e '^#' > "$known" || true

is_known() {
  grep -qxF -- "$1" "$known"
}

# Every listed entry must still name a package, or a rename would silently
# turn an expected failure into an untested path.
while IFS= read -r entry; do
  [ -f "$root/$entry/gnomod.toml" ] || {
    echo "::error file=ci/known-failing.txt::$entry is not a package (no gnomod.toml)"
    exit 1
  }
done < "$known"

# No test file: `gno test` on a package with no *_test.gno or *_filetest.gno
# file prints `[no test files]` and exits 0 without compiling anything, so a
# type error in it would pass. `gno lint` is no substitute: it refuses a
# `package main` script whose name differs from its directory, which is every
# script under internal/. So a probe test file holding only the package clause
# is put in the package's own directory for the run, and always removed. gno
# then builds the package exactly as it builds any tested one: same directory,
# same workspace, same import resolution. An existing file of that name is
# refused rather than used, and the probe is created with noclobber, so a file
# this script did not write is never overwritten nor deleted.
probe_name=zz_ci_compile_probe_test.gno
add_probe() {
  local dir="$1" name
  if [ -e "$dir/$probe_name" ]; then
    echo "::error file=$dir/$probe_name::$probe_name is reserved for ci/gno-test.sh; remove it (a run that was killed can leave it behind)"
    return 1
  fi
  if compgen -G "$dir/*_test.gno" > /dev/null ||
     compgen -G "$dir/*_filetest.gno" > /dev/null; then
    return 0
  fi
  name="$(sed -n 's/^package[[:space:]]\{1,\}\([A-Za-z_][A-Za-z0-9_]*\).*/\1/p' "$dir"/*.gno | sort -u)"
  if [ -z "$name" ] || [ "$(printf '%s\n' "$name" | wc -l)" -ne 1 ]; then
    echo "::error file=$dir/gnomod.toml::$dir has no test file and no single package name to compile it under"
    return 1
  fi
  probe="$dir/$probe_name"
  ( set -C; printf 'package %s\n' "$name" > "$probe" ) || {
    probe=""
    echo "::error file=$dir/$probe_name::could not create $probe_name"
    return 1
  }
}

pass=0 expected=0 bad=0
cd "$root"
while IFS= read -r -d '' mod; do
  dir="${mod%/gnomod.toml}"
  if ! add_probe "$dir"; then bad=$((bad + 1)); continue; fi
  if "$gno" test "./$dir" > "$log" 2>&1; then status=ok; else status=fail; fi
  if [ -n "$probe" ]; then rm -f -- "$probe"; probe=""; fi
  # Exit 0 is not enough on its own: gno must also say it tested this package.
  if [ "$status" = ok ] && ! grep -qE "^ok +\./$dir[[:space:]]" "$log"; then
    status=untested
  fi
  if is_known "$dir"; then
    if [ "$status" != fail ]; then
      echo "::error file=$dir/gnomod.toml::$dir now passes: remove it from ci/known-failing.txt"
      sed 's/^/    /' "$log"
      bad=$((bad + 1))
    else
      echo "  expected failure  $dir"
      expected=$((expected + 1))
    fi
  elif [ "$status" = ok ]; then
    echo "  ok                $dir"
    pass=$((pass + 1))
  else
    if [ "$status" = untested ]; then
      echo "::error file=$dir/gnomod.toml::gno test exited 0 for $dir without reporting it ok"
    else
      echo "::error file=$dir/gnomod.toml::gno test failed for $dir"
    fi
    sed 's/^/    /' "$log"
    bad=$((bad + 1))
  fi
done < <(find gno -name gnomod.toml -print0 | LC_ALL=C sort -z)

echo
echo "$pass passed, $expected failed as expected (ci/known-failing.txt), $bad unexpected"

# Nothing found is not a pass: a moved gno/ or a broken find would otherwise
# end here with every counter at zero and exit 0.
if [ $((pass + expected + bad)) -eq 0 ]; then
  echo "::error::no package found under gno/, so nothing was tested"
  exit 1
fi
[ "$bad" -eq 0 ]
