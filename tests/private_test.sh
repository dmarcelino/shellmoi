#!/usr/bin/env bash
# Installs two private profiles into a fake home and checks the links, the drop-in files
# that load them in Bash, SSH and git, and that uninstall puts the home back as it was.
#
#   tests/private_test.sh
#
# The clone gets the working tree's tracked files, so it tests uncommitted changes too.

set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
home=$work/home
clone=$work/clone
private=$clone/private

# shellcheck source=lib.sh
. "$repo/tests/lib.sh"

shellmoi() {
    HOME=$home SHELLMOI_DIR=$clone bash "$repo/install.sh" "$@" > "$work/out" 2>&1 ||
        fail "install.sh $* exited non-zero: $(cat "$work/out")"
}

git clone --quiet "$repo" "$clone"
(cd "$repo" && git ls-files -z | xargs -0 tar cf -) | (cd "$clone" && tar xf -)

# Two profiles: each has drop-in files of its own, and both have .shared
put "$private/alpha/.bashrc.d/alpha.sh" 'ALPHA_LOADED=yes'
put "$private/alpha/.ssh/config.d/alpha.conf" 'Host alpha-host'
put "$private/alpha/.config/git/profiles/alpha.gitconfig" '[user]
	email = alpha@example.com'
put "$private/alpha/.shared" 'from alpha'
put "$private/beta/.bashrc.d/beta.sh" 'BETA_LOADED=yes'
put "$private/beta/.config/git/profiles/beta.gitconfig" "[includeIf \"gitdir:$home/work/\"]
	path = beta-work.inc"
put "$private/beta/.config/git/profiles/beta-work.inc" '[user]
	email = beta@example.com'
put "$private/beta/.shared" 'from beta'
# Paths shellmoi links itself: a profile does not replace them
put "$private/alpha/.inputrc" 'from alpha'
put "$private/alpha/.claude/skills/owl/extra.md" 'from alpha'
# Leftovers of Finder and editors
put "$private/alpha/.DS_Store" 'finder'
put "$private/alpha/.bashrc.d/alpha.sh~" 'editor backup'
put "$private/alpha/.bashrc.d/.alpha.sh.swp" 'vim swap'
# Not profiles: the private repository itself, and push.sh's backups
git init --quiet "$private"
put "$private/.backups/20200101-000000/alpha/.old" 'backup'

# Files in the way of links: one a profile's, one shellmoi's that a profile also has
put "$home/.bashrc.d/alpha.sh" 'original alpha.sh'
put "$home/.inputrc" 'original inputrc'

before=$(snapshot "$home")

shellmoi
shellmoi

[ "$(readlink "$home/.bashrc.d/alpha.sh")" = "$private/alpha/.bashrc.d/alpha.sh" ] ||
    fail "install did not link alpha's ~/.bashrc.d/alpha.sh"
[ "$(readlink "$home/.bashrc.d/beta.sh")" = "$private/beta/.bashrc.d/beta.sh" ] ||
    fail "install did not link beta's ~/.bashrc.d/beta.sh"
[ "$(cat "$home"/.bashrc.d/alpha.sh.bak.*)" = 'original alpha.sh' ] ||
    fail "install did not back up the file in the way"

[ "$(cat "$home/.shared")" = 'from alpha' ] || fail "~/.shared is not the first profile's"
grep -q "skipped        ~/.shared of profile beta" "$work/out" ||
    fail "install did not report the file both profiles have"
[ ! -e "$home/.old" ] && [ ! -e "$home/HEAD" ] && [ ! -e "$home/20200101-000000" ] ||
    fail "install linked files from private/.backups or private/.git"

# shellmoi's own .inputrc stays linked, the user's original is kept, once, and the
# profile's copy is skipped; likewise a file inside a skill, which would land in the clone
[ "$(readlink "$home/.inputrc")" = "$clone/.inputrc" ] || fail "a profile replaced ~/.inputrc"
backups=$(cd "$home" && ls -d .inputrc.bak.*)
[ "$(echo "$backups" | wc -l)" -eq 1 ] && [ "$(cat "$home/$backups")" = 'original inputrc' ] ||
    fail "the original ~/.inputrc is not kept in one backup: $backups"
grep -q "skipped        ~/.inputrc of profile alpha (shellmoi links it)" "$work/out" ||
    fail "install did not report the profile's ~/.inputrc as skipped"
