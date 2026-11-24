# What push.sh and pull.sh share to copy private profiles over SSH. Sourced, not run: the
# script that sources it sets HERE, its own folder, and defines usage.
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
# What copy_profile copied, each line "    <profile>/<path>"; the updated files install.sh
# links, each line a path relative to ~; the profiles it could not copy in full; whether
# install.sh has something to do: a new file, a system file, or a file not linked yet
ADDED=""
UPDATED=""
UPDATED_LINKED=""
FAILED=""
NEEDS_INSTALL=false

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
        .*|*/*|*$'\n'*|'') die "Not a profile name: '$1'" ;;
    esac
}

# Reads <host> [--install] [--all | profile...] into HOST, INSTALL, ALL and PROFILES, the
# names one per line. Prints the usage and exits when there is nothing, or --help.
parse_args() {
    if [ $# -eq 0 ] || [ "$1" = -h ] || [ "$1" = --help ]; then
        usage
        exit 0
    fi
    HOST=$1
    shift
    check_host "$HOST"
    INSTALL=false
    ALL=false
    PROFILES=""
    local arg
    for arg in "$@"; do
        case "$arg" in
            --install) INSTALL=true ;;
            --all) ALL=true ;;
            -h|--help)
                usage
                exit 0
                ;;
            -*) die "Unknown option: $arg" ;;
            *)
                check_profile_name "$arg"
                PROFILES="$PROFILES$arg"$'\n'
                ;;
        esac
    done
    if $ALL && [ -n "$PROFILES" ]; then
        die "--all takes no profile names"
    fi
}

# Quotes a string for the other machine's login shell, which may be zsh
quote() {
    printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

# Prints a path or name for a command to copy: quoted if anything in it needs it, else a
# path under ~ as ~/..., the ~ for the reader's shell to expand
# shellcheck disable=SC2088
shell_word() {
    case "$1" in
        *[!A-Za-z0-9._/@:-]*) quote "$1" ;;
        "$HOME"/*) echo "~/${1#"$HOME"/}" ;;
        *) echo "$1" ;;
    esac
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

# Sets RSYNC to this machine's rsync 3 or later; with --ensure, installs it first if missing
local_rsync() {
    echo "==> Checking rsync here"
    local hint=" Or pass --install."
    if [ "${1:-}" = --ensure ]; then
        "$HERE/install-tools.sh" --ensure rsync || true
        hint=""
    fi
    RSYNC=$(find_rsync) ||
        die "rsync 3 or later is needed here: $HERE/install-tools.sh --ensure rsync installs it.$hint"
}

# Sets REMOTE_RSYNC to the other machine's rsync 3 or later; installs nothing there. The
# argument, if any, ends the message when there is none.
remote_rsync() {
    REMOTE_RSYNC=$(remote_output "$(declare -f find_rsync); find_rsync") ||
        die "rsync 3 or later is needed on $HOST: install-tools.sh --ensure rsync there installs it.${1:+ $1}"
}

# Copies a profile folder with rsync, from <src>/ to <dst>/, one of them host:path. On the
# receiving side, a file it replaces is kept first in private/.backups/<stamp>/<profile>/,
# which is not a profile. --checksum: a file whose content is the same is not copied, even
# with another time. Adds what it copied to ADDED and UPDATED, and the profile to FAILED
# when rsync fails: what it got to is still listed, and the caller copies the next one.
copy_profile() {
    local src=$1 dst=$2 profile=$3 stamp=$4 line path
    echo "==> Copying profile $profile"
    if ! "$RSYNC" -a --checksum "${EXCLUDES[@]}" \
        --backup "--backup-dir=../.backups/$stamp/$profile" --out-format='%i %n' \
        --rsync-path="$REMOTE_RSYNC" -e "ssh ${SSH_OPTS[*]}" \
        "$src/" "$dst/" > "$WORK_DIR/changes"
    then
        FAILED="$FAILED $profile"
    fi
    # Each line is rsync's change summary, then the path: <f (sent) or >f (received) for a
    # file, cL for a symlink, then +++++++++ when it is new
    while IFS= read -r line; do
        path=${line#* }
        case "$line" in
            [\<\>]f'+++++++++ '*|'cL+++++++++ '*) ADDED="$ADDED    $profile/$path"$'\n' ;;
            [\<\>]f*|cL*)
                UPDATED="$UPDATED    $profile/$path"$'\n'
                case "$path" in
                    .system/*) ;;
                    *) UPDATED_LINKED="$UPDATED_LINKED$path"$'\n' ;;
                esac
                ;;
            *) continue ;;
        esac
        # install.sh links a new file, and prints the sudo commands for a system file
        # (in .system/, as install.sh names it) that changed
        case "${line%% *}:$path" in
            *+++++++++:*|*:.system/*) NEEDS_INSTALL=true ;;
        esac
    done < "$WORK_DIR/changes"
}

# Returns 0 when one of the paths read, relative to ~, has no symlink there: a file a
# copy-only run added, whose install.sh was not run since. A symlink to another profile's
# file, or to shellmoi's own, counts: install.sh would not link this one either.
any_unlinked() {
    local path
    while IFS= read -r path; do
        if [ -n "$path" ] && [ ! -L "$HOME/$path" ]; then
            return 0
        fi
    done
    return 1
}

# Sets NEEDS_INSTALL when a file the copies updated is not linked in ~ on the receiving
# side, which is this machine for pull and HOST for push. A check that fails counts as not
# linked, so the hint to run install.sh errs on the side of showing.
check_links() {
    if $NEEDS_INSTALL || [ -z "$UPDATED_LINKED" ]; then
        return
    fi
    local status=0
    if [ "$1" = pull ]; then
        any_unlinked <<< "$UPDATED_LINKED" || status=$?
    else
        printf '%s' "$UPDATED_LINKED" |
            on_remote "$(declare -f any_unlinked); any_unlinked" > /dev/null 2>&1 || status=$?
    fi
    if [ "$status" -ne 1 ]; then
        NEEDS_INSTALL=true
    fi
}

# Lists what the copies changed, and what to do next: pull, as the changes are here, says
# how to review them; without --install, both say how to link. Takes push or pull, the
# backups' time, and the profiles. The ~ of the other machine's paths is printed as is.
# shellcheck disable=SC2088
summary() {
    local direction=$1 stamp=$2
    shift 2
    echo
    if [ -z "$ADDED$UPDATED" ]; then
        # A failed copy is not up to date: finish says what failed
        if [ -z "$FAILED" ]; then
            echo "Already up to date."
        fi
        return
    fi
    local dir where="" profiles="" profile
    if [ "$direction" = pull ]; then
        dir=$(shell_word "$PRIVATE_DIR")
    else
        dir="~/$REMOTE_DIR/private"
        where=" on $HOST"
    fi
    for profile in "$@"; do
        profiles="$profiles $(shell_word "$profile")"
    done
    if [ -n "$UPDATED" ]; then
        echo "Updated$where, the versions they replaced kept in $dir/.backups/$stamp/:"
        printf '%s' "$UPDATED"
    fi
    if [ -n "$ADDED" ]; then
        echo "Added$where:"
        printf '%s' "$ADDED"
    fi
    if [ "$direction" = pull ]; then
        echo
        if [ -n "$UPDATED" ]; then
            echo "Review the changes:"
            if git -C "$PRIVATE_DIR" rev-parse -q --verify HEAD > /dev/null; then
                echo "    git -C $dir diff --$profiles"
            else
                # Nothing committed: git diff has nothing to compare with
                echo "    cd $dir/.backups/$stamp && find . -type f -exec diff -u {} ../../{} \\;"
                echo "($dir has no commits yet, so git diff cannot show them.)"
            fi
        fi
        if [ -n "$ADDED" ]; then
            echo "See the new files:"
            echo "    git -C $dir status --$profiles"
        fi
    fi
    if $NEEDS_INSTALL && ! $INSTALL; then
        echo
        echo "Some files are not linked$where yet, or system files changed. install.sh links"
        echo "them and prints the sudo commands for system files; run it${where:- here}:"
        if [ "$direction" = pull ]; then
            echo "    $(shell_word "$SHELLMOI_DIR/install.sh")"
        else
            echo "    ~/$REMOTE_DIR/install.sh"
        fi
    fi
}

# Ends the run: an error when a copy or the install failed, after what was copied is listed.
# Takes whether the install failed, and the command that runs it again.
finish() {
    if $1; then
        echo
        echo "install.sh failed (see above), so new files may not be linked. Run it again:"
        echo "    $2"
    fi
    if [ -n "$FAILED" ]; then
        echo
        die "Could not copy every file of:$FAILED. What was copied is listed above."
    fi
    if $1; then
        exit 1
    fi
}
