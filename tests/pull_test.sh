#!/usr/bin/env bash
# Pulls private profiles from a "remote" that is a second fake home on this machine: an ssh
# stub runs the commands here, with that home. No network, no SSH server. push.sh sets the
# remote up first.
#
#   tests/pull_test.sh
#
# The clones are of a copy of the working tree, so it tests uncommitted changes too.
# Needs rsync 3 or later and git.

set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# shellcheck source=lib.sh
. "$repo/tests/lib.sh"

upstream=$work/upstream  # what the clones come from, as GitHub would serve it
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
# A clean environment, as sshd gives: nothing of the caller's, such as SHELLMOI_DIR
exec env -i HOME="$REMOTE_HOME" PATH=/usr/bin:/bin bash -c "$*"
EOF
chmod +x "$work/bin/ssh"
link_rsync3 "$work/bin"

# Runs the script from the working tree, as the local user, against the remote home
run() {
    local script=$1
    shift
    env -i HOME="$local_home" PATH="$work/bin:/usr/bin:/bin" REMOTE_HOME="${REMOTE:-$remote_home}" \
        SHELLMOI_DIR="$local_clone" SHELLMOI_REPO="$upstream" SHELLMOI_SYSTEM_ROOT="$work/root" \
        bash "$repo/$script" "$@" > "$work/out" 2>&1
}

commit_private() {
    git -C "$private" add -A
    git -C "$private" -c user.name=test -c user.email=test@example.com commit --quiet -m "$1"
}

git clone --quiet "$upstream" "$local_clone"
put "$private/alpha/.bashrc.d/alpha.sh" 'ALPHA=1'
put "$private/alpha/.ssh/config.d/alpha.conf" 'Host alpha-host'
put "$private/alpha/.system/etc/shellmoi-test.conf" 'v=1'
# A login shell on the remote that prints a greeting: not a profile, nor rsync's path
put "$remote_home/.profile" 'echo Welcome'
run push.sh remote --install alpha || fail "the push that sets up the remote failed: $(cat "$work/out")"
grep -q "command not found" "$work/out" && fail "push ran the remote's greeting as rsync: $(cat "$work/out")"
# The local install, so the profile is linked here as it would be
env -i HOME="$local_home" PATH="/usr/bin:/bin" SHELLMOI_DIR="$local_clone" SHELLMOI_SYSTEM_ROOT="$work/root" \
    bash "$local_clone/install.sh" > "$work/out" 2>&1 || fail "install failed: $(cat "$work/out")"
git -C "$private" init --quiet
commit_private 'before pull'

# Edited on the remote: one file changed, one added, a new profile
put "$remote_private/alpha/.bashrc.d/alpha.sh" 'ALPHA=2'
put "$remote_private/alpha/.config/alpha/settings" 'added=yes'
put "$remote_private/gamma/.bashrc.d/gamma.sh" 'GAMMA=1'

## PULLING ONE PROFILE ##

before=$(snapshot "$remote_home")
run pull.sh remote --install alpha || fail "pull exited non-zero: $(cat "$work/out")"
expect_same "pull changed the remote" "$before" "$(snapshot "$remote_home")"
grep -q "command not found" "$work/out" && fail "pull ran the remote's greeting as rsync: $(cat "$work/out")"
[ "$(cat "$private/alpha/.bashrc.d/alpha.sh")" = 'ALPHA=2' ] || fail "the change did not come back"
[ "$(cat "$local_home/.bashrc.d/alpha.sh")" = 'ALPHA=2' ] || fail "the linked file is not the pulled one"
[ "$(readlink "$local_home/.config/alpha/settings")" = "$private/alpha/.config/alpha/settings" ] ||
    fail "the added file is not linked into the local home"
[ ! -e "$private/gamma" ] || fail "pull copied a profile it was not given"
backups=$(cd "$private/.backups" && find . -type f | sort)
[ "$(echo "$backups" | sed 's|^\./[^/]*/||')" = alpha/.bashrc.d/alpha.sh ] ||
    fail "expected a backup of the changed file only, found: $backups"
