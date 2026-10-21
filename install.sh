#!/usr/bin/env bash
# Install or update shellmoi: clone the repository, then link its files into $HOME.
#
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/dmarcelino/shellmoi/main/install.sh)"
#
# Safe to run again: it pulls the latest changes and only touches what changed.
# `install.sh uninstall` removes the links and puts back what the first install moved away.
# Must run under Bash 3.2 (the macOS default), so no mapfile or associative arrays.

set -euo pipefail

SHELLMOI_REPO="${SHELLMOI_REPO:-https://github.com/dmarcelino/shellmoi.git}"
SHELLMOI_DIR="${SHELLMOI_DIR:-$HOME/.local/share/shellmoi}"
BACKUP_SUFFIX=".bak.$(date +%Y%m%d-%H%M%S)"
# Matches the timestamp in BACKUP_SUFFIX only, not backups other tools made
BACKUP_STAMP_GLOB='[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9]'
GITCONFIG_HEADER="# Machine-specific git settings: user.name, user.email, credential helpers"

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
# (by default next to the target; pass a home-relative backup path to put it elsewhere)
link() {
    local src=$1 target=$2 file=$3 backup=${4:-$3$BACKUP_SUFFIX}
    if [ -L "$target" ] && [ "$(readlink "$target")" = "$src" ]; then
        echo "  up to date     ~/$file"
        return
    fi
    if [ -e "$target" ] || [ -L "$target" ]; then
        mkdir -p "$(dirname "$HOME/$backup")"
        mv "$target" "$HOME/$backup"
        echo "  backed up      ~/$file -> ~/$backup"
    fi
    ln -s "$src" "$target"
    echo "  linked         ~/$file"
}

# Prints, NUL-separated, the tracked files that deploy puts into $HOME
managed_files() {
    local file
    while IFS= read -r -d '' file; do
        case "$file" in
            README.md|LICENSE|AGENTS.md|CLAUDE.md|.gitignore|install.sh) continue ;;
            install-tools.sh|tools/*|tests/*) continue ;;
            .claude/skills|.codex/skills/*) continue ;;  # see deploy_skills
        esac
        printf '%s\0' "$file"
    done < <(git -C "$SHELLMOI_DIR" ls-files -z)
}

# Files the apps write to, so they are copied instead of linked
is_copied_once() {
    case "$1" in
        .claude/settings.json|.codex/config.toml) return 0 ;;
        *) return 1 ;;
    esac
}

# Prints the name of each skill directory, one per line
skill_names() {
    local dir
    for dir in "$SHELLMOI_DIR"/.codex/skills/*/; do
        [ -d "$dir" ] || continue
        basename "$dir"
    done
}

deploy() {
    local file target
    echo "Installing into $HOME"
    while IFS= read -r -d '' file; do
        target="$HOME/$file"
        mkdir -p "$(dirname "$target")"
        if is_copied_once "$file"; then
            copy_once "$SHELLMOI_DIR/$file" "$target" "$file"
        else
            link "$SHELLMOI_DIR/$file" "$target" "$file"
        fi
    done < <(managed_files)
}

# Links each skill directory on its own, so other skills in ~/.claude/skills and
# ~/.codex/skills stay. Backups go outside the skills folders: a backup inside them still
# holds a SKILL.md and would load as a second copy of the skill.
deploy_skills() {
    local name tool file
    while IFS= read -r name; do
        for tool in .codex .claude; do
            file="$tool/skills/$name"
            mkdir -p "$HOME/$tool/skills"
            link "$SHELLMOI_DIR/$file" "$HOME/$file" "$file" \
                "$tool/skills$BACKUP_SUFFIX/$name"
        done
    done < <(skill_names)
}

# Without ~/.gitconfig, `git config --global` writes to ~/.config/git/config, which is a
# link into this repository: private values like user.email would end up in it
ensure_local_gitconfig() {
    if [ ! -e "$HOME/.gitconfig" ]; then
        echo "$GITCONFIG_HEADER" > "$HOME/.gitconfig"
        echo "  created        ~/.gitconfig (set user.name and user.email with git config --global)"
    fi
}

# Removes the directory and its parents while they are empty, stopping below $HOME
remove_empty_dirs() {
    local dir=$1
    while [ "${dir#"$HOME"/}" != "$dir" ] && rmdir "$dir" 2>/dev/null; do
        dir=$(dirname "$dir")
    done
}

