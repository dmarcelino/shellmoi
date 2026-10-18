#!/usr/bin/env bash
# Install or update shellmoi: clone the repository, then link its files into $HOME.
#
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/dmarcelino/shellmoi/main/install.sh)"
#
# Safe to run again: it pulls the latest changes and only touches what changed.
# Must run under Bash 3.2 (the macOS default), so no mapfile or associative arrays.

set -euo pipefail

SHELLMOI_REPO="${SHELLMOI_REPO:-https://github.com/dmarcelino/shellmoi.git}"
SHELLMOI_DIR="${SHELLMOI_DIR:-$HOME/.local/share/shellmoi}"
BACKUP_SUFFIX=".bak.$(date +%Y%m%d-%H%M%S)"

# Prints the command that installs a package on this system
pkg_install_hint() {
    local pkg=$1
    if command -v apt-get >/dev/null 2>&1; then
        echo "sudo apt install $pkg"
    elif command -v dnf >/dev/null 2>&1; then
        echo "sudo dnf install $pkg"
    elif command -v pacman >/dev/null 2>&1; then
        echo "sudo pacman -S $pkg"
    elif command -v brew >/dev/null 2>&1; then
        if [ "$pkg" = bash-completion ]; then
            echo "brew install bash bash-completion@2"
        else
            echo "brew install $pkg"
        fi
    else
        echo "install $pkg with your package manager"
    fi
}

require_git() {
    if ! command -v git >/dev/null 2>&1; then
        echo "git is required. Install it, then run this script again:" >&2
        echo "    $(pkg_install_hint git)" >&2
        exit 1
    fi
}

clone_or_update() {
    if [ -d "$SHELLMOI_DIR/.git" ]; then
        if git -C "$SHELLMOI_DIR" rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1; then
            echo "Updating $SHELLMOI_DIR"
            git -C "$SHELLMOI_DIR" pull --ff-only --quiet
        else
            echo "Using $SHELLMOI_DIR as is (its branch has no upstream to pull from)"
        fi
    elif [ -e "$SHELLMOI_DIR" ]; then
        echo "$SHELLMOI_DIR exists but is not a git repository; move it away or set SHELLMOI_DIR." >&2
        exit 1
    else
        echo "Cloning $SHELLMOI_REPO into $SHELLMOI_DIR"
        mkdir -p "$(dirname "$SHELLMOI_DIR")"
        git clone --quiet "$SHELLMOI_REPO" "$SHELLMOI_DIR"
    fi
}

# Copies the file only if the target does not exist yet: the app owns it from then on
copy_once() {
    local src=$1 target=$2 file=$3
    if [ -e "$target" ] || [ -L "$target" ]; then
        echo "  kept existing  ~/$file"
    else
        cp "$src" "$target"
        echo "  copied         ~/$file"
    fi
}

# Links the target to the source, moving anything else at that path to a backup
link() {
    local src=$1 target=$2 file=$3
    if [ -L "$target" ] && [ "$(readlink "$target")" = "$src" ]; then
        echo "  up to date     ~/$file"
        return
    fi
    if [ -e "$target" ] || [ -L "$target" ]; then
        mv "$target" "$target$BACKUP_SUFFIX"
        echo "  backed up      ~/$file -> ~/$file$BACKUP_SUFFIX"
    fi
    ln -s "$src" "$target"
    echo "  linked         ~/$file"
}

deploy() {
    local file target
    echo "Installing into $HOME"
    while IFS= read -r -d '' file; do
        case "$file" in
            README.md|AGENTS.md|CLAUDE.md|.gitignore|install.sh) continue ;;
        esac
        target="$HOME/$file"
        mkdir -p "$(dirname "$target")"
        case "$file" in
            .claude/settings.json|.codex/config.toml)
                copy_once "$SHELLMOI_DIR/$file" "$target" "$file" ;;
            *)
                link "$SHELLMOI_DIR/$file" "$target" "$file" ;;
        esac
    done < <(git -C "$SHELLMOI_DIR" ls-files -z)
}

check_bash_completion() {
    if [ -f /usr/share/bash-completion/bash_completion ]; then
        return
    fi
    if command -v brew >/dev/null 2>&1 &&
        [ -s "$(brew --prefix)/etc/profile.d/bash_completion.sh" ]; then
        return
    fi
    echo
    echo "bash-completion is not installed. Install it with:"
    echo "    $(pkg_install_hint bash-completion)"
    if [ "$(uname -s)" = Darwin ]; then
        echo "macOS also needs a newer Bash as the login shell; see the README."
    fi
}

main() {
    require_git
    clone_or_update
    deploy
    check_bash_completion
    echo
    echo "Done. Open a new shell to load the configuration."
    echo "To push changes, switch the clone to SSH:"
    echo "    git -C $SHELLMOI_DIR remote set-url origin git@github.com:dmarcelino/shellmoi.git"
}

main "$@"