[ "$(cat "$private/.backups"/*/alpha/.bashrc.d/alpha.sh)" = 'ALPHA=1' ] ||
    fail "the backup does not hold the file as it was"
grep -q "^    alpha/.bashrc.d/alpha.sh$" "$work/out" || fail "pull did not list the updated file"
grep -q "^    alpha/.config/alpha/settings$" "$work/out" || fail "pull did not list the added file"
grep -qF "git -C ~/.local/share/shellmoi/private diff -- alpha" "$work/out" || fail "pull did not suggest git diff"
grep -qF "git -C ~/.local/share/shellmoi/private status -- alpha" "$work/out" || fail "pull did not suggest git status"
grep -q "not committed" "$work/out" && fail "pull warned about changes when all were committed"
git -C "$private" diff --quiet -- alpha/.bashrc.d/alpha.sh &&
    fail "git diff does not show the pulled change"

## NOTHING NEW ##

commit_private 'pulled'
# Only its time differs: the content is the same, so it is not copied
touch -t 202001010000 "$remote_private/alpha/.bashrc.d/alpha.sh"
backups=$(find "$private/.backups" -type f | sort)
run pull.sh remote alpha || fail "the second pull exited non-zero: $(cat "$work/out")"
grep -q "Already up to date." "$work/out" || fail "pull did not say it was up to date"
grep -q "git -C" "$work/out" && fail "pull suggested git with nothing changed"
[ "$(find "$private/.backups" -type f | sort)" = "$backups" ] ||
    fail "pull backed up a file whose content had not changed"

## CHANGES NOT COMMITTED HERE ##

put "$private/alpha/.bashrc.d/alpha.sh" 'ALPHA=local'
run pull.sh remote alpha || fail "the pull over a local change exited non-zero: $(cat "$work/out")"
grep -q "Profile alpha has changes not committed" "$work/out" ||
    fail "pull did not warn about the uncommitted change"
[ "$(cat "$private/alpha/.bashrc.d/alpha.sh")" = 'ALPHA=2' ] || fail "pull did not take the remote's file"
grep -rqx 'ALPHA=local' "$private/.backups" || fail "the local change was not kept in a backup"
git -C "$private" checkout --quiet -- alpha

## ALL PROFILES ##

run pull.sh remote --install --all || fail "pull --all exited non-zero: $(cat "$work/out")"
[ "$(readlink "$local_home/.bashrc.d/gamma.sh")" = "$private/gamma/.bashrc.d/gamma.sh" ] ||
    fail "pull --all did not copy and link gamma"
[ "$(readlink "$local_home/.bashrc.d/alpha.sh")" = "$private/alpha/.bashrc.d/alpha.sh" ] ||
    fail "pull --all unlinked alpha"
[ ! -e "$private/Welcome" ] || fail "pull took the remote's greeting for a profile"

## A NEW SYMLINK, NOTHING ELSE ##

commit_private 'all pulled'
ln -s alpha.sh "$remote_private/alpha/.bashrc.d/alpha-link.sh"
run pull.sh remote --install alpha || fail "the pull of a symlink exited non-zero: $(cat "$work/out")"
grep -q "^    alpha/.bashrc.d/alpha-link.sh$" "$work/out" || fail "pull did not list the new symlink"
grep -q "^Updated" "$work/out" && fail "pull listed the new symlink as updated, not added"
[ "$(readlink "$local_home/.bashrc.d/alpha-link.sh")" = "$private/alpha/.bashrc.d/alpha-link.sh" ] ||
    fail "the new symlink is not linked into the local home"

## A SYSTEM FILE CHANGED, NOTHING ELSE ##

commit_private 'symlink pulled'
put "$remote_private/alpha/.system/etc/shellmoi-test.conf" 'v=2'
run pull.sh remote --install alpha || fail "the pull of a system file exited non-zero: $(cat "$work/out")"
grep -q "^    alpha/.system/etc/shellmoi-test.conf$" "$work/out" || fail "pull did not list the system file"
grep -qF "sudo install -m 644 $private/alpha/.system/etc/shellmoi-test.conf" "$work/out" ||
    fail "pull did not print the sudo commands for the changed system file"

