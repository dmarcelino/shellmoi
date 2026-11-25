#!/usr/bin/env bash
# Checks `install.sh system-save` and `install.sh system-apply`, which copy the private
# profiles' .system/ files from the system and onto it, against a stand-in for /.
#
#   tests/system_test.sh
#
# The clone gets the working tree's tracked files, so it tests uncommitted changes too.

set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
# The tests take permissions away; give them back so the folder can go
trap 'chmod -R u+rwx "$work" 2>/dev/null; rm -rf "$work"' EXIT
home=$work/home
clone=$work/clone
private=$clone/private
# A stand-in for /, so the profiles' .system/ files never meet the real system
root=$work/root
mkdir -p "$home" "$root/etc"

# shellcheck source=lib.sh
. "$repo/tests/lib.sh"

[ "$(id -u)" != 0 ] || fail "run this test as a user other than root: it checks permissions"

# A stand-in for sudo: logs the command and runs it as root of a user namespace, which
# reads and writes the test's files whatever their mode. Where there are no user namespaces,
# as on macOS, it makes the stand-in for / writable instead, and the tests of what only root
# can read are skipped.
mkdir -p "$work/bin"
cat > "$work/bin/sudo" <<'EOF'
#!/bin/sh
echo "$*" >> "$SUDO_LOG"
if unshare -r true 2>/dev/null; then
    exec unshare -r "$@"
fi
chmod -R u+w "$SUDO_ROOT"
exec "$@"
EOF
as_root=false
if unshare -r true 2>/dev/null; then
    as_root=true
fi
chmod +x "$work/bin/sudo"
sudo_log=$work/sudo.log
: > "$sudo_log"

# Runs install.sh with the arguments, its input not a terminal, its output in $work/out
run() {
    HOME=$home SHELLMOI_DIR=$clone SHELLMOI_SYSTEM_ROOT=$root PATH="$work/bin:$PATH" \
        SUDO_LOG=$sudo_log SUDO_ROOT=$root \
        bash "$repo/install.sh" "$@" > "$work/out" 2>&1 < /dev/null
}

succeeds() {
    run "$@" || fail "install.sh $* exited non-zero: $(cat "$work/out")"
}

fails() {
    if run "$@"; then
        fail "install.sh $* succeeded: $(cat "$work/out")"
    fi
}

expect_out() {
    grep -qF -- "$1" "$work/out" || fail "$2: $(cat "$work/out")"
}

# Prints the mode of the file, as ls does, seen as root where it can
mode_of() {
    if $as_root; then
        unshare -r ls -ld "$1" | cut -c1-10
    else
        ls -ld "$1" | cut -c1-10
    fi
}

# Prints the file's content in this run's or an earlier run's backups
backup_of() {
    local found
    found=$(find "$private/.backups" -path "*/$1" | head -n 1)
    [ -n "$found" ] || fail "no backup of $1"
    cat "$found"
}

git clone --quiet "$repo" "$clone"
(cd "$repo" && git ls-files -z | xargs -0 tar cf -) | (cd "$clone" && tar xf -)

## SYSTEM-SAVE ##

put "$private/alpha/.system/etc/app.conf" 'from alpha'
put "$private/alpha/.system/etc/missing.conf" 'only in alpha'
put "$private/alpha/.system/etc/same.conf" 'same'
put "$private/beta/.system/etc/app.conf" 'from beta'
put "$private/beta/.system/etc/beta.conf" 'from beta'
put "$root/etc/app.conf" 'changed on the system'
put "$root/etc/same.conf" 'same'
put "$root/etc/beta.conf" 'beta changed on the system'
touch -t 202001010000 "$private/alpha/.system/etc/app.conf"

# With a profile named, only that profile
succeeds system-save alpha
[ "$(cat "$private/alpha/.system/etc/app.conf")" = 'changed on the system' ] ||
    fail "system-save did not copy the system's file into the profile"
[ "$(backup_of alpha/.system/etc/app.conf)" = 'from alpha' ] ||
    fail "system-save did not keep the profile's old copy"
[ "$(cat "$private/alpha/.system/etc/missing.conf")" = 'only in alpha' ] ||
    fail "system-save changed a file missing on the system"
