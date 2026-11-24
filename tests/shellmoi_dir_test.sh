#!/usr/bin/env bash
# Starts an interactive shell from a ~/.bashrc linked into the clone, as the install links
# it, and checks SHELLMOI_DIR: it is the clone, child processes see it, and
# `cd SHELLMOI_DIR` goes there from another folder.
#
#   tests/shellmoi_dir_test.sh

set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# shellcheck source=lib.sh
. "$repo/tests/lib.sh"

ln -s "$repo/.bashrc" "$work/.bashrc"
# .bashrc loads bash-sensible, which turns on cdable_vars, from ~/.config
mkdir -p "$work/.config/bash"
ln -s "$repo/.config/bash/sensible" "$work/.config/bash/sensible"

# shellcheck disable=SC2016  # expanded by the shell under test
result=$(cd / && env -i HOME="$work" PATH=/usr/bin:/bin TERM=dumb \
    bash -i -c 'cd SHELLMOI_DIR >/dev/null; printf "%s %s\n" "$PWD" "$(bash -c "printf %s \"\$SHELLMOI_DIR\"")"' \
    2>/dev/null | tail -n 1)  # the last line: Debian's /etc/bash.bashrc may print a sudo hint first

expect_same "cd SHELLMOI_DIR, then SHELLMOI_DIR in a child process" "$repo $repo" "$result"

echo "PASS: SHELLMOI_DIR"
