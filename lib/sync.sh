# What push.sh and pull.sh share to copy private profiles over SSH. Sourced, not run: the
# script that sources it sets HERE, its own folder, and HOST, the other machine.
# Must run under Bash 3.2 (the macOS default), so no mapfile or associative arrays, and no
# "${array[@]}" of an empty array under set -u.
# shellcheck shell=bash
# The variables are for the scripts that source this
# shellcheck disable=SC2034

SHELLMOI_DIR="${SHELLMOI_DIR:-$HOME/.local/share/shellmoi}"
PRIVATE_DIR="$SHELLMOI_DIR/private"
# The clone on the other machine, relative to its home
REMOTE_DIR=".local/share/shellmoi"
# Leftovers of Finder and editors, not files of a profile; install.sh skips the same
EXCLUDES=(--exclude=.git --exclude=.DS_Store --exclude='*~' --exclude='.*.sw?')

die() {
    echo "$*" >&2
    exit 1
}

# Prints each profile, one per line: the folders in the private folder (by default this
# machine's), but not .git or .backups. pull.sh runs it on the other machine too.
list_profiles() {
    local dir
    for dir in "${1:-$PRIVATE_DIR}"/*/; do
        if [ -d "$dir" ]; then
            dir=${dir%/}
            echo "${dir##*/}"
        fi
    done
}

# Stops unless the host is one: ssh and rsync would take a leading dash as an option
check_host() {
    case "$1" in
        -*|'') die "Not a host: $1" ;;
    esac
}

# Stops unless the name is one of a profile's: no hidden folder, no path
check_profile_name() {
    case "$1" in
        .*|*/*|'') die "Not a profile name: '$1'" ;;
    esac
}

# Quotes a string for the other machine's login shell, which may be zsh
quote() {
    printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

# Opens one SSH connection to HOST for every step, so the password or key is asked for
# once; closes it on exit
open_ssh() {
    WORK_DIR=$(mktemp -d /tmp/shellmoi-sync.XXXXXX)
    SSH_OPTS=(-o ControlMaster=auto -o "ControlPath=$WORK_DIR/ssh" -o ControlPersist=60)
    trap 'ssh -o "ControlPath=$WORK_DIR/ssh" -O exit "$HOST" 2>/dev/null || true; rm -rf "$WORK_DIR"' EXIT
}

# Runs a script on the other machine in a Bash login shell, which sets shellmoi's PATH;
# -t gives it a terminal, so sudo can ask for a password
on_remote() {
    local tty=-T
    if [ "$1" = -t ]; then
        shift
        if [ -t 0 ]; then
            tty=-t
        fi
    fi
    ssh "${SSH_OPTS[@]}" "$tty" "$HOST" "bash -lc $(quote "$1")"
}

# Runs a script on the other machine like on_remote, and prints only its output: not what
# the login shell's files print, such as a greeting in ~/.profile. Keeps its exit status.
remote_output() {
    local start=@@shellmoi-output-start@@ end=@@shellmoi-output-end@@ out status=0
    out=$(on_remote "echo $start; { $1
}; status=\$?; echo $end; exit \$status") || status=$?
    printf '%s\n' "$out" | awk -v s="$start" -v e="$end" '$0 == e { f = 0 } f { print } $0 == s { f = 1 }'
    return "$status"
}

# Prints the first rsync on PATH that is version 3 or later: macOS's own (2.6.9 or
# openrsync) lacks options used here. on_remote runs it on the other machine too.
find_rsync() {
    local rsync version re='^rsync +version +([0-9]+)\.'
    while IFS= read -r rsync; do
        version=$("$rsync" --version 2>/dev/null) || continue
        if [[ $version =~ $re ]] && [ "${BASH_REMATCH[1]}" -ge 3 ]; then
            echo "$rsync"
            return 0
        fi
    done < <(type -ap rsync)
    return 1
}

# Sets RSYNC to this machine's rsync 3 or later, installing it first if missing
local_rsync() {
    echo "==> Checking rsync here"
    "$HERE/install-tools.sh" --ensure rsync || true
    RSYNC=$(find_rsync) ||
        die "rsync 3 or later is needed here: $HERE/install-tools.sh --ensure rsync"
}

# Sets REMOTE_RSYNC to the other machine's rsync 3 or later; installs nothing there
remote_rsync() {
    REMOTE_RSYNC=$(remote_output "$(declare -f find_rsync); find_rsync") ||
        die "rsync 3 or later is needed on $HOST: install-tools.sh --ensure rsync there."
}