expect_out "missing        /etc/missing.conf" "system-save did not report the missing file"
expect_out "up to date     /etc/same.conf" "system-save did not report the identical file"
[ "$(cat "$private/beta/.system/etc/beta.conf")" = 'from beta' ] ||
    fail "system-save alpha changed profile beta"

# Every profile; the file an earlier profile has stays as it is in the later one
succeeds system-save
[ "$(cat "$private/beta/.system/etc/beta.conf")" = 'beta changed on the system' ] ||
    fail "system-save did not save profile beta"
[ "$(cat "$private/beta/.system/etc/app.conf")" = 'from beta' ] ||
    fail "system-save saved a file an earlier profile has"
expect_out "skipped        /etc/app.conf of profile beta" \
    "system-save did not report the file both profiles have"

# Warns when the profile's copy is the newer one
put "$root/etc/same.conf" 'older on the system'
touch -t 202001010000 "$root/etc/same.conf"
succeeds system-save alpha
expect_out "did you mean system-apply?" "system-save did not warn about the newer profile copy"

# A file only root can read is reported, and the run fails
put "$private/alpha/.system/etc/secret.conf" 'secret'
put "$root/etc/secret.conf" 'root only'
chmod 000 "$root/etc/secret.conf"
fails system-save alpha
expect_out "unreadable     /etc/secret.conf" "system-save did not report the unreadable file"
[ "$(cat "$private/alpha/.system/etc/secret.conf")" = 'secret' ] ||
    fail "system-save changed the profile's copy of an unreadable file"
chmod 600 "$root/etc/secret.conf"
rm "$root/etc/secret.conf" "$private/alpha/.system/etc/secret.conf"

# Names that are not profiles with a .system/ folder, and an option it does not take
fails system-save .git
expect_out "Not a profile name" "system-save took a hidden folder for a profile"
fails system-save nope
expect_out "has no .system folder" "system-save took a missing profile"
fails system-save --yes
[ ! -s "$sudo_log" ] || fail "system-save ran sudo: $(cat "$sudo_log")"

## SYSTEM-APPLY ##

