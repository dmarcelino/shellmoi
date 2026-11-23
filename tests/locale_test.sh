#!/usr/bin/env bash
# Sources .bashrc in a clean, non-interactive shell and checks the locale it leaves behind:
# a UTF-8 one this host has when none was set, and the caller's own when one was.
#
#   tests/locale_test.sh

set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

# Prints LANG after sourcing .bashrc with only HOME, PATH and the given variables set;
# stderr goes to $work/err. Non-interactive, as for `ssh host tmux`, so this also checks
# the locale is set before .bashrc returns early.
lang_after_bashrc() {
    env -i HOME="$work" PATH=/usr/bin:/bin "$@" \
        bash -c '. "$1"; printf %s "${LANG-}"' _ "$repo/.bashrc" 2> "$work/err"
}

# No locale at all, as SSH from Windows sends
lang=$(lang_after_bashrc)
[ -n "$lang" ] || fail "no locale set: LANG is still empty"
[ ! -s "$work/err" ] || fail "no locale set: .bashrc wrote to stderr: $(cat "$work/err")"
charmap=$(env -i LANG="$lang" locale charmap 2>/dev/null)
[ "$charmap" = UTF-8 ] || fail "no locale set: LANG=$lang has charmap $charmap, not UTF-8"

# The caller's LANG is kept
lang=$(lang_after_bashrc LANG=fr_FR.UTF-8)
[ "$lang" = fr_FR.UTF-8 ] || fail "LANG=fr_FR.UTF-8 given: LANG became '$lang'"

# LC_ALL alone counts as a locale; LANG is not filled in
lang=$(lang_after_bashrc LC_ALL=C)
[ -z "$lang" ] || fail "LC_ALL=C given: LANG became '$lang'"

echo "PASS: locale"
