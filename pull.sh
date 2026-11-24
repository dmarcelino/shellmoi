#!/usr/bin/env bash
# Copies private profiles back from another machine over SSH, into this clone's private/,
# and nothing else. With --install, it then runs install.sh here, to link what is new.
# The reverse of push.sh; changes nothing on the other machine.
#
#   ~/.local/share/shellmoi/pull.sh <host> [--install] [--all | profile...]
#
# <host> is anything ssh takes, such as user@host or a Host from ~/.ssh/config. The profiles
# are folders in the other machine's private/; --all pulls every one. Nothing is deleted
# here: a profile file that changed is kept in private/.backups/<time>/ first. Must run
# under Bash 3.2 (the macOS default), so no mapfile or associative arrays, and no
# "${array[@]}" of an empty array under set -u.

set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/sync.sh
. "$HERE/lib/sync.sh"

usage() {
    echo "Usage: $0 <host> [--install] [--all | profile...]"
    echo
    echo "Copies the profiles from the other machine's private/ into $PRIVATE_DIR,"
    echo "and nothing else."
    echo "--install  then runs install.sh here, to link new files and print the sudo"
    echo "           commands for system files"
    echo "--all      pulls every profile there"
}

# Lists the profiles on the other machine, one per line
remote_profiles() {
    remote_output "$(declare -f list_profiles); list_profiles \"\$HOME/$REMOTE_DIR/private\""
}

main() {
    parse_args "$@"
    if ! $ALL && [ -z "$PROFILES" ]; then
        die "No profiles given; name some, or pass --all"
    fi

    open_ssh
    on_remote true || die "Cannot reach $HOST over SSH."
    on_remote "[ -d \"\$HOME/$REMOTE_DIR/private\" ]" ||
        die "No private profiles on $HOST: ~/$REMOTE_DIR/private is missing."

    local available profile
    available=$(remote_profiles) || die "Cannot list the profiles on $HOST."
    if $ALL; then
        [ -n "$available" ] || die "No profiles on $HOST"
        PROFILES=$available
    fi
    set --
    while IFS= read -r profile; do
        if [ -n "$profile" ]; then
            set -- "$@" "$profile"
        fi
    done <<< "$PROFILES"
    for profile in "$@"; do
        # The names come from the other machine too, with --all
        check_profile_name "$profile"
        if ! grep -qxF -- "$profile" <<< "$available"; then
            echo "Profiles on $HOST: $(tr '\n' ' ' <<< "$available")" >&2
            die "No profile $profile on $HOST"
        fi
    done

    if $INSTALL; then
        local_rsync --ensure
    else
        local_rsync
    fi
    echo "==> Checking rsync on $HOST"
    remote_rsync ""

    # Its own git repository, as push.sh makes on the other machine
    mkdir -p "$PRIVATE_DIR"
    [ -d "$PRIVATE_DIR/.git" ] || git -C "$PRIVATE_DIR" init -q
    for profile in "$@"; do
        if [ -n "$(git -C "$PRIVATE_DIR" status --porcelain -- "$profile")" ]; then
            echo "Profile $profile has changes not committed in $PRIVATE_DIR: git diff will show"
            echo "them mixed with the pull's. Commit before pulling to keep them apart."
        fi
    done

    local stamp
    stamp=$(date +%Y%m%d-%H%M%S)
    for profile in "$@"; do
        copy_profile "$HOST:$REMOTE_DIR/private/$profile" "$PRIVATE_DIR/$profile" "$profile" "$stamp"
    done

    # Its output first, so the summary stays last; a failed install, such as its update of
    # the clone without a network, still gets the summary
    check_links pull
    local install_failed=false
    if $INSTALL && $NEEDS_INSTALL; then
        echo "==> Linking the new files"
        "$HERE/install.sh" || install_failed=true
    fi

    summary pull "$stamp" "$@"
    finish "$install_failed" "$(shell_word "$HERE/install.sh")"
}

main "$@"
