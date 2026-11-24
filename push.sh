#!/usr/bin/env bash
# Sets up another machine over SSH: installs shellmoi there, or updates it, then copies the
# given private profiles into its clone and links them.
#
#   ~/.local/share/shellmoi/push.sh <host> [--all | profile...]
#
# <host> is anything ssh takes, such as user@host or a Host from ~/.ssh/config. The profiles
# are folders in $SHELLMOI_DIR/private; --all pushes every one. Nothing is deleted on the
# other machine: a profile file that changed is kept in its private/.backups/<time>/ first.
# pull.sh copies the other way. Must run under Bash 3.2 (the macOS default), so no mapfile
# or associative arrays, and no "${array[@]}" of an empty array under set -u.

set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/sync.sh
. "$HERE/lib/sync.sh"
# Words that suggest a secret, in any case: those of HISTIGNORE in .bashrc, which are for
# variable names, and a private key's header
SECRET_PATTERN='SECRET|TOKEN|PASSWORD|PASSWD|_KEY|APIKEY|JWT|CREDENTIAL|PRIVATE KEY'

usage() {
    echo "Usage: $0 <host> [--all | profile...]"
    echo
    echo "--all pushes every profile."
    echo
    echo "Profiles in $PRIVATE_DIR:"
    list_profiles | sed 's/^/    /'
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

main() {
    if [ $# -eq 0 ] || [ "$1" = -h ] || [ "$1" = --help ]; then
        usage
        exit 0
    fi
    HOST=$1
    shift
    check_host "$HOST"
    local profile
    if [ "${1:-}" = --all ]; then
        [ $# -eq 1 ] || die "--all takes no profile names"
        set --
        while IFS= read -r profile; do
            set -- "$@" "$profile"
        done < <(list_profiles)
        [ $# -gt 0 ] || die "No profiles in $PRIVATE_DIR"
    fi
    for profile in "$@"; do
        check_profile_name "$profile"
        if [ ! -d "$PRIVATE_DIR/$profile" ]; then
            usage >&2
            die "No profile $profile in $PRIVATE_DIR"
        fi
    done

    open_ssh

    if [ $# -gt 0 ]; then
        warn_secrets "$@"
    fi

    local_rsync

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
    remote_rsync

    # Its own git repository, as here: git clean in the clone then leaves it alone
    on_remote "mkdir -p \"\$HOME/$REMOTE_DIR/private\" && cd \"\$HOME/$REMOTE_DIR/private\" &&
        { [ -d .git ] || git init -q; }"

    local stamp
    stamp=$(date +%Y%m%d-%H%M%S)
    for profile in "$@"; do
        echo "==> Copying profile $profile"
        # Backups relative to the profile folder: private/.backups/, which is not a profile
        "$RSYNC" -a "${EXCLUDES[@]}" --backup "--backup-dir=../.backups/$stamp/$profile" \
            --rsync-path="$REMOTE_RSYNC" -e "ssh ${SSH_OPTS[*]}" \
            "$PRIVATE_DIR/$profile/" "$HOST:$REMOTE_DIR/private/$profile/"
    done

    echo "==> Linking the profiles on $HOST"
    on_remote "\"\$HOME/$REMOTE_DIR/install.sh\""
}

main "$@"