[ ! -e "$clone/skills/owl/extra.md" ] || fail "a profile's file was put inside a skill"

for junk in .DS_Store .bashrc.d/alpha.sh~ .bashrc.d/.alpha.sh.swp; do
    [ ! -e "$home/$junk" ] && [ ! -L "$home/$junk" ] || fail "install linked ~/$junk"
done

# Bash loads every ~/.bashrc.d/*.sh
loaded=$(env -i HOME="$home" PATH=/usr/bin:/bin TERM=dumb \
    bash --rcfile "$repo/.bashrc" -i -c 'echo "$ALPHA_LOADED $BETA_LOADED"' 2>/dev/null |
    tail -n 1)  # the last line: Debian's /etc/bash.bashrc may print a sudo hint first
[ "$loaded" = "yes yes" ] || fail "an interactive shell did not load ~/.bashrc.d: '$loaded'"

# SSH: a new ~/.ssh/config includes the profiles' files, readable by the owner only
[ "$(cat "$home/.ssh/config")" = "# Written by shellmoi's install.sh: loads the private profiles' SSH settings
Include config.d/*.conf" ] || fail "install did not write ~/.ssh/config: $(cat "$home/.ssh/config")"
[ "$(ls -l "$home/.ssh/config" | cut -c1-10)" = -rw------- ] ||
    fail "~/.ssh/config can be read by others"

# git: the profiles' settings apply, a conditional include included
mkdir -p "$home/work" "$home/other"
git -C "$home/work" init --quiet
git -C "$home/other" init --quiet
email() {
    (cd "$1" && HOME=$home XDG_CONFIG_HOME= GIT_CONFIG_NOSYSTEM=1 git config user.email)
}
[ "$(email "$home/other")" = alpha@example.com ] || fail "git did not use alpha's email"
[ "$(email "$home/work")" = beta@example.com ] || fail "git did not use beta's email in ~/work"
rm -rf "$home/work" "$home/other"

shellmoi uninstall
grep -q "deleting the clone deletes them" "$work/out" ||
    fail "uninstall did not warn that the clone holds the profiles"
expect_same "uninstall did not restore the home as it was" "$before" "$(snapshot "$home")"

## AN EXISTING ~/.ssh/config ##

# Says how to include the profiles' SSH settings unless the config does, before any Host:
# inside a Host block, an Include applies to that host only
ssh_hint() {
    home=$work/ssh-$1
    put "$home/.ssh/config" "$2"
    shellmoi
    [ "$(cat "$home/.ssh/config")" = "$2" ] || fail "install edited an existing ~/.ssh/config"
    grep -q "    Include config.d/\*.conf" "$work/out"
}
ssh_hint none 'Host mine' || fail "no hint for a ~/.ssh/config without the Include"
ssh_hint in-host 'Host mine
  User me
Include config.d/*.conf' || fail "no hint for an Include inside a Host block"
ssh_hint top 'Include config.d/*.conf
Host mine' && fail "a hint for a ~/.ssh/config that includes the profiles"

## A PROFILE RENAMED, A FILE REMOVED ##

# Its old links are replaced or removed, not backed up as if they were the user's files
rm -rf "$private/alpha" "$private/beta"
put "$private/old/.bashrc.d/old.sh" 'OLD=1'
put "$private/old/.ssh/config.d/old.conf" 'Host old-host'
home=$work/home-renamed
mkdir -p "$home"
before=$(snapshot "$home")
shellmoi
mv "$private/old" "$private/new"
rm "$private/new/.ssh/config.d/old.conf"
shellmoi
[ "$(readlink "$home/.bashrc.d/old.sh")" = "$private/new/.bashrc.d/old.sh" ] ||
    fail "the renamed profile's file is not linked"
[ ! -e "$home/.ssh/config.d/old.conf" ] && [ ! -L "$home/.ssh/config.d/old.conf" ] ||
    fail "the link to a removed profile file stayed"
leftovers=$(cd "$home" && find . -name '*.bak.*')
[ -z "$leftovers" ] || fail "install backed up its own links: $leftovers"
shellmoi uninstall
expect_same "uninstall after a rename did not restore the home" "$before" "$(snapshot "$home")"

echo "PASS: private"