rm -rf "${private:?}"/*/ "$private/.backups" "${root:?}"/*
put "$private/alpha/.system/etc/app.conf" 'from alpha'
put "$private/alpha/.system/etc/same.conf" 'same'
put "$private/alpha/.system/etc/new/new.conf" 'new from alpha'
put "$private/alpha/.system/etc/locked/locked.conf" 'locked from alpha'
put "$private/beta/.system/etc/app.conf" 'from beta'
put "$root/etc/app.conf" 'old on the system'
put "$root/etc/same.conf" 'same'
put "$root/etc/locked/locked.conf" 'old locked'
chmod 444 "$root/etc/locked/locked.conf"
chmod 555 "$root/etc/locked"
touch -t 202001010000 "$private/alpha/.system/etc/app.conf"
root_before=$(snapshot "$root")

# Without --yes and no terminal to ask in, it lists and changes nothing
fails system-apply
expect_same "system-apply changed the system without --yes" "$root_before" "$(snapshot "$root")"
expect_out "pass --yes" "system-apply did not say how to go ahead"
expect_out "differs        /etc/app.conf (profile alpha)" "system-apply did not list the differing file"
expect_out "+from alpha" "system-apply did not show the difference"
expect_out "did you mean system-save?" "system-apply did not warn about the newer system file"
expect_out "missing        /etc/new/new.conf (profile alpha)" "system-apply did not list the missing file"
expect_out "/etc/locked/locked.conf (profile alpha, with sudo)" \
    "system-apply did not mark the file that needs sudo"
expect_out "skipped        /etc/app.conf of profile beta" \
    "system-apply did not report the file both profiles have"
[ ! -s "$sudo_log" ] || fail "system-apply ran sudo without --yes: $(cat "$sudo_log")"

succeeds system-apply --yes
[ "$(cat "$root/etc/app.conf")" = 'from alpha' ] || fail "system-apply did not copy the file"
[ "$(cat "$root/etc/new/new.conf")" = 'new from alpha' ] ||
    fail "system-apply did not copy the missing file"
[ "$(cat "$root/etc/locked/locked.conf")" = 'locked from alpha' ] ||
    fail "system-apply did not copy the file that needs sudo"
[ "$(backup_of .system/etc/app.conf)" = 'old on the system' ] ||
    fail "system-apply did not keep the system's old file"
[ "$(backup_of .system/etc/locked/locked.conf)" = 'old locked' ] ||
    fail "system-apply did not keep the old file it replaced with sudo"
# A file already there is copied over, keeping its owner and mode, not reinstalled as 644
grep -qF "cp $private/alpha/.system/etc/locked/locked.conf $root/etc/locked/locked.conf" \
    "$sudo_log" || fail "system-apply did not use sudo for the locked file: $(cat "$sudo_log")"
if $as_root; then
    [ "$(mode_of "$root/etc/locked/locked.conf")" = -r--r--r-- ] ||
        fail "system-apply changed the mode of the file it replaced with sudo"
fi
grep -qE 'app\.conf|new\.conf|same\.conf' "$sudo_log" &&
    fail "system-apply used sudo where it was not needed: $(cat "$sudo_log")"
[ -z "$(find "$root" -name '*.bak*')" ] || fail "system-apply left backups on the system"

# Nothing left to do
: > "$sudo_log"
succeeds system-apply --yes
expect_out "Already up to date." "system-apply after applying had something to do"
[ ! -s "$sudo_log" ] || fail "system-apply ran sudo with nothing to do: $(cat "$sudo_log")"
grep -q Tabby "$work/out" && fail "system-apply named a program none of its files belong to"

# A system file that is a link is left alone: replacing it would turn it into a file
put "$private/gamma/.system/etc/link.conf" 'from gamma'
put "$root/etc/real.conf" 'real'
ln -s real.conf "$root/etc/link.conf"
fails system-apply --yes gamma
expect_out "a link         /etc/link.conf" "system-apply did not report the link"
[ -L "$root/etc/link.conf" ] && [ "$(cat "$root/etc/real.conf")" = real ] ||
    fail "system-apply replaced a link or wrote through it"
expect_out "Some files could not be applied" "system-apply did not say what failed"

# A profile file that is a link: system-save would write through it, outside the profiles
put "$work/outside.conf" 'outside'
put "$root/etc/via-link.conf" 'on the system'
ln -s "$work/outside.conf" "$private/gamma/.system/etc/via-link.conf"
fails system-save gamma
expect_out "a link         /etc/via-link.conf" "system-save did not report the profile's link"
[ "$(cat "$work/outside.conf")" = outside ] || fail "system-save wrote through a profile's link"
rm "$private/gamma/.system/etc/via-link.conf"

# Not a file on the system, and nothing else to do: still a failure, and said so
put "$private/delta/.system/etc/dir.conf" 'from delta'
mkdir -p "$root/etc/dir.conf"
fails system-apply --yes delta
expect_out "not a file     /etc/dir.conf" "system-apply did not report the folder"
expect_out "Some files could not be applied" "system-apply failed without saying why"

# A name with a line break in it
put "$private/epsilon/.system/etc/two"$'\n'"lines.conf" 'from epsilon'
succeeds system-apply --yes epsilon
[ "$(cat "$root/etc/two"$'\n'"lines.conf")" = 'from epsilon' ] ||
    fail "system-apply did not copy a file with a line break in its name: $(cat "$work/out")"

## WHAT ONLY ROOT CAN READ ##

if $as_root; then
    # A folder you cannot search: the file in it is there, not missing
    put "$private/zeta/.system/etc/hidden/secret.conf" 'new secret'
    put "$root/etc/hidden/secret.conf" 'old secret'
    # A new file in that folder: the folder keeps its mode
    put "$private/zeta/.system/etc/hidden/new.conf" 'new in hidden'
    chmod 600 "$root/etc/hidden/secret.conf"
    chmod 700 "$root/etc/hidden"
    # A file you can write but not read: its backup needs root
    put "$private/zeta/.system/etc/write-only.conf" 'new'
    put "$root/etc/write-only.conf" 'old'
    chmod 200 "$root/etc/write-only.conf"
    chmod 000 "$root/etc/hidden"

    fails system-save zeta
    expect_out "unreadable     /etc/hidden/secret.conf" \
        "system-save took a file it cannot see for a missing one"
    [ "$(cat "$private/zeta/.system/etc/hidden/secret.conf")" = 'new secret' ] ||
        fail "system-save changed the profile's copy of a file it cannot see"

    : > "$sudo_log"
    succeeds system-apply --yes zeta
    expect_out "differs        /etc/hidden/secret.conf (profile zeta, with sudo)" \
        "system-apply took a file in a folder it cannot search for a missing one"
    expect_out "+new secret" "system-apply did not show the difference of a root-only file"
    expect_out "/etc/write-only.conf (profile zeta, with sudo)" \
        "system-apply did not mark the unreadable file as needing sudo"
    [ "$(unshare -r cat "$root/etc/hidden/secret.conf")" = 'new secret' ] ||
        fail "system-apply did not copy the root-only file"
    [ "$(mode_of "$root/etc/hidden/secret.conf")" = -rw------- ] ||
        fail "system-apply made a root-only file readable: $(mode_of "$root/etc/hidden/secret.conf")"
    [ "$(unshare -r cat "$root/etc/hidden/new.conf")" = 'new in hidden' ] ||
        fail "system-apply did not add the file to the root-only folder"
    [ "$(mode_of "$root/etc/hidden")" = d--------- ] ||
        fail "system-apply changed the mode of the folder: $(mode_of "$root/etc/hidden")"
    [ "$(backup_of .system/etc/hidden/secret.conf)" = 'old secret' ] ||
        fail "system-apply did not keep the root-only file it replaced"
    secret_backup=$(find "$private/.backups" -path '*/.system/etc/hidden/secret.conf')
    [ "$(mode_of "$secret_backup")" = -rw------- ] ||
        fail "the backup of a root-only file is readable by others: $(mode_of "$secret_backup")"

    : > "$sudo_log"
    succeeds system-apply --yes zeta
    expect_out "up to date     /etc/hidden/secret.conf" \
        "system-apply did not compare the root-only file"
    expect_out "Already up to date." "system-apply reapplies a root-only file that is the same"
    grep -q install "$sudo_log" && fail "system-apply wrote with nothing to do: $(cat "$sudo_log")"