## A PROFILE NAME WITH A SPACE ##

commit_private 'system file pulled'
put "$remote_private/my work/.bashrc.d/my-work.sh" 'MY_WORK=1'
run pull.sh remote 'my work' || fail "the pull of 'my work' exited non-zero: $(cat "$work/out")"
[ "$(cat "$private/my work/.bashrc.d/my-work.sh")" = 'MY_WORK=1' ] || fail "'my work' was not copied"
grep -qF "status -- 'my work'" "$work/out" || fail "pull did not quote the profile name"

## ONE PROFILE FAILS ##

commit_private 'my work pulled'
put "$remote_private/alpha/.bashrc.d/unreadable.sh" 'X=1'
chmod 000 "$remote_private/alpha/.bashrc.d/unreadable.sh"
put "$remote_private/gamma/.bashrc.d/gamma-more.sh" 'MORE=1'
run pull.sh remote --install --all && fail "pull exited zero with a file it could not copy"
chmod 644 "$remote_private/alpha/.bashrc.d/unreadable.sh"
grep -q "Could not copy every file of: alpha" "$work/out" || fail "pull did not name the failed profile"
[ "$(readlink "$local_home/.bashrc.d/gamma-more.sh")" = "$private/gamma/.bashrc.d/gamma-more.sh" ] ||
    fail "after alpha failed, gamma's new file was not copied and linked"
grep -q "^    gamma/.bashrc.d/gamma-more.sh$" "$work/out" || fail "pull did not list what it copied"

## THE INSTALL FAILS ##

run pull.sh remote alpha || fail "the pull that finishes alpha exited non-zero: $(cat "$work/out")"
commit_private 'all pulled again'
put "$remote_private/alpha/.bashrc.d/alpha-new.sh" 'NEW=1'
# Its update of the clone cannot reach the upstream
mv "$upstream" "$work/upstream-away"
run pull.sh remote --install alpha && fail "pull exited zero with a failed install"
mv "$work/upstream-away" "$upstream"
grep -q "^    alpha/.bashrc.d/alpha-new.sh$" "$work/out" || fail "a failed install hid the summary"
grep -q "install.sh failed" "$work/out" || fail "pull did not say the install failed"

## COPY ONLY, THE DEFAULT ##

git -C "$private" add -A
git -C "$private" -c user.name=test -c user.email=test@example.com commit --quiet -m 'before copy only'
# A new commit upstream, which an install would bring to the local clone
git -C "$upstream" -c user.name=test -c user.email=test@example.com \
    commit --quiet --allow-empty -m 'not for a copy-only pull'
local_head=$(git -C "$local_clone" rev-parse HEAD)
put "$remote_private/alpha/.bashrc.d/alpha-copy.sh" 'COPY=1'
put "$remote_private/alpha/.system/etc/shellmoi-test.conf" 'v=3'
run pull.sh remote alpha || fail "the copy-only pull exited non-zero: $(cat "$work/out")"
[ "$(cat "$private/alpha/.bashrc.d/alpha-copy.sh")" = 'COPY=1' ] || fail "the copy-only pull did not copy"
[ ! -e "$local_home/.bashrc.d/alpha-copy.sh" ] || fail "the copy-only pull linked the new file"
[ "$(git -C "$local_clone" rev-parse HEAD)" = "$local_head" ] ||
    fail "the copy-only pull updated the local clone"
grep -qE "==> Linking|sudo install" "$work/out" && fail "the copy-only pull ran install.sh"
grep -q "Some files are not linked yet" "$work/out" || fail "the copy-only pull did not say to link"
grep -qF "    ~/.local/share/shellmoi/install.sh" "$work/out" ||
    fail "the copy-only pull did not print the install command"

