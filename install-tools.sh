#!/usr/bin/env bash
# Pick tools from a checklist and install them.
#
#   ./install-tools.sh tools/ai.sh [tools/dev.sh ...]
#   ./install-tools.sh ai dev           # same, by name
#
# Run it as your own user: tools that live in $HOME (claude, rustup, SDKMAN, uv) must not
# land in root's home. Steps that need root call sudo themselves; the password is asked
# once, after the checklist.
#
# Each tool file defines one function per tool, with a "# description" line above it:
#   install_<tool>     installs it (hyphens in <tool> become underscores)
#   installed_<tool>   optional check; the default is `command -v <tool>`
# A tool installs what it needs first with `ensure <other-tool>`.
# Debian and Ubuntu only.

set -euo pipefail

TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/tools"

# Where the installers put binaries; on PATH here so new tools are found right away, and
# so installers that add their directory to ~/.bashrc when it is missing (codex) don't
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:/usr/local/go/bin:$HOME/go/bin:$PATH"

usage() {
    echo "Usage: $0 <tool file or name>..."
    echo
    echo "Tool files:"
    local file
    for file in "$TOOLS_DIR"/*.sh; do
        printf '    %-8s tools/%s\n' "$(basename "$file" .sh)" "$(basename "$file")"
    done
}

## HELPERS FOR TOOL FILES ##

has() {
    command -v "$1" >/dev/null 2>&1
}

# Debian architecture name: amd64 or arm64
deb_arch() {
    dpkg --print-architecture
}

# Ubuntu or Debian release codename, for vendor apt repositories
os_codename() {
    (. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
}

# Latest release tag of a GitHub repository, e.g. "v0.55.1"
gh_latest() {
    local url
    url=$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest")
    echo "${url##*/}"
}

# Changes to a new empty directory for downloads; removed when the script exits
enter_tmp() {
    cd "$(mktemp -d -p "$WORK_DIR")"
}

apt_install() {
    if [ ! -e "$WORK_DIR/apt-updated" ]; then
        sudo apt-get update -q
        touch "$WORK_DIR/apt-updated"
    fi
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -q "$@"
}

# Adds a vendor apt repository signed with the key at key_url, e.g.
#   add_apt_source docker https://download.docker.com/linux/ubuntu/gpg \
#       "https://download.docker.com/linux/ubuntu $(os_codename) stable"
add_apt_source() {
    local name=$1 key_url=$2 source=$3
    local keyring="/etc/apt/keyrings/$name.gpg" key="$WORK_DIR/$name.key"
    curl -fsSL "$key_url" -o "$key"
    if grep -q 'BEGIN PGP' "$key"; then
        gpg --dearmor --yes -o "$key.gpg" "$key"
        key="$key.gpg"
    fi
    sudo install -D -m 0644 "$key" "$keyring"
    echo "deb [arch=$(deb_arch) signed-by=$keyring] $source" |
        sudo tee "/etc/apt/sources.list.d/$name.list" >/dev/null
    rm -f "$WORK_DIR/apt-updated"
}

# Links ~/.local/bin/<name> to a command installed under another name (fdfind -> fd)
link_local() {
    mkdir -p "$HOME/.local/bin"
    ln -sf "$(command -v "$1")" "$HOME/.local/bin/$2"
}

is_installed() {
    local fn="installed_${1//-/_}"
    if declare -F "$fn" >/dev/null; then
        "$fn"
    else
        has "$1"
    fi
}

run_install() {
    echo
    echo "==> Installing $1"
    "install_${1//-/_}"
    hash -r
    echo "$1" >> "$WORK_DIR/installed"
}

# Installs a tool only if it is missing; for dependencies
ensure() {
    is_installed "$1" || run_install "$1"
}

## CHECKLIST ##

# Prints "<tool><TAB><description>" for each install_ function, in file order
list_tools() {
    awk '
        /^# / { desc = substr($0, 3); next }
        match($0, /^install_[A-Za-z0-9_]+\(\)/) {
            name = substr($0, 9, RLENGTH - 10)
            gsub(/_/, "-", name)
            print name "\t" desc
        }
        { desc = "" }
    ' "$1"
}

