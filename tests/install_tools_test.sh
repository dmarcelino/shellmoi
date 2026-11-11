#!/usr/bin/env bash
# Checks that install-tools.sh offers the right tools on each system and takes no Linux
# steps on macOS. Installs nothing: package managers, sudo and downloads are stubbed.
#
#   tests/install_tools_test.sh
#
# Needs jq, which the Colima step uses to edit the Docker config.

set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

# shellcheck source=../install-tools.sh
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

is_mac() { return 0; }
expect_tool macOS colima offered
expect_tool macOS docker-ce hidden

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
