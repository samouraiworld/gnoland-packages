#!/usr/bin/env bash
# Runs `gno test` on every package under gno/, one package at a time, with the
# gno binary given in $GNO (default: `gno` on PATH).
#
# A package passes only when gno prints `ok` for it. A package with no test
# file is still compiled: see "No test file" below.
#
# A package listed in ci/known-failing.txt is expected to FAIL, on the cause
# the list pins for it and on nothing else. If it starts to pass, this script
# fails too, so the list cannot go stale: remove the entry in the pull request
# that fixes the package.
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
# whitespace and a CR are stripped, blank lines and comments (indented or not)
# are dropped, and each entry becomes "<package>\t<cause>", so the validation
# and the lookups cannot disagree.
awk '{
  sub(/\r$/, ""); sub(/^[ \t]+/, ""); sub(/[ \t]+$/, "")
  if ($0 == "" || substr($0, 1, 1) == "#") next
  pkg = $1; cause = $0
  sub(/^[^ \t]+[ \t]*/, "", cause)
  print pkg "\t" cause
}' "$root/ci/known-failing.txt" > "$known"

# awk rather than `cut | grep -q`: grep -q exits at the first match, and under
# pipefail the writer it leaves behind can fail the pipeline on a match.
is_known() {
  awk -F'\t' -v pkg="$1" '$1 == pkg { found = 1 } END { exit !found }' "$known"
}

# Every listed entry must still name a package, or a rename would silently
# turn an expected failure into an untested path. And every entry must pin a
# cause: a bare package name would accept any failure at all.
while IFS=$'\t' read -r entry cause; do
  [ -f "$root/$entry/gnomod.toml" ] || {
    echo "::error file=ci/known-failing.txt::$entry is not a package (no gnomod.toml)"
    exit 1
  }
  [ -n "$cause" ] || {
    echo "::error file=ci/known-failing.txt::$entry pins no cause; write the error it is expected to fail on after the package"
    exit 1
  }
done < "$known"

# unexplained <package>: prints every line of $log that the causes pinned for
# <package> do not account for, then every pinned cause the log does not show.
# Empty output means the package failed exactly as pinned.
#
# A cause is a fixed string, never a regular expression, so a `.` in an import
# path cannot match more than it says. A line is accounted for when it:
#   - contains a pinned cause;
#   - is progress or the frame of an error dump, which carries no message of
#     its own (the message is on its `Msg Traces` line, which must be pinned);
#   - is gno's summary of this package's failure;
#   - or, for a cause `package "X" is not available`, is one of the three
#     lines gno prints because X could not be fetched: the failed file query,
#     the `[setup failed]` line for X, and the failed open of X's directory.
# Anything else, a type error, a panic, a failing test, an import that is not
# pinned, is an error nobody expected, and the package fails the job.
unexplained() {
  awk -F'\t' -v pkg="$1" -v logf="$log" '
    function ends(s, suf) {
      return length(s) >= length(suf) && substr(s, length(s) - length(suf) + 1) == suf
    }
    $1 == pkg {
      n++; cause[n] = $2; seen[n] = 0
      if (match($2, /^package "[^"]+" is not available$/))
        missing[n] = substr($2, 10, length($2) - 9 - length("\" is not available"))
    }
    END {
      while ((getline line < logf) > 0) {
        explained = 0
        for (i = 1; i <= n; i++)
          if (index(line, cause[i])) { seen[i] = 1; explained = 1 }
        if (explained) continue
        l = line; gsub(/[ \t]+/, " ", l); sub(/^ /, "", l); sub(/ $/, "", l)
        if (l ~ /^gno: downloading [^ ]+$/ ||
            l == "--= Error =--" || l == "Msg Traces:" || l == "Stack Trace:" ||
            l == "Data: &vm.InvalidPackageError{abciError:vm.abciError{}}" ||
            l ~ /^[0-9]+ [^ ]+\.go:[0-9]+$/ ||
            l ~ /^\.\.\. [0-9]+ more lines elided$/ ||
            l == "FAIL" || l ~ /^FAIL: [0-9]+ build errors, [0-9]+ test errors$/ ||
            (index(l, "FAIL ./" pkg " ") == 1 && l ~ / [0-9.]+s$/))
          continue
        for (i = 1; i <= n; i++) {
          x = missing[i]
          if (x == "") continue
          if (ends(l, "/pkg/mod/" x ": query files list for pkg \"" x "\": qfile failed: invalid package") ||
              (index(l, "FAIL ") == 1 && ends(l, "/pkg/mod/" x " [setup failed]")) ||
              (index(l, ":0: open ") && ends(l, "/pkg/mod/" x ": no such file or directory (code=gnoUnknownError)"))) {
            explained = 1; break
          }
        }
        if (!explained) print "    unexpected: " line
      }
      for (i = 1; i <= n; i++)
        if (!seen[i]) print "    pinned cause not shown: " cause[i]
    }' "$known"
}

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
      continue
    fi
    why="$(unexplained "$dir")"
    if [ -z "$why" ]; then
      echo "  expected failure  $dir"
      expected=$((expected + 1))
    else
      echo "::error file=$dir/gnomod.toml::$dir failed, but not only on the cause ci/known-failing.txt pins for it"
      printf '%s\n' "$why"
      echo "    full output:"
      sed 's/^/      /' "$log"
      bad=$((bad + 1))
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