resolve_file() {
    if [ -f "$1" ]; then
        echo "$1"
    elif [ -f "$TOOLS_DIR/$1.sh" ]; then
        echo "$TOOLS_DIR/$1.sh"
    else
        echo "No tool file: $1" >&2
        usage >&2
        exit 1
    fi
}

STTY_SAVED=""

# Runs again on EXIT after an INT: `read -n` puts the terminal back in raw mode while it
# unwinds, after the INT trap ran
restore_terminal() {
    if [ -n "$STTY_SAVED" ]; then
        stty "$STTY_SAVED" 2>/dev/null || true
        printf '\033[?25h'
    fi
}

cancel() {
    restore_terminal
    echo
    echo "Cancelled, nothing was installed." >&2
    exit 130
}

# menu_select <title> <labels_array> <hints_array> <states_array>
# Draws a checklist in place: up/down or k/j move, space toggles, a cycles the initial
# choice, all and none, enter confirms, q or Esc cancels. Reads the initial choice from
# the states array ("1" ticked, "" not) and writes the user's choice back to it.
menu_select() {
    local title=$1
    local -n _labels=$2 _hints=$3 _states=$4
    local count=${#_labels[@]} cursor=0 drawn=0 width=0 cols i line key rest
    local initial=("${_states[@]}")

    for ((i = 0; i < count; i++)); do
        if [ ${#_labels[$i]} -gt "$width" ]; then
            width=${#_labels[$i]}
        fi
    done
    cols=$(stty size 2>/dev/null | cut -d' ' -f2)
    cols=${cols:-80}

    STTY_SAVED=$(stty -g)
    stty -echo -icanon
    printf '\033[?25l'

    echo "$title"
    echo
    while true; do
        # Redraw in place on every pass but the first
        if [ $drawn -eq 1 ]; then
            printf '\033[%dA' $((count + 2))
        fi
        drawn=1

        for ((i = 0; i < count; i++)); do
            local marker=" " pointer="  "
            [ -n "${_states[$i]}" ] && marker=x
            [ $i -eq $cursor ] && pointer="> "
            printf -v line '%s[%s] %-*s  %s' "$pointer" "$marker" "$width" \
                "${_labels[$i]}" "${_hints[$i]}"
            # Cut at the terminal width: a wrapped line would break the redraw
            printf '\033[2K%s\n' "${line:0:cols-1}"
        done
        printf '\033[2K\n'
        printf '\033[2K%s\n' "  up/down move   space toggle   a missing/all/none   enter confirm   q cancel"

        IFS= read -rsn1 key || key=""
        case "$key" in
            $'\033')
                # Arrow keys arrive as ESC [ A/B; a bare ESC cancels
                IFS= read -rsn2 -t 0.05 rest || rest=""
                case "$rest" in
                    '[A') cursor=$(((cursor - 1 + count) % count)) ;;
                    '[B') cursor=$(((cursor + 1) % count)) ;;
                    '') cancel ;;
                esac
                ;;
            k) cursor=$(((cursor - 1 + count) % count)) ;;
            j) cursor=$(((cursor + 1) % count)) ;;
            ' ')
                if [ -n "${_states[$cursor]}" ]; then
                    _states[cursor]=""
                else
                    _states[cursor]=1
                fi
                ;;
            a)
                # Initial choice -> all -> none -> initial choice; from any other
                # choice, back to the initial one
                local all=1 same=1
                for ((i = 0; i < count; i++)); do
                    [ -z "${_states[$i]}" ] && all=""
                    [ "${_states[$i]}" != "${initial[$i]}" ] && same=""
                done
                for ((i = 0; i < count; i++)); do
                    if [ -n "$all" ]; then
                        _states[i]=""
                    elif [ -n "$same" ]; then
                        _states[i]=1
                    else
                        _states[i]=${initial[$i]}
                    fi
                done
                ;;
            ''|$'\n'|$'\r')
                restore_terminal
                echo
                return 0
                ;;
            q|Q) cancel ;;
        esac
    done
}

