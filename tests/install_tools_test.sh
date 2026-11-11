#!/usr/bin/env bash
# Checks that install-tools.sh offers the right tools on each system and takes no Linux
# steps on macOS. Installs nothing: package managers, sudo and downloads are stubbed.
#
#   tests/install_tools_test.sh
#
# Needs jq, which the Colima step uses to edit the Docker config.

set -euo pipefail

# install-tools.sh needs Bash 4.3; on macOS, run under Homebrew's bash instead of 3.2.
# Before anything else, as exec skips the cleanup trap below.
if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
    for bash in /opt/homebrew/bin/bash /usr/local/bin/bash; do
        if [ -x "$bash" ]; then
            exec "$bash" "$0" "$@"
        fi
    done
fi

repo=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

# shellcheck source=../install-tools.sh
# As a user's environment might have them: no HOMEBREW_NO_ASK, so that of the person running
# the test can't hide a missing one, and a HOMEBREW_ASK, which install-tools.sh must clear
unset HOMEBREW_NO_ASK
export HOMEBREW_ASK=1
. "$repo/install-tools.sh"
for file in "$repo"/tools/*.sh; do
    # shellcheck source=/dev/null
    . "$file"
done

# Every tool the checklist offers on this system
supported_tools() {
    local file name desc
    for file in "$repo"/tools/*.sh; do
        while IFS=$'\t' read -r name desc; do
            if is_supported "$name"; then
                echo "$name"
            fi
        done < <(list_tools "$file")
    done
}

expect_tool() {
    local system=$1 tool=$2 want=$3 tools
    tools=$(supported_tools)
    if [ "$want" = offered ]; then
        grep -qx "$tool" <<< "$tools" || fail "$system does not offer $tool"
    else
        grep -qx "$tool" <<< "$tools" && fail "$system offers $tool"
    fi
    return 0
}

## CHECKLIST PER SYSTEM ##

is_mac() { return 1; }
expect_tool Linux docker-ce offered
expect_tool Linux colima hidden
expect_tool Linux bash hidden

is_mac() { return 0; }
expect_tool macOS colima offered
expect_tool macOS docker-ce hidden
expect_tool macOS bash offered

## NO HOMEBREW CONFIRMATION ##

# Homebrew only checks that the variable is set
[ -n "${HOMEBREW_NO_ASK:-}" ] && [ -z "${HOMEBREW_ASK+set}" ] ||
    fail "install-tools.sh lets Homebrew ask for confirmation after the checklist"
# Before the Bash check, which may install Homebrew's bash before re-running the script
export_line=$(grep -n '^export HOMEBREW_NO_ASK=' "$repo/install-tools.sh" | cut -d: -f1)
check_line=$(grep -n 'BASH_VERSINFO' "$repo/install-tools.sh" | head -n 1 | cut -d: -f1)
[ -n "$export_line" ] && [ "$export_line" -lt "$check_line" ] ||
    fail "install-tools.sh sets HOMEBREW_NO_ASK after the Bash check"

## BASH FOR INSTALLERS ##

# Installers piped into a shell get the Bash running install-tools.sh, never `bash` from
# PATH, which can be macOS's 3.2 (SDKMAN refuses it); sudo's root shell on Linux is fine
piped=$(grep -nE '\| *bash( |;|$)' "$repo"/tools/*.sh || true)
[ -z "$piped" ] || fail "installers piped into bash from PATH instead of \"\$BASH\":
$piped"

# On macOS with Homebrew, install-tools.sh puts Homebrew's bash before /bin/bash
if [ "$(uname -s)" = Darwin ] && { [ -x /opt/homebrew/bin/brew ] || [ -x /usr/local/bin/brew ]; }; then
    [ "$(command -v bash)" != /bin/bash ] ||
        fail "bash on PATH is macOS's 3.2 after loading install-tools.sh"
fi

## NO LINUX STEPS ON MACOS ##

calls=$work/calls
: > "$calls"
record() { echo "$*" >> "$calls"; }

# Records each call; brew --prefix answers like Homebrew on Apple silicon
brew() {
    record brew "$@"
    if [ "$1" = --prefix ]; then
        echo /opt/homebrew
    fi
}
apt_install() { record apt_install "$@"; }
add_apt_source() { record add_apt_source "$@"; }
deb_arch() { record deb_arch; }
os_codename() { record os_codename; }
link_local() { record link_local "$@"; }
gh_latest() { record gh_latest "$@"; }
enter_tmp() { record enter_tmp; }
sudo() { record sudo "$@"; }
dpkg() { record dpkg "$@"; }
cargo() { record cargo "$@"; }
curl() { record curl "$@"; }
npm() { record npm "$@"; }
npx() { record npx "$@"; }
sdk_install() { record sdk_install "$@"; }
ensure() { record ensure "$@"; }

export HOME=$work/home
mkdir -p "$HOME"

while IFS= read -r tool; do
    (set -e; "install_${tool//-/_}") || fail "install_$tool failed on macOS"
done < <(supported_tools)

linux_steps=$(grep -E '^(apt_install|add_apt_source|deb_arch|os_codename|link_local|gh_latest|enter_tmp|sudo|dpkg|cargo) ' "$calls" || true)
[ -z "$linux_steps" ] || fail "macOS installs took Linux steps:
$linux_steps"

expect_call() {
    grep -qxF "$1" "$calls" || fail "macOS installs did not run: $1"
}
expect_call "brew install --quiet bash"
expect_call "brew install --quiet worktrunk"
expect_call "brew install --quiet hashicorp/tap/terraform"
expect_call "brew install --quiet colima docker docker-compose docker-buildx"
expect_call "brew services start colima"
expect_call "brew link --force node@$NODE_MAJOR"
expect_call "npm install -g @colbymchenry/codegraph"

## DOCKER PLUGIN DIRECTORIES ##

plugins=/opt/homebrew/lib/docker/cli-plugins
config=$HOME/.docker/config.json

[ "$(jq -c .cliPluginsExtraDirs "$config")" = "[\"$plugins\"]" ] ||
    fail "colima did not write the plugin directory to a new Docker config: $(cat "$config")"

# An existing config keeps its other settings, and the directory is listed once
echo '{"auths": {"example.com": {}}, "cliPluginsExtraDirs": ["/elsewhere"]}' > "$config"
docker_plugin_dirs
docker_plugin_dirs
[ "$(jq -c . "$config")" = "{\"auths\":{\"example.com\":{}},\"cliPluginsExtraDirs\":[\"/elsewhere\",\"$plugins\"]}" ] ||
    fail "colima did not merge the plugin directory into an existing Docker config: $(cat "$config")"

echo "PASS"
