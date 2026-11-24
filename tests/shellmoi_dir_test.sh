#!/usr/bin/env bash
# Starts interactive shells from a ~/.bashrc linked into the clone in different ways and
# checks SHELLMOI_DIR: it is the clone's absolute path, child processes see it, and
# `cd SHELLMOI_DIR` goes there from another folder. A .bashrc outside a clone sets none.
#
#   tests/shellmoi_dir_test.sh

set -euo pipefail

# Physical path: SHELLMOI_DIR has the links on the way resolved
repo=$(cd -P "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# shellcheck source=lib.sh
. "$repo/tests/lib.sh"

# Makes a home with bash-sensible in ~/.config, where the install links it: it turns on
# cdable_vars, which `cd SHELLMOI_DIR` needs
make_home() {
    local home=$work/$1
    mkdir -p "$home/.config/bash"
    ln -s "$repo/.config/bash/sensible" "$home/.config/bash/sensible"
    echo "$home"
}

# Starts an interactive shell in / with the home, runs the commands, then prints the folder
# `cd SHELLMOI_DIR` goes to and SHELLMOI_DIR as a child process sees it
probe() {
    local home=$1 commands=${2:-:}
    # shellcheck disable=SC2016  # expanded by the shell under test
    (cd / && env -i HOME="$home" PATH=/usr/bin:/bin TERM=dumb bash -i -c "$commands"'
        cd / && cd SHELLMOI_DIR >/dev/null 2>&1
        printf "%s %s\n" "$PWD" "$(bash -c "printf %s \"\${SHELLMOI_DIR-unset}\"")"' \
        2>/dev/null | tail -n 1)  # the last line: Debian's /etc/bash.bashrc may print a sudo hint first
}

# ~/.bashrc links to the clone's file by an absolute path, as the install links it
home=$(make_home absolute)
ln -s "$repo/.bashrc" "$home/.bashrc"
expect_same "absolute link" "$repo $repo" "$(probe "$home")"

# A relative link, as GNU stow makes, read from another folder
home=$(make_home relative)
mkdir -p "$home/.local/share"
ln -s "$repo" "$home/.local/share/shellmoi"
ln -s .local/share/shellmoi/.bashrc "$home/.bashrc"
expect_same "relative link" "$repo $repo" "$(probe "$home")"

# A chain of links: ~/.bashrc to a dotfiles folder, which links to the clone
home=$(make_home chain)
mkdir -p "$home/dotfiles"
ln -s "$repo/.bashrc" "$home/dotfiles/bashrc"
ln -s dotfiles/bashrc "$home/.bashrc"
expect_same "chain of links" "$repo $repo" "$(probe "$home")"

# Sourced by a relative path from inside the clone, as when reloading it after an edit
home=$(make_home sourced)
expect_same "sourced as . .bashrc" "$repo $repo" \
    "$(probe "$home" "cd $(printf %q "$repo") && . .bashrc")"

# A copy of .bashrc is in no clone: SHELLMOI_DIR stays unset, so the scripts use their default
home=$(make_home copied)
cp "$repo/.bashrc" "$home/.bashrc"
expect_same "copied .bashrc" "/ unset" "$(probe "$home")"

echo "PASS: SHELLMOI_DIR"
