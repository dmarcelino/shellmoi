#!/usr/bin/env bash
# Copies the given private profiles over SSH into another machine's clone, and nothing else.
# With --install, it first installs shellmoi there or updates it, and links the profiles after.
#
#   ~/.local/share/shellmoi/push.sh <host> [--install] [--all | profile...]
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
    echo "Usage: $0 <host> [--install] [--all | profile...]"
    echo
    echo "Copies the profiles into the other machine's clone of shellmoi, and nothing else."
    echo "--install  first installs shellmoi there, or updates it, and links the profiles after;"
    echo "           with no profiles, only that"
    echo "--all      pushes every profile"
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

# Installs shellmoi on the other machine, or updates it
install_remote_shellmoi() {
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
}

main() {
    parse_args "$@"
    local profile
    set --
    if $ALL; then
        while IFS= read -r profile; do
            set -- "$@" "$profile"
        done < <(list_profiles)
        [ $# -gt 0 ] || die "No profiles in $PRIVATE_DIR"
    else
        while IFS= read -r profile; do
            if [ -n "$profile" ]; then
                set -- "$@" "$profile"
            fi
        done <<< "$PROFILES"
        if [ $# -eq 0 ] && ! $INSTALL; then
            usage >&2
            die "No profiles given; name some, or pass --all"
        fi
    fi
    for profile in "$@"; do
        if [ ! -d "$PRIVATE_DIR/$profile" ]; then
            usage >&2
            die "No profile $profile in $PRIVATE_DIR"
        fi
    done

    open_ssh

    if [ $# -gt 0 ]; then
        warn_secrets "$@"
    fi

    # Only to copy: --install with no profiles sets up the other machine, which needs none
    if [ $# -gt 0 ]; then
        if $INSTALL; then
            local_rsync --ensure
        else
            local_rsync
        fi
    fi

    on_remote true || die "Cannot reach $HOST over SSH."
    if $INSTALL; then
        install_remote_shellmoi
        if [ $# -eq 0 ]; then
            echo "No profiles given; available: $(list_profiles | tr '\n' ' ')"
            return
        fi
        echo "==> Checking rsync on $HOST"
        if ! on_remote -t "\"\$HOME/$REMOTE_DIR/install-tools.sh\" --ensure rsync"; then
            echo "Could not check or install rsync on $HOST; looking for one there."
        fi
        remote_rsync
    else
        # Not even private/ is made without a clone: install.sh would then refuse the folder
        on_remote "[ -d \"\$HOME/$REMOTE_DIR/.git\" ]" ||
            die "No shellmoi on $HOST: pass --install to set it up."
        echo "==> Checking rsync on $HOST"
        remote_rsync "Or pass --install."
    fi

    # Its own git repository, as here: git clean in the clone then leaves it alone
    on_remote "mkdir -p \"\$HOME/$REMOTE_DIR/private\" && cd \"\$HOME/$REMOTE_DIR/private\" &&
        { [ -d .git ] || git init -q; }"

    local stamp
    stamp=$(date +%Y%m%d-%H%M%S)
    for profile in "$@"; do
        copy_profile "$PRIVATE_DIR/$profile" "$HOST:$REMOTE_DIR/private/$profile" "$profile" "$stamp"
    done

    # Its output first, so the summary stays last
    local install_failed=false
    if $INSTALL; then
        echo "==> Linking the profiles on $HOST"
        on_remote "\"\$HOME/$REMOTE_DIR/install.sh\"" || install_failed=true
    fi

    if ! $INSTALL; then
        check_links push
    fi
    summary push "$stamp" "$@"
    # As on_remote runs it: in a Bash login shell, which sets shellmoi's PATH
    finish "$install_failed" "ssh $(shell_word "$HOST") \"bash -lc '~/$REMOTE_DIR/install.sh'\""
}

main "$@"
