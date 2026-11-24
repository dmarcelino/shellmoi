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
# would through the login shell. -O (control commands) does nothing. With INSTALL_FAIL_AT=n,
# the nth command that runs the remote's install.sh fails instead.
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
case "$*" in
    */install.sh*)
        echo x >> "$INSTALL_CALLS"
        if [ "$(wc -l < "$INSTALL_CALLS")" -eq "${INSTALL_FAIL_AT:-0}" ]; then
            exit 1
        fi
        ;;
esac
cd "$REMOTE_HOME"
# A clean environment, as sshd gives: nothing of push.sh's, such as SHELLMOI_DIR
exec env -i HOME="$REMOTE_HOME" PATH=/usr/bin:/bin bash -c "$*"
EOF
chmod +x "$work/bin/ssh"
link_rsync3 "$work/bin"

push() {
    env -i HOME="$local_home" PATH="${TEST_PATH:-$work/bin:/usr/bin:/bin}" REMOTE_HOME="$remote_home" \
        SHELLMOI_DIR="$local_clone" SHELLMOI_REPO="$upstream" \
        INSTALL_CALLS="$work/install-calls" INSTALL_FAIL_AT="${INSTALL_FAIL_AT:-}" \
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

push remote --install alpha || fail "push exited non-zero: $(cat "$work/out")"
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
push remote alpha --install || fail "the second push exited non-zero: $(cat "$work/out")"
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
push remote --install --all || fail "push --all exited non-zero: $(cat "$work/out")"
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

## COPY ONLY, THE DEFAULT ##

# A remote without shellmoi: nothing is made there, not even private/
mkdir -p "$work/bare"
env -i HOME="$local_home" PATH="$work/bin:/usr/bin:/bin" REMOTE_HOME="$work/bare" \
    SHELLMOI_DIR="$local_clone" SHELLMOI_REPO="$upstream" \
    bash "$repo/push.sh" remote alpha > "$work/out" 2>&1 &&
    fail "a copy-only push ran against a remote without shellmoi"
grep -q "No shellmoi on remote: pass --install" "$work/out" || fail "push did not suggest --install"
[ -z "$(ls -A "$work/bare")" ] || fail "a copy-only push changed a remote without shellmoi"

push remote && fail "a copy-only push ran without profiles"
grep -q "No profiles given" "$work/out" || fail "push did not ask for profiles"

# A new commit upstream, which an install would bring to the remote's clone
git -C "$upstream" -c user.name=test -c user.email=test@example.com \
    commit --quiet --allow-empty -m 'not for a copy-only push'
remote_head=$(git -C "$remote_home/.local/share/shellmoi" rev-parse HEAD)
put "$private/alpha/.bashrc.d/alpha.sh" 'ALPHA=3'
put "$private/alpha/.config/alpha/settings" 'added=yes'
before=$(snapshot "$remote_home" | grep -v '^\./\.local/share/shellmoi/private/')
push remote alpha || fail "the copy-only push exited non-zero: $(cat "$work/out")"
[ "$(cat "$remote_private/alpha/.bashrc.d/alpha.sh")" = 'ALPHA=3' ] ||
    fail "the copy-only push did not copy the change"
[ "$(cat "$remote_private/alpha/.config/alpha/settings")" = 'added=yes' ] ||
    fail "the copy-only push did not copy the new file"
expect_same "the copy-only push changed the remote outside private/" "$before" \
    "$(snapshot "$remote_home" | grep -v '^\./\.local/share/shellmoi/private/')"
[ "$(git -C "$remote_home/.local/share/shellmoi" rev-parse HEAD)" = "$remote_head" ] ||
    fail "the copy-only push updated the remote's clone"
grep -qE "Updating shellmoi|Linking" "$work/out" && fail "the copy-only push ran an install"
grep -q "^    alpha/.bashrc.d/alpha.sh$" "$work/out" || fail "push did not list the updated file"
[ "$(sed -n "/^Added on remote:$/{n;p;}" "$work/out")" = "    alpha/.config/alpha/settings" ] ||
    fail "push did not list the new file as added: $(cat "$work/out")"
grep -q "Some files are not linked on remote yet" "$work/out" || fail "push did not say to link"
grep -qF "    ~/.local/share/shellmoi/install.sh" "$work/out" || fail "push did not print the install command"

## A FILE ADDED BY A COPY-ONLY PUSH, NEVER LINKED, THEN CHANGED ##

put "$private/alpha/.config/alpha/settings" 'added=changed'
push remote alpha || fail "the push of the unlinked file exited non-zero: $(cat "$work/out")"
[ "$(sed -n "/^Updated on remote/{n;p;}" "$work/out")" = "    alpha/.config/alpha/settings" ] ||
    fail "push did not list the unlinked file as updated: $(cat "$work/out")"
grep -q "Some files are not linked on remote yet" "$work/out" ||
    fail "push did not say to link a changed file that was never linked"
# A change to a linked file needs no install
put "$private/alpha/.bashrc.d/alpha.sh" 'ALPHA=4'
push remote alpha || fail "the push of a linked file exited non-zero: $(cat "$work/out")"
grep -q "not linked" "$work/out" && fail "push said to link a file that is linked"

## A FAILED LINKING ON THE REMOTE ##

put "$private/alpha/.bashrc.d/alpha.sh" 'ALPHA=5'
rm -f "$work/install-calls"
# The first install.sh is the update of shellmoi, the second the linking
INSTALL_FAIL_AT=2 push remote --install alpha && fail "push exited zero with a failed linking"
grep -qF "    ssh remote \"bash -lc '~/.local/share/shellmoi/install.sh'\"" "$work/out" ||
    fail "push did not print the install command as it runs it: $(cat "$work/out")"
[ "$(cat "$remote_private/alpha/.bashrc.d/alpha.sh")" = 'ALPHA=5' ] || fail "the copy before the failed linking was lost"

## A COPY THAT FAILS ##

put "$private/alpha/.bashrc.d/unreadable.sh" 'X=1'
chmod 000 "$private/alpha/.bashrc.d/unreadable.sh"
push remote alpha && fail "push exited zero with a file it could not copy"
chmod 644 "$private/alpha/.bashrc.d/unreadable.sh"
rm "$private/alpha/.bashrc.d/unreadable.sh"
grep -q "Could not copy every file of: alpha" "$work/out" || fail "push did not name the failed profile"
grep -q "Already up to date" "$work/out" && fail "push said up to date when a copy failed"

## SETUP ONLY: NO RSYNC NEEDED HERE ##

push remote --install || fail "push --install with no profiles exited non-zero: $(cat "$work/out")"
grep -q "Checking rsync here" "$work/out" && fail "push --install with no profiles looked for rsync"

## NO RSYNC 3 HERE ##

# Only where /usr/bin and /bin have no rsync 3 or later, as on macOS: there, a PATH without
# the test's rsync has none
if ! { /usr/bin/rsync --version; /bin/rsync --version; } 2>/dev/null |
    grep -qE '^rsync +version +[3-9]\.'; then
    mkdir -p "$work/bin-old"
    ln -sf "$work/bin/ssh" "$work/bin-old/ssh"
    TEST_PATH="$work/bin-old:/usr/bin:/bin" push remote alpha &&
        fail "push ran without rsync 3 here"
    grep -q "needed here: .* Or pass --install." "$work/out" ||
        fail "push did not suggest --install for rsync here: $(cat "$work/out")"
fi

## OPTIONS ##

push remote --help || fail "push remote --help exited non-zero: $(cat "$work/out")"
grep -q "^Usage:" "$work/out" || fail "push remote --help did not print the usage"
push remote "$(printf 'alpha\nbeta')" && fail "push took a name with a newline"
grep -q "Not a profile name" "$work/out" || fail "push did not reject the name with a newline"

echo "PASS: push"
