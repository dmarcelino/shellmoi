#!/usr/bin/env bash
# Installs into a fake home, uninstalls, and expects the home as it was before.
#
#   tests/uninstall_test.sh
#
# Runs install.sh from the working tree; the files it links come from a local clone, so
# no network is needed.

set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
home=$work/home
clone=$work/clone

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

# Lists every path under the fake home with its link target or checksum
snapshot() {
    (cd "$home" && find . -mindepth 1 | LC_ALL=C sort | while IFS= read -r path; do
        if [ -L "$path" ]; then
            echo "$path -> $(readlink "$path")"
        elif [ -d "$path" ]; then
            echo "$path/"
        else
            echo "$path $(cksum < "$path")"
        fi
    done)
}

shellmoi() {
    HOME=$home SHELLMOI_DIR=$clone bash "$repo/install.sh" "$@" > "$work/out" 2>&1 ||
        fail "install.sh $* exited non-zero: $(cat "$work/out")"
}

expect_same() {
    local label=$1 expected=$2 actual=$3
    if [ "$expected" != "$actual" ]; then
        diff <(echo "$expected") <(echo "$actual") >&2 || true
        fail "$label"
    fi
}

git clone --quiet "$repo" "$clone"
skill=$(cd "$clone/.codex/skills" && ls | head -n 1)

# A home with files in the way of some links, a skill of the same name, an unrelated
# skill, a backup made by another tool and an edited Claude settings file
mkdir -p "$home/.config/lazygit" "$home/.claude/skills" "$home/.codex/skills" \
    "$home/elsewhere/$skill"
echo 'original bashrc' > "$home/.bashrc"
echo 'original inputrc' > "$home/.inputrc"
echo 'original lazygit' > "$home/.config/lazygit/config.yml"
echo 'backup by another tool' > "$home/.bashrc.bak.20200101000000"
echo '{}' > "$home/.claude/settings.json"
ln -s "$home/elsewhere/$skill" "$home/.claude/skills/$skill"
ln -s "$home/elsewhere/$skill" "$home/.codex/skills/other"

before=$(snapshot)

shellmoi
shellmoi
[ -L "$home/.bashrc" ] || fail "install did not link ~/.bashrc"

# Something replaced a link with a plain file; the next install backs it up again
rm "$home/.inputrc"
echo 'edited after install' > "$home/.inputrc"
sleep 1  # backups are stamped to the second
shellmoi

shellmoi uninstall
after=$(snapshot)

newer_backups=$(cd "$home" && ls -d .inputrc.bak.* 2>/dev/null || true)
[ "$(echo "$newer_backups" | wc -l)" -eq 1 ] && [ -n "$newer_backups" ] ||
    fail "expected one newer ~/.inputrc backup, found: $newer_backups"
[ "$(cat "$home/$newer_backups")" = 'edited after install' ] ||
    fail "the newer ~/.inputrc backup does not hold the later edit"
grep -q "left backup    ~/$newer_backups" "$work/out" ||
    fail "uninstall did not list the newer backup"

expect_same "uninstall did not restore the home as it was" \
    "$before" "$(echo "$after" | grep -v "^\./$newer_backups ")"

shellmoi uninstall
expect_same "a second uninstall changed the home" "$after" "$(snapshot)"

echo "PASS"