# Shows a checklist per tool file; adds the ticked tools to the CHOSEN array
choose_tools() {
    local file name desc i
    for file in "$@"; do
        local names=() hints=() states=()
        while IFS=$'\t' read -r name desc; do
            # Missing tools start ticked
            if is_installed "$name"; then
                desc="$desc (installed)"
                states+=("")
            else
                states+=(1)
            fi
            names+=("$name")
            hints+=("$desc")
        done < <(list_tools "$file")
        [ ${#names[@]} -gt 0 ] || continue

        menu_select "Install which tools from tools/$(basename "$file")?" names hints states
        for ((i = 0; i < ${#names[@]}; i++)); do
            if [ -n "${states[$i]}" ]; then
                CHOSEN+=("${names[$i]}")
            fi
        done
    done
}

## MAIN ##

# Keeps the sudo timestamp fresh, so long installs don't ask for the password again
keep_sudo_alive() {
    while sleep 60; do
        sudo -n -v 2>/dev/null || exit
    done &
    SUDO_KEEPALIVE_PID=$!
}

cleanup() {
    restore_terminal
    if [ -n "${SUDO_KEEPALIVE_PID:-}" ]; then
        kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    fi
    if [ -n "${WORK_DIR:-}" ]; then
        rm -rf "$WORK_DIR"
    fi
}

main() {
    if [ $# -eq 0 ] || [ "$1" = -h ] || [ "$1" = --help ]; then
        usage
        exit 0
    fi
    if [ "$(id -u)" -eq 0 ]; then
        echo "Run this as your own user, not root: it calls sudo where needed." >&2
        exit 1
    fi
    if ! has apt-get; then
        echo "This script supports Debian and Ubuntu only (apt-get not found)." >&2
        exit 1
    fi
    if [ ! -t 0 ] || [ ! -t 1 ]; then
        echo "Run this in a terminal: it shows a checklist." >&2
        exit 1
    fi

    local files=() file
    for file in "$@"; do
        files+=("$(resolve_file "$file")")
    done
    # All tool files, so a tool can depend on a tool from another file
    for file in "$TOOLS_DIR"/*.sh "${files[@]}"; do
        # shellcheck source=/dev/null
        . "$file"
    done

    trap cleanup EXIT
    trap cancel INT

    CHOSEN=()
    choose_tools "${files[@]}"
    if [ ${#CHOSEN[@]} -eq 0 ]; then
        echo "Nothing to install."
        exit 0
    fi

    echo "Installing: ${CHOSEN[*]}"
    echo "Some steps need root; sudo asks for your password once."
    if ! sudo -v; then
        echo "sudo is required to install tools." >&2
        exit 1
    fi
    trap 'echo; exit 130' INT

    WORK_DIR=$(mktemp -d)
    keep_sudo_alive

    local tool status failed=()
    for tool in "${CHOSEN[@]}"; do
        # A subshell, so a failing tool doesn't stop the others; outside a condition,
        # so set -e still works inside it
        set +e
        (set -e; run_install "$tool")
        status=$?
        set -e
        if [ $status -ne 0 ]; then
            failed+=("$tool")
            echo "!!  $tool failed (exit $status)" >&2
        fi
    done

    echo
    if [ -s "$WORK_DIR/installed" ]; then
        echo "Installed: $(sort -u "$WORK_DIR/installed" | tr '\n' ' ')"
    fi
    if [ ${#failed[@]} -gt 0 ]; then
        echo "Failed:    ${failed[*]}" >&2
    fi
    if grep -qx docker-ce "$WORK_DIR/installed" 2>/dev/null; then
        echo "Log out and in again to use docker without sudo."
    fi
    echo "Open a new shell to use the new tools."
    [ ${#failed[@]} -eq 0 ]
}

main "$@"