# The file it added, not linked, then changed there: still to link, and --install links it
put "$remote_private/alpha/.bashrc.d/alpha-copy.sh" 'COPY=2'
run pull.sh remote alpha || fail "the pull of the unlinked file exited non-zero: $(cat "$work/out")"
grep -q "Some files are not linked yet" "$work/out" ||
    fail "pull did not say to link a changed file that was never linked"
put "$remote_private/alpha/.bashrc.d/alpha-copy.sh" 'COPY=3'
run pull.sh remote --install alpha || fail "the pull --install of it exited non-zero: $(cat "$work/out")"
[ "$(readlink "$local_home/.bashrc.d/alpha-copy.sh")" = "$private/alpha/.bashrc.d/alpha-copy.sh" ] ||
    fail "pull --install did not link the changed file that was never linked"
# A change to a linked file needs no install
put "$remote_private/alpha/.bashrc.d/alpha-copy.sh" 'COPY=4'
run pull.sh remote alpha || fail "the pull of a linked file exited non-zero: $(cat "$work/out")"
grep -q "not linked" "$work/out" && fail "pull said to link a file that is linked"

## A COPY THAT FAILS, WITH NOTHING COPIED ##

put "$remote_private/alpha/.bashrc.d/unreadable.sh" 'X=1'
chmod 000 "$remote_private/alpha/.bashrc.d/unreadable.sh"
run pull.sh remote alpha && fail "pull exited zero with a file it could not copy"
chmod 644 "$remote_private/alpha/.bashrc.d/unreadable.sh"
rm "$remote_private/alpha/.bashrc.d/unreadable.sh"
grep -q "Could not copy every file of: alpha" "$work/out" || fail "pull did not name the failed profile"
grep -q "Already up to date" "$work/out" && fail "pull said up to date when a copy failed"

## NO COMMITS YET ##

mv "$private/.git" "$work/private-git"
git -C "$private" init --quiet
put "$remote_private/alpha/.bashrc.d/alpha.sh" 'ALPHA=3'
run pull.sh remote alpha || fail "the pull without commits exited non-zero: $(cat "$work/out")"
grep -q "has no commits yet" "$work/out" || fail "pull suggested git diff without commits"
review=$(sed -n '/^Review the changes:$/{n;p;}' "$work/out")
(HOME=$local_home bash -c "$review") > "$work/review" || true
grep -qx '+ALPHA=3' "$work/review" || fail "the suggested review does not show the change: $review"
rm -rf "$private/.git"
mv "$work/private-git" "$private/.git"

## REJECTED ##

run pull.sh remote --all alpha && fail "pull accepted --all with a profile name"
grep -q -- "--all takes no profile names" "$work/out" || fail "pull did not reject --all alpha"
run pull.sh remote && fail "pull ran without profiles"
grep -q "No profiles given" "$work/out" || fail "pull did not ask for profiles"
run pull.sh -oProxyCommand=true alpha && fail "pull took an ssh option as the host"
grep -q "Not a host: -oProxyCommand=true" "$work/out" || fail "pull did not reject the host"
run pull.sh remote nope && fail "pull accepted a profile the remote does not have"
grep -q "No profile nope on remote" "$work/out" || fail "pull did not name the unknown profile"
run pull.sh remote --help || fail "pull remote --help exited non-zero: $(cat "$work/out")"
grep -q "^Usage:" "$work/out" || fail "pull remote --help did not print the usage"
run pull.sh remote "$(printf 'alpha\ngamma')" && fail "pull took a name with a newline"
grep -q "Not a profile name" "$work/out" || fail "pull did not reject the name with a newline"
run pull.sh remote ../alpha && fail "pull accepted a path as a profile"
grep -q "Not a profile name" "$work/out" || fail "pull did not reject the path"
mkdir -p "$work/bare"
REMOTE=$work/bare run pull.sh remote alpha && fail "pull ran against a remote without shellmoi"
grep -q "No private profiles on remote" "$work/out" || fail "pull did not say the remote has none"

echo "PASS: pull"
