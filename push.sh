#!/usr/bin/env bash
# Sets up another machine over SSH: installs shellmoi there, or updates it, then copies the
# given private profiles into its clone and links them.
#
#   ~/.local/share/shellmoi/push.sh <host> [profile...]
#
# <host> is anything ssh takes, such as user@host or a Host from ~/.ssh/config. The profiles
# are folders in $SHELLMOI_DIR/private. Nothing is deleted on the other machine: a profile
# file that changed is kept in its private/.backups/<time>/ first.
# Must run under Bash 3.2 (the macOS default), so no mapfile or associative arrays, and no
# "${array[@]}" of an empty array under set -u.

set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SHELLMOI_DIR="${SHELLMOI_DIR:-$HOME/.local/share/shellmoi}"
PRIVATE_DIR="$SHELLMOI_DIR/private"
# The clone on the other machine, relative to its home
REMOTE_DIR=".local/share/shellmoi"
# Words that suggest a secret, in any case: those of HISTIGNORE in .bashrc, which are for
# variable names, and a private key's header
SECRET_PATTERN='SECRET|TOKEN|PASSWORD|PASSWD|_KEY|APIKEY|JWT|CREDENTIAL|PRIVATE KEY'
# Leftovers of Finder and editors, not files of a profile; install.sh skips the same
EXCLUDES=(--exclude=.git --exclude=.DS_Store --exclude='*~' --exclude='.*.sw?')

usage() {
    echo "Usage: $0 <host> [profile...]"
    echo
    echo "Profiles in $PRIVATE_DIR:"
    list_profiles | sed 's/^/    /'
}

die() {
    echo "$*" >&2
    exit 1
}

# Prints each profile, one per line: the folders in private/, but not .git or .backups
list_profiles() {
    local dir
    for dir in "$PRIVATE_DIR"/*/; do
        if [ -d "$dir" ]; then
            dir=${dir%/}
            echo "${dir##*/}"
        fi
    done
}

# Quotes a string for the other machine's login shell, which may be zsh
quote() {
    printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
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

# Lists, without the lines themselves, where the profiles name something like a secret
warn_secrets() {
    local found
    found=$(cd "$PRIVATE_DIR" && grep -rnoiIE --exclude-dir=.git "$SECRET_PATTERN" "$@" || true)
    if [ -n "$found" ]; then
        echo "These lines name something like a secret; the copy is encrypted, but check that"
        echo "they belong on $HOST:"
        echo "$found" | sed 's/^/    /'
    fi
}

# Prints the first rsync on PATH that is version 3 or later: macOS's own (2.6.9 or
# openrsync) lacks options used here. push.sh runs it on the other machine too.
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

main() {
    if [ $# -eq 0 ] || [ "$1" = -h ] || [ "$1" = --help ]; then
        usage
        exit 0
    fi
    HOST=$1
    shift
    # ssh and rsync would take it as an option
    case "$HOST" in
        -*|'') die "Not a host: $HOST" ;;
    esac
    local profile
    for profile in "$@"; do
        case "$profile" in
            .*|*/*|'') die "Not a profile name: '$profile'" ;;
        esac
        if [ ! -d "$PRIVATE_DIR/$profile" ]; then
            usage >&2
            die "No profile $profile in $PRIVATE_DIR"
        fi
    done

    # One SSH connection for every step, so the password or key is asked for once
    WORK_DIR=$(mktemp -d /tmp/shellmoi-push.XXXXXX)
    SSH_OPTS=(-o ControlMaster=auto -o "ControlPath=$WORK_DIR/ssh" -o ControlPersist=60)
    trap 'ssh -o "ControlPath=$WORK_DIR/ssh" -O exit "$HOST" 2>/dev/null || true; rm -rf "$WORK_DIR"' EXIT

    if [ $# -gt 0 ]; then
        warn_secrets "$@"
    fi

    echo "==> Checking rsync here"
    "$HERE/install-tools.sh" --ensure rsync || true
    local rsync
    rsync=$(find_rsync) ||
        die "rsync 3 or later is needed here: $HERE/install-tools.sh --ensure rsync"

    on_remote true || die "Cannot reach $HOST over SSH."
    if on_remote "[ -d \"\$HOME/$REMOTE_DIR/.git\" ]"; then
        echo "==> Updating shellmoi on $HOST"
        on_remote "\"\$HOME/$REMOTE_DIR/install.sh\""
    else
        echo "==> Installing shellmoi on $HOST"
        local env=""
        if [ -n "${SHELLMOI_REPO:-}" ]; then
            env="SHELLMOI_REPO=$(quote "$SHELLMOI_REPO") "
        fi
        ssh "${SSH_OPTS[@]}" -T "$HOST" "env ${env}bash -l -s" < "$HERE/install.sh"
    fi

    if [ $# -eq 0 ]; then
        echo "No profiles given; available: $(list_profiles | tr '\n' ' ')"
        return
    fi

    echo "==> Checking rsync on $HOST"
    if ! on_remote -t "\"\$HOME/$REMOTE_DIR/install-tools.sh\" --ensure rsync"; then
        echo "Could not check or install rsync on $HOST; looking for one there."
    fi
    local remote_rsync
    remote_rsync=$(on_remote "$(declare -f find_rsync); find_rsync") ||
        die "rsync 3 or later is needed on $HOST: install-tools.sh --ensure rsync there."

    # Its own git repository, as here: git clean in the clone then leaves it alone
    on_remote "mkdir -p \"\$HOME/$REMOTE_DIR/private\" && cd \"\$HOME/$REMOTE_DIR/private\" &&
        { [ -d .git ] || git init -q; }"

    local stamp
    stamp=$(date +%Y%m%d-%H%M%S)
    for profile in "$@"; do
        echo "==> Copying profile $profile"
        # Backups relative to the profile folder: private/.backups/, which is not a profile
        "$rsync" -a "${EXCLUDES[@]}" --backup "--backup-dir=../.backups/$stamp/$profile" \
            --rsync-path="$remote_rsync" -e "ssh ${SSH_OPTS[*]}" \
            "$PRIVATE_DIR/$profile/" "$HOST:$REMOTE_DIR/private/$profile/"
    done

    echo "==> Linking the profiles on $HOST"
    on_remote "\"\$HOME/$REMOTE_DIR/install.sh\""
}

main "$@"
