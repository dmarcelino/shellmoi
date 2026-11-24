#!/usr/bin/env bash
# Copies private profiles back from another machine over SSH, into this clone's private/,
# and links any new files. The reverse of push.sh; changes nothing on the other machine.
#
#   ~/.local/share/shellmoi/pull.sh <host> [--all | profile...]
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
    echo "Usage: $0 <host> [--all | profile...]"
    echo
    echo "Copies the profiles from the other machine's private/ into $PRIVATE_DIR."
    echo "--all pulls every profile there."
}

# Prints a path or name for a command to copy: quoted if anything in it needs it, else a
# path under ~ as ~/..., the ~ for the reader's shell to expand
# shellcheck disable=SC2088
shell_word() {
    case "$1" in
        *[!A-Za-z0-9._/-]*) quote "$1" ;;
        "$HOME"/*) echo "~/${1#"$HOME"/}" ;;
        *) echo "$1" ;;
    esac
}

# Lists the profiles on the other machine, one per line
remote_profiles() {
    remote_output "$(declare -f list_profiles); list_profiles \"\$HOME/$REMOTE_DIR/private\""
}

main() {
    if [ $# -eq 0 ] || [ "$1" = -h ] || [ "$1" = --help ]; then
        usage
        exit 0
    fi
    HOST=$1
    shift
    check_host "$HOST"
    local all=false profile
    if [ "${1:-}" = --all ]; then
        [ $# -eq 1 ] || die "--all takes no profile names"
        all=true
        shift
    else
        [ $# -gt 0 ] || die "No profiles given; name some, or pass --all"
    fi
    for profile in "$@"; do
        check_profile_name "$profile"
    done

    open_ssh
    on_remote true || die "Cannot reach $HOST over SSH."
    on_remote "[ -d \"\$HOME/$REMOTE_DIR/private\" ]" ||
        die "No private profiles on $HOST: ~/$REMOTE_DIR/private is missing."

    local available
    available=$(remote_profiles) || die "Cannot list the profiles on $HOST."
    if $all; then
        [ -n "$available" ] || die "No profiles on $HOST"
        while IFS= read -r profile; do
            set -- "$@" "$profile"
        done <<< "$available"
    fi
    for profile in "$@"; do
        # The names come from the other machine too, with --all
        check_profile_name "$profile"
        if ! grep -qxF -- "$profile" <<< "$available"; then
            echo "Profiles on $HOST: $(tr '\n' ' ' <<< "$available")" >&2
            die "No profile $profile on $HOST"
        fi
    done

    local_rsync
    echo "==> Checking rsync on $HOST"
    remote_rsync

    # Its own git repository, as push.sh makes on the other machine
    mkdir -p "$PRIVATE_DIR"
    [ -d "$PRIVATE_DIR/.git" ] || git -C "$PRIVATE_DIR" init -q
    for profile in "$@"; do
        if [ -n "$(git -C "$PRIVATE_DIR" status --porcelain -- "$profile")" ]; then
            echo "Profile $profile has changes not committed in $PRIVATE_DIR: git diff will show"
            echo "them mixed with the pull's. Commit before pulling to keep them apart."
        fi
    done

    local stamp line path added="" updated="" failed="" install=false
    stamp=$(date +%Y%m%d-%H%M%S)
    for profile in "$@"; do
        echo "==> Copying profile $profile"
        # Backups relative to the profile folder: private/.backups/, which is not a profile.
        # --checksum: a file whose content is the same is not copied, even with another time.
        # Each line is rsync's change summary, then the path: >f or cL (a symlink) for what
        # it copied, followed by +++++++++ when it is new. A failed copy still lists the
        # files it got to, and the other profiles are still copied.
        if ! "$RSYNC" -a --checksum "${EXCLUDES[@]}" \
            --backup "--backup-dir=../.backups/$stamp/$profile" --out-format='%i %n' \
            --rsync-path="$REMOTE_RSYNC" -e "ssh ${SSH_OPTS[*]}" \
            "$HOST:$REMOTE_DIR/private/$profile/" "$PRIVATE_DIR/$profile/" > "$WORK_DIR/changes"
        then
            failed="$failed $profile"
        fi
        while IFS= read -r line; do
            path=${line#* }
            case "$line" in
                '>f+++++++++ '*|'cL+++++++++ '*) added="$added    $profile/$path"$'\n' ;;
                '>f'*|'cL'*) updated="$updated    $profile/$path"$'\n' ;;
                *) continue ;;
            esac
            # install.sh links a new file, and prints the sudo commands for a system file
            # (in .system/, as install.sh names it) that changed
            case "${line%% *}:$path" in
                *+++++++++:*|*:.system/*) install=true ;;
            esac
        done < "$WORK_DIR/changes"
    done

    # Its own output comes first, so the summary below stays last; a failed install, such
    # as its update of the clone without a network, still gets the summary
    local install_failed=false
    if $install; then
        echo "==> Linking the new files"
        "$HERE/install.sh" || install_failed=true
    fi

    summary "$stamp" "$added" "$updated" "$@"

    if $install_failed; then
        echo
        echo "install.sh failed (see above), so new files may not be linked. Run it again:"
        echo "    $(shell_word "$HERE/install.sh")"
    fi
    if [ -n "$failed" ]; then
        echo
        die "Could not copy every file of:$failed. What was copied is listed above."
    fi
    if $install_failed; then
        exit 1
    fi
}

# Lists what the pull updated and added, and how to review it
summary() {
    local stamp=$1 added=$2 updated=$3
    shift 3
    echo
    if [ -z "$added$updated" ]; then
        echo "Already up to date."
        return
    fi
    local dir backups profiles="" profile
    dir=$(shell_word "$PRIVATE_DIR")
    backups=$(shell_word "$PRIVATE_DIR/.backups/$stamp")
    for profile in "$@"; do
        profiles="$profiles $(shell_word "$profile")"
    done
    if [ -n "$updated" ]; then
        echo "Updated, the versions they replaced kept in $backups/:"
        printf '%s' "$updated"
    fi
    if [ -n "$added" ]; then
        echo "Added:"
        printf '%s' "$added"
    fi
    echo
    if [ -n "$updated" ]; then
        echo "Review the changes:"
        if git -C "$PRIVATE_DIR" rev-parse -q --verify HEAD > /dev/null; then
            echo "    git -C $dir diff --$profiles"
        else
            # Nothing committed: git diff has nothing to compare with
            echo "    cd $backups && find . -type f -exec diff -u {} ../../{} \\;"
            echo "($dir has no commits yet, so git diff cannot show them.)"
        fi
    fi
    if [ -n "$added" ]; then
        echo "See the new files:"
        echo "    git -C $dir status --$profiles"
    fi
}

main "$@"