else
    echo "SKIP: what only root can read (no user namespaces here)"
fi

## INSTALL ##

# Still only prints the commands, now with the two others
put "$root/etc/app.conf" 'changed again'
put "$private/gamma/.system/etc/link.conf" 'from gamma again'
: > "$sudo_log"
succeeds
expect_same "install changed a system file" 'changed again' "$(cat "$root/etc/app.conf")"
# A file already there is copied over, keeping its owner and mode, as system-apply does
expect_out "    sudo cp $private/alpha/.system/etc/app.conf $root/etc/app.conf" \
    "install did not print the copy command"
grep -qF "install -m 644 $private/alpha/.system/etc/app.conf" "$work/out" &&
    fail "install would reset the mode of a file already there: $(cat "$work/out")"
expect_out "a link         /etc/link.conf; left alone" "install did not leave the link alone"
expect_out "not a file     /etc/dir.conf; left alone" "install did not leave the folder alone"
grep -qE "sudo .*$root/etc/dir\.conf" "$work/out" &&
    fail "install printed a command that would copy into a folder: $(cat "$work/out")"
grep -q "^cmp:" "$work/out" && fail "install let cmp complain: $(cat "$work/out")"
grep -qE "sudo .*$root/etc/link\.conf" "$work/out" &&
    fail "install printed a command that would replace a link: $(cat "$work/out")"
if $as_root; then
    # In a folder you cannot open, the file may be there: copied over, and the folder
    # left as it is
    expect_out "    sudo cp $private/zeta/.system/etc/hidden/secret.conf $root/etc/hidden/secret.conf" \
        "install did not print the copy command for a file in a folder it cannot open"
    grep -qE "install .*$root/etc/hidden" "$work/out" &&
        fail "install would reinstall a file or folder it cannot see: $(cat "$work/out")"
fi
expect_out "install.sh system-apply" "install did not name system-apply"
expect_out "install.sh system-save" "install did not name system-save"
[ ! -s "$sudo_log" ] || fail "install ran sudo: $(cat "$sudo_log")"

echo "PASS: system"