# Prints the backups link made of a home-relative path, oldest first: the backup path is
# <prefix><BACKUP_SUFFIX><suffix>, as in link's backup argument
backups() {
    local prefix=$1 suffix=$2 backup
    # shellcheck disable=SC2086  # the stamp pattern must expand
    for backup in "$HOME/$prefix.bak."$BACKUP_STAMP_GLOB"$suffix"; do
        if [ -e "$backup" ] || [ -L "$backup" ]; then
            echo "$backup"
        fi
    done
}

# Undoes link: removes the link to the source and moves the oldest backup back, which
# holds what was there before the first install. Newer backups stay and are listed.
unlink_restore() {
    local src=$1 file=$2 backup_prefix=${3:-$2} backup_suffix=${4:-}
    local target="$HOME/$2" backup restored= removed=
    if [ -L "$target" ] && [ "$(readlink "$target")" = "$src" ]; then
        rm "$target"
        removed=1
    elif [ -e "$target" ] || [ -L "$target" ]; then
        echo "  kept           ~/$file (not a shellmoi link)"
        return
    fi
    while IFS= read -r backup; do
        if [ -z "$restored" ]; then
            mv "$backup" "$target"
            restored=$backup
            echo "  restored       ~/$file <- ~/${backup#"$HOME"/}"
            remove_empty_dirs "$(dirname "$backup")"
        else
            echo "  left backup    ~/${backup#"$HOME"/}"
        fi
    done < <(backups "$backup_prefix" "$backup_suffix")
    if [ -z "$restored" ] && [ -n "$removed" ]; then
        echo "  removed        ~/$file"
        remove_empty_dirs "$(dirname "$target")"
    fi
}

# Undoes copy_once: removes the copy unless it was changed since
uncopy_once() {
    local src=$1 file=$2 target="$HOME/$2"
    if [ -f "$target" ] && [ ! -L "$target" ] && cmp -s "$src" "$target"; then
        rm "$target"
        echo "  removed        ~/$file"
        remove_empty_dirs "$(dirname "$target")"
    elif [ -e "$target" ] || [ -L "$target" ]; then
        echo "  kept           ~/$file (differs from shellmoi's copy)"
    fi
}

undeploy() {
    local file
    while IFS= read -r -d '' file; do
        if is_copied_once "$file"; then
            uncopy_once "$SHELLMOI_DIR/$file" "$file"
        else
            unlink_restore "$SHELLMOI_DIR/$file" "$file"
        fi
    done < <(managed_files)
}

undeploy_skills() {
    local name tool file
    while IFS= read -r name; do
        for tool in .codex .claude; do
            file="$tool/skills/$name"
            unlink_restore "$SHELLMOI_DIR/$file" "$file" "$tool/skills" "/$name"
        done
    done < <(skill_names)
}

# Removes ~/.gitconfig if it still holds only what ensure_local_gitconfig wrote
remove_local_gitconfig() {
    if [ -f "$HOME/.gitconfig" ] && [ "$(cat "$HOME/.gitconfig")" = "$GITCONFIG_HEADER" ]; then
        rm "$HOME/.gitconfig"
        echo "  removed        ~/.gitconfig"
    fi
}

check_diff_so_fancy() {
    if ! command -v diff-so-fancy >/dev/null 2>&1; then
        echo
        echo "diff-so-fancy is not installed: git diffs will be plain, and lazygit expects it."
        echo "Install it with:"
        echo "    $SHELLMOI_DIR/install-tools.sh shell"
    fi
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

run_install() {
    require_git
    clone_or_update
    deploy
    deploy_skills
    ensure_local_gitconfig
    check_bash_completion
    check_diff_so_fancy
    echo
    echo "Done. Open a new shell to load the configuration."
    echo "To push changes, switch the clone to SSH:"
    echo "    git -C $SHELLMOI_DIR remote set-url origin git@github.com:dmarcelino/shellmoi.git"
}

run_uninstall() {
    require_git
    if [ ! -d "$SHELLMOI_DIR/.git" ]; then
        echo "$SHELLMOI_DIR is not a shellmoi clone, so there is nothing to uninstall." >&2
        echo "Set SHELLMOI_DIR if you installed from another location." >&2
        exit 1
    fi
    echo "Uninstalling from $HOME"
    undeploy_skills
    undeploy
    remove_local_gitconfig
    echo
    echo "Done. Open a new shell to load your previous configuration."
    echo "The clone stays in $SHELLMOI_DIR; delete it if you no longer need it."
}

main() {
    case "${1:-install}" in
        install) run_install ;;
        uninstall) run_uninstall ;;
        *)
            echo "Usage: install.sh [install|uninstall]" >&2
            exit 2
            ;;
    esac
}

main "$@"
