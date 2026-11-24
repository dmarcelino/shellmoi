#!/usr/bin/env bash
# Pushes private profiles to a "remote" that is a second fake home on this machine: an ssh
# stub runs the commands here, with that home. No network, no SSH server.
#
#   tests/push_test.sh
#
# The remote clones a copy of the working tree, so it tests uncommitted changes too.
# Needs rsync and git.

set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# shellcheck source=lib.sh
. "$repo/tests/lib.sh"

command -v rsync >/dev/null 2>&1 || fail "this test needs rsync"

upstream=$work/upstream  # what the remote clones, as GitHub would serve it
local_home=$work/local
local_clone=$local_home/.local/share/shellmoi
private=$local_clone/private
remote_home=$work/remote
remote_private=$remote_home/.local/share/shellmoi/private

# The working tree, untracked files included, committed into a repository of its own
git clone --quiet "$repo" "$upstream"
(cd "$repo" && git ls-files -z -co --exclude-standard | grep -zv '^\.worktrees/' |
    xargs -0 tar cf -) | (cd "$upstream" && tar xf -)
git -C "$upstream" add -A
git -C "$upstream" -c user.name=test -c user.email=test@example.com \
    commit --quiet --allow-empty -m 'working tree'

# ssh: drops the options and the host, then runs the command in the remote home, as sshd
# would through the login shell. -O (control commands) does nothing.
mkdir -p "$work/bin" "$local_home" "$remote_home"
cat > "$work/bin/ssh" <<'EOF'
#!/usr/bin/env bash
while [ $# -gt 0 ]; do
    case "$1" in
        -O) exit 0 ;;
        -[oplibcFeEJLRDwW]) shift 2 ;;
        -*) shift ;;
        *) break ;;
    esac
done
shift
cd "$REMOTE_HOME"
# A clean environment, as sshd gives: nothing of push.sh's, such as SHELLMOI_DIR
exec env -i HOME="$REMOTE_HOME" PATH=/usr/bin:/bin bash -c "$*"
EOF
chmod +x "$work/bin/ssh"
link_rsync3 "$work/bin"

push() {
    env -i HOME="$local_home" PATH="$work/bin:/usr/bin:/bin" REMOTE_HOME="$remote_home" \
        SHELLMOI_DIR="$local_clone" SHELLMOI_REPO="$upstream" \
        bash "$repo/push.sh" "$@" > "$work/out" 2>&1
}

git clone --quiet "$upstream" "$local_clone"
put "$private/alpha/.bashrc.d/alpha.sh" 'ALPHA=1
export API_TOKEN=do-not-print'
put "$private/alpha/.ssh/config.d/alpha.conf" 'Host alpha-host'
put "$private/alpha/.config/git/profiles/alpha.gitconfig" '[github]
	token = do-not-print-either'
put "$private/alpha/.ssh/id_test" '-----BEGIN OPENSSH PRIVATE KEY-----
not-a-real-key'
put "$private/beta/.bashrc.d/beta.sh" 'BETA=1'

## A REMOTE WITHOUT SHELLMOI ##

push remote alpha || fail "push exited non-zero: $(cat "$work/out")"
grep -q "Installing shellmoi on remote" "$work/out" || fail "push did not install shellmoi"
[ -d "$remote_home/.local/share/shellmoi/.git" ] || fail "the remote has no shellmoi clone"
[ "$(readlink "$remote_home/.bashrc.d/alpha.sh")" = "$remote_private/alpha/.bashrc.d/alpha.sh" ] ||
    fail "the remote's ~/.bashrc.d/alpha.sh is not linked to the copied profile"
[ "$(cat "$remote_home/.bashrc.d/alpha.sh")" = "$(cat "$private/alpha/.bashrc.d/alpha.sh")" ] ||
    fail "the remote's alpha.sh differs from the pushed one"
[ -L "$remote_home/.ssh/config.d/alpha.conf" ] || fail "the remote's SSH settings are not linked"
[ ! -e "$remote_private/beta" ] && [ ! -e "$remote_home/.bashrc.d/beta.sh" ] ||
    fail "push copied a profile it was not given"
[ -d "$remote_private/.git" ] || fail "the remote's private folder is not a git repository"

# The secret warning names the file and line, not the value
grep -q "alpha/.bashrc.d/alpha.sh:2:TOKEN" "$work/out" || fail "push did not warn about API_TOKEN"
grep -q "alpha/.config/git/profiles/alpha.gitconfig:2:token" "$work/out" ||
    fail "push did not warn about a lower-case token"
grep -q "alpha/.ssh/id_test:1:PRIVATE KEY" "$work/out" || fail "push did not warn about a private key"
grep -qE 'do-not-print|not-a-real-key' "$work/out" && fail "push printed a secret's value"

## A REMOTE WITH SHELLMOI: AN UPDATE ##

put "$private/alpha/.bashrc.d/alpha.sh" 'ALPHA=2'
# An rsync older than 3 first on the remote's PATH, as macOS's own: push uses a newer one
put "$remote_home/.local/bin/rsync" '#!/bin/sh
if [ "$1" = --version ]; then echo "rsync  version 2.6.9  protocol version 29"; exit 0; fi
touch "$HOME/old-rsync-ran"
exit 1'
chmod +x "$remote_home/.local/bin/rsync"
push remote alpha || fail "the second push exited non-zero: $(cat "$work/out")"
[ ! -e "$remote_home/old-rsync-ran" ] || fail "push used the remote's rsync older than 3"
rm "$remote_home/.local/bin/rsync"
grep -q "Updating shellmoi on remote" "$work/out" || fail "the second push did not update shellmoi"
[ "$(cat "$remote_home/.bashrc.d/alpha.sh")" = 'ALPHA=2' ] || fail "the change did not reach the remote"
backups=$(cd "$remote_private/.backups" && find . -type f | sort)
[ "$(echo "$backups" | sed 's|^\./[^/]*/||')" = alpha/.bashrc.d/alpha.sh ] ||
    fail "expected a backup of the changed file only, found: $backups"
[ "$(cat "$remote_private/.backups"/*/alpha/.bashrc.d/alpha.sh)" = "ALPHA=1
export API_TOKEN=do-not-print" ] || fail "the backup does not hold the file as it was"
[ ! -e "$remote_home/alpha" ] && [ ! -e "$remote_home/.bashrc.d/alpha.sh.bak" ] ||
    fail "the backups were linked into the remote home"

## ALL PROFILES ##

# alpha is on the remote already, beta not yet
push remote --all || fail "push --all exited non-zero: $(cat "$work/out")"
[ "$(readlink "$remote_home/.bashrc.d/beta.sh")" = "$remote_private/beta/.bashrc.d/beta.sh" ] ||
    fail "push --all did not copy and link beta"
[ "$(readlink "$remote_home/.bashrc.d/alpha.sh")" = "$remote_private/alpha/.bashrc.d/alpha.sh" ] ||
    fail "push --all unlinked alpha"
push remote --all alpha && fail "push accepted --all with a profile name"
grep -q -- "--all takes no profile names" "$work/out" || fail "push did not reject --all alpha"

## A HOST THAT LOOKS LIKE AN OPTION ##

push -oProxyCommand=true alpha && fail "push took an ssh option as the host"
grep -q "Not a host: -oProxyCommand=true" "$work/out" || fail "push did not reject the host"

## AN UNKNOWN PROFILE ##

push remote nope && fail "push accepted an unknown profile"
grep -q "No profile nope" "$work/out" || fail "push did not name the unknown profile"

echo "PASS: push"
