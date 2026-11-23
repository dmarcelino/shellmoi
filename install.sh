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
# Private profiles: one folder each, laid out like $HOME; git ignores the folder
PRIVATE_DIR="$SHELLMOI_DIR/private"
GIT_PROFILES=".config/git/profiles.gitconfig"
GIT_PROFILES_HEADER="# Written by shellmoi's install.sh from ~/.config/git/profiles/; do not edit"
SSH_CONFIG_CONTENT="# Written by shellmoi's install.sh: loads the private profiles' SSH settings
Include config.d/*.conf"
# What install linked from the profiles, one home-relative path per line, so a later
# install or uninstall finds links to files a profile no longer has
PRIVATE_LINKS="$HOME/.local/state/shellmoi/private-links"

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
            # --no-rebase: a pull.rebase setting, such as shellmoi's own, would otherwise
            # rebase, which stops when the clone has local changes
            git -C "$SHELLMOI_DIR" pull --no-rebase --ff-only --quiet
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
    local src=$1 target=$2 file=$3 backup=${4:-$3$BACKUP_SUFFIX} current
    if [ -L "$target" ]; then
        current=$(readlink "$target")
        if [ "$current" = "$src" ]; then
            echo "  up to date     ~/$file"
            return
        fi
        # Another link into the clone, such as a profile's file after a rename: shellmoi's,
        # not the user's, so replaced rather than backed up
        if [ "${current#"$SHELLMOI_DIR"/}" != "$current" ]; then
            rm "$target"
            ln -s "$src" "$target"
            echo "  relinked       ~/$file"
            return
        fi
    fi
    if [ -e "$target" ] || [ -L "$target" ]; then
        # Never over an earlier backup, which may hold the only copy of the user's file
        if [ -e "$HOME/$backup" ] || [ -L "$HOME/$backup" ]; then
            echo "  kept           ~/$file (~/$backup is taken; run the install again)"
            return
        fi
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
            README.md|LICENSE|AGENTS.md|CLAUDE.md|.gitignore|install.sh|push.sh) continue ;;
            install-tools.sh|tools/*|tests/*) continue ;;
            skills/*) continue ;;  # see deploy_skills
        esac
        printf '%s\0' "$file"
    done < <(git -C "$SHELLMOI_DIR" ls-files -z)
}

# Files the apps write to, so they are copied instead of linked
is_copied_once() {
    case "$1" in
        .codex/config.toml) return 0 ;;
        *) return 1 ;;
    esac
}

# JSON files the apps write to, and often create before shellmoi is installed: merged into
# an existing file instead of skipped
is_merged() {
    case "$1" in
        .claude/settings.json) return 0 ;;
        *) return 1 ;;
    esac
}

# What shellmoi did to a merged file, kept out of the apps' folders: <file>.installed marks
# that the install copied or merged it, <file>.original is the file from before the merge
STATE_DIR="$HOME/.local/state/shellmoi"

# Prints shellmoi's settings merged with the existing ones; the existing ones win
json_merge() {
    jq -s '.[0] * .[1]' "$1" "$2"
}

# Installs shellmoi's settings once: copied if the file is missing, else merged into it with
# the original kept for uninstall. Later runs leave the file alone, so a setting removed
# from it stays removed.
merge_json() {
    local src=$1 target=$2 file=$3 marker="$STATE_DIR/$3.installed" original="$STATE_DIR/$3.original"
    local merged="$target.shellmoi-merge"
    if [ -e "$marker" ]; then
        echo "  kept           ~/$file (installed before; yours to change)"
        return
    fi
    mkdir -p "$(dirname "$marker")"
    if [ ! -e "$target" ] && [ ! -L "$target" ]; then
        cp "$src" "$target"
        : > "$marker"
        echo "  copied         ~/$file"
        return
    fi
    if cmp -s "$src" "$target"; then
        : > "$marker"
        echo "  up to date     ~/$file"
        return
    fi
    if [ -L "$target" ] || [ -e "$original" ] || ! command -v jq >/dev/null 2>&1; then
        echo "  kept existing  ~/$file (not merged: needs jq, a plain file and no earlier"
        echo "                 original in ${STATE_DIR#"$HOME"/}); compare with"
        echo "                 diff ~/$file $src"
        return
    fi
    # A copy of the target keeps its permissions, which may guard secrets in it
    cp -p "$target" "$merged"
    if ! json_merge "$src" "$target" > "$merged" 2>/dev/null; then
        rm -f "$merged"
        echo "  kept existing  ~/$file (not valid JSON, so not merged)"
        return
    fi
    cp -p "$target" "$original"
    mv "$merged" "$target"
    : > "$marker"
    echo "  merged         ~/$file (your settings win; original in ~/${original#"$HOME"/})"
}

# Prints the name of each skill directory, one per line
skill_names() {
    local dir
    for dir in "$SHELLMOI_DIR"/skills/*/; do
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
        if is_merged "$file"; then
            merge_json "$SHELLMOI_DIR/$file" "$target" "$file"
        elif is_copied_once "$file"; then
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
            link "$SHELLMOI_DIR/skills/$name" "$HOME/$file" "$file" \
                "$tool/skills$BACKUP_SUFFIX/$name"
        done
    done < <(skill_names)
}

# Prints, NUL-separated, each file of the private profiles as <profile>/<home-relative path>,
# profiles in name order. Dot-folders such as .git and .backups are not profiles, and the
# leftovers of Finder and editors are not files of them (push.sh skips the same).
private_files() {
    local dir
    for dir in "$PRIVATE_DIR"/*/; do
        [ -d "$dir" ] || continue
        dir=${dir%/}
        (cd "$dir" && find . \( -name .git -o -name .DS_Store -o -name '*~' -o -name '.*.sw?' \) \
            -prune -o \( -type f -o -type l \) -print0) |
            while IFS= read -r -d '' file; do
                printf '%s/%s\0' "${dir##*/}" "${file#./}"
            done
    done
}

# Prints, NUL-separated, <action>:<profile>/<home-relative path> for each file of the
# profiles. The action is "link", or "shellmoi" for a path shellmoi links itself, or "taken"
# for a file an earlier profile has: profiles add files of their own, such as
# ~/.bashrc.d/<profile>.sh, and never replace shellmoi's.
private_links() {
    local entry file name managed=$'\n' skills seen=$'\n'
    while IFS= read -r -d '' file; do
        managed="$managed$file"$'\n'
    done < <(managed_files)
    skills=$'\n'"$(skill_names)"$'\n'
    while IFS= read -r -d '' entry; do
        file=${entry#*/}
        name=
        case "$file" in
            .claude/skills/*|.codex/skills/*)
                name=${file#*/skills/}
                name=${name%%/*}
                ;;
        esac
        if [[ $managed == *$'\n'"$file"$'\n'* ]] ||
            { [ -n "$name" ] && [[ $skills == *$'\n'"$name"$'\n'* ]]; }; then
            printf 'shellmoi:%s\0' "$entry"
        elif [[ $seen == *$'\n'"$file"$'\n'* ]]; then
            printf 'taken:%s\0' "$entry"
        else
            seen="$seen$file"$'\n'
            printf 'link:%s\0' "$entry"
        fi
    done < <(private_files)
}

# Undoes the link of a profile's file: removes it if it still points into the profiles, and
# puts back what it replaced
unlink_private() {
    local file=$1 current
    if [ -L "$HOME/$file" ]; then
        current=$(readlink "$HOME/$file")
        if [ "${current#"$PRIVATE_DIR"/}" != "$current" ]; then
            unlink_restore "$current" "$file"
            return
        fi
    fi
    if [ -e "$HOME/$file" ] || [ -L "$HOME/$file" ]; then
        echo "  kept           ~/$file (not a shellmoi link)"
    fi
}

# Links each file of the private profiles into $HOME, then unlinks what an earlier install
# linked from a file the profiles no longer have, such as one removed or renamed
deploy_private() {
    local record entry file linked=$'\n'
    [ -d "$PRIVATE_DIR" ] || [ -s "$PRIVATE_LINKS" ] || return 0
    echo "Installing the private profiles in $PRIVATE_DIR"
    while IFS= read -r -d '' record; do
        entry=${record#*:}
        file=${entry#*/}
        case "${record%%:*}" in
            shellmoi)
                echo "  skipped        ~/$file of profile ${entry%%/*} (shellmoi links it)"
                continue
                ;;
            taken)
                echo "  skipped        ~/$file of profile ${entry%%/*} (an earlier profile has it)"
                continue
                ;;
        esac
        case "$file" in
            .ssh/*) [ -d "$HOME/.ssh" ] || mkdir -m 700 "$HOME/.ssh" ;;
        esac
        mkdir -p "$(dirname "$HOME/$file")"
        link "$PRIVATE_DIR/$entry" "$HOME/$file" "$file"
        linked="$linked$file"$'\n'
    done < <(private_links)
    if [ -f "$PRIVATE_LINKS" ]; then
        while IFS= read -r file; do
            if [[ $linked != *$'\n'"$file"$'\n'* ]]; then
                unlink_private "$file"
            fi
        done < "$PRIVATE_LINKS"
    fi
    linked=${linked#$'\n'}
    if [ -n "$linked" ]; then
        mkdir -p "$(dirname "$PRIVATE_LINKS")"
        printf '%s' "$linked" > "$PRIVATE_LINKS"
    elif [ -e "$PRIVATE_LINKS" ]; then
        rm "$PRIVATE_LINKS"
        remove_empty_dirs "$(dirname "$PRIVATE_LINKS")"
    fi
}

# Writes ~/.config/git/profiles.gitconfig, which the shared git config includes: git cannot
# include a folder, so it lists each file in ~/.config/git/profiles/
write_git_profiles() {
    local file includes="" target="$HOME/$GIT_PROFILES"
    for file in "$HOME"/.config/git/profiles/*.gitconfig; do
        if [ -e "$file" ]; then
            includes="$includes[include]"$'\n'"	path = profiles/${file##*/}"$'\n'
        fi
    done
    if [ -e "$target" ] && [ "$(head -n 1 "$target")" != "$GIT_PROFILES_HEADER" ]; then
        echo "  kept existing  ~/$GIT_PROFILES (not written by shellmoi)"
    elif [ -z "$includes" ]; then
        remove_git_profiles
    elif [ "$(cat "$target" 2>/dev/null)" = "$GIT_PROFILES_HEADER"$'\n'"${includes%$'\n'}" ]; then
        echo "  up to date     ~/$GIT_PROFILES"
    else
        printf '%s\n%s' "$GIT_PROFILES_HEADER" "$includes" > "$target"
        echo "  wrote          ~/$GIT_PROFILES"
    fi
}

# Removes ~/.config/git/profiles.gitconfig if shellmoi wrote it
remove_git_profiles() {
    local target="$HOME/$GIT_PROFILES"
    if [ -f "$target" ] && [ "$(head -n 1 "$target")" = "$GIT_PROFILES_HEADER" ]; then
        rm "$target"
        echo "  removed        ~/$GIT_PROFILES"
        remove_empty_dirs "$(dirname "$target")"
    fi
}

# The profiles' SSH settings are in ~/.ssh/config.d/<profile>.conf, which ~/.ssh/config must
# include. Creates ~/.ssh/config if it is missing; never edits one that is there.
ensure_ssh_include() {
    local config="$HOME/.ssh/config"
    [ -d "$HOME/.ssh/config.d" ] || return 0
    if [ ! -e "$config" ] && [ ! -L "$config" ]; then
        (umask 077 && printf '%s\n' "$SSH_CONFIG_CONTENT" > "$config")
        echo "  created        ~/.ssh/config (includes ~/.ssh/config.d/*.conf)"
    elif ! has_ssh_include "$config"; then
        echo
        echo "~/.ssh/config does not load the private profiles' SSH settings. Add this line"
        echo "at its top, before any Host or Match:"
        echo "    Include config.d/*.conf"
    fi
}

# Whether the SSH config includes config.d/ before its first Host or Match: inside a Host
# or Match block, an Include applies to that block only
has_ssh_include() {
    awk '
        { keyword = tolower($1) }
        keyword == "host" || keyword == "match" { exit }
        keyword == "include" && /config\.d\// { found = 1; exit }
        END { exit !found }
    ' "$1" 2>/dev/null
}

# Removes ~/.ssh/config if it still holds only what ensure_ssh_include wrote
remove_ssh_include() {
    local config="$HOME/.ssh/config"
    if [ -f "$config" ] && [ ! -L "$config" ] && [ "$(cat "$config")" = "$SSH_CONFIG_CONTENT" ]; then
        rm "$config"
        echo "  removed        ~/.ssh/config"
        remove_empty_dirs "$HOME/.ssh"
    fi
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

# Undoes merge_json: puts back the original from before the merge, if there was one. The
# installed file goes if it is still what install wrote, else it stays as a backup.
unmerge_json() {
    local src=$1 file=$2 target="$HOME/$2" marker="$STATE_DIR/$2.installed"
    local original="$STATE_DIR/$2.original" backup
    if [ ! -e "$original" ]; then
        uncopy_once "$src" "$file"
        rm -f "$marker"
        remove_empty_dirs "$(dirname "$marker")"
        return
    fi
    if [ -L "$target" ] || { [ -e "$target" ] && [ ! -f "$target" ]; }; then
        echo "  kept           ~/$file (not a shellmoi file)"
        return
    fi
    if [ -f "$target" ]; then
        if command -v jq >/dev/null 2>&1 &&
            json_merge "$src" "$original" 2>/dev/null | cmp -s - "$target"; then
            rm "$target"
        else
            backup="$HOME/$file$BACKUP_SUFFIX"
            while [ -e "$backup" ] || [ -L "$backup" ]; do
                backup="$backup.1"
            done
            mv "$target" "$backup"
            echo "  left backup    ~/${backup#"$HOME"/} (changed since the merge)"
        fi
    fi
    mv "$original" "$target"
    rm -f "$marker"
    echo "  restored       ~/$file (from before the merge)"
    remove_empty_dirs "$(dirname "$marker")"
}

undeploy() {
    local file
    while IFS= read -r -d '' file; do
        if is_merged "$file"; then
            unmerge_json "$SHELLMOI_DIR/$file" "$file"
        elif is_copied_once "$file"; then
            uncopy_once "$SHELLMOI_DIR/$file" "$file"
        else
            unlink_restore "$SHELLMOI_DIR/$file" "$file"
        fi
    done < <(managed_files)
}

# Undoes deploy_private, from what it recorded: also the links to files the profiles no
# longer have
undeploy_private() {
    local file
    [ -f "$PRIVATE_LINKS" ] || return 0
    while IFS= read -r file; do
        unlink_private "$file"
    done < "$PRIVATE_LINKS"
    rm "$PRIVATE_LINKS"
    remove_empty_dirs "$(dirname "$PRIVATE_LINKS")"
}

undeploy_skills() {
    local name tool file
    while IFS= read -r name; do
        for tool in .codex .claude; do
            file="$tool/skills/$name"
            unlink_restore "$SHELLMOI_DIR/skills/$name" "$file" "$tool/skills" "/$name"
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
}

# macOS starts zsh or Bash 3.2 by default; this configuration needs Bash 4 or later
check_login_shell() {
    local version brew_bash
    [ "$(uname -s)" = Darwin ] && [ -n "${SHELL:-}" ] || return 0
    version=$("$SHELL" -c 'echo "${BASH_VERSINFO[0]:-0}"' 2>/dev/null) || version=0
    [ "${version:-0}" -lt 4 ] || return 0
    brew_bash="$(brew --prefix 2>/dev/null || echo /opt/homebrew)/bin/bash"
    echo
    echo "Your login shell, $SHELL, is not Bash 4 or later, which this configuration needs."
    echo "Install Bash from Homebrew and make it your login shell:"
    [ -x "$brew_bash" ] || echo "    brew install bash"
    grep -qx "$brew_bash" /etc/shells 2>/dev/null ||
        echo "    echo $brew_bash | sudo tee -a /etc/shells"
    echo "    chsh -s $brew_bash"
}

# The files in ~ are links into the clone, so an installer that appends to ~/.bashrc edits
# a file of this public repository
check_local_changes() {
    local changes
    changes=$(git -C "$SHELLMOI_DIR" status --porcelain --untracked-files=no 2>/dev/null) ||
        return 0
    [ -n "$changes" ] || return 0
    echo
    echo "These files in $SHELLMOI_DIR have local changes:"
    echo "$changes" | sed 's/^/    /'
    echo "They are linked into ~, so whatever edits ~/.bashrc and the like edits them."
    echo "Move private or machine-specific lines to ~/.bashrc.local, which git ignores."
}

run_install() {
    require_git
    clone_or_update
    deploy
    deploy_skills
    deploy_private
    write_git_profiles
    ensure_local_gitconfig
    ensure_ssh_include
    check_login_shell
    check_bash_completion
    check_diff_so_fancy
    check_local_changes
    echo
    echo "Done. Open a new shell to load the configuration."
    # For a GitHub clone over HTTPS, which pushes only with a token or credential helper:
    # the same repository over SSH, a fork included
    local origin
    origin=$(git -C "$SHELLMOI_DIR" remote get-url origin 2>/dev/null || true)
    case "$origin" in
        https://github.com/*)
            echo "To push over SSH instead of HTTPS, switch the clone's remote:"
            printf '    git -C %q remote set-url origin git@github.com:%s\n' \
                "$SHELLMOI_DIR" "${origin#https://github.com/}"
            ;;
    esac
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
    undeploy_private
    remove_git_profiles
    remove_ssh_include
    remove_local_gitconfig
    echo
    echo "Done. Open a new shell to load your previous configuration."
    echo "The clone stays in $SHELLMOI_DIR; delete it if you no longer need it."
    if [ -d "$PRIVATE_DIR" ]; then
        echo "It holds your private profiles in $PRIVATE_DIR: deleting the clone deletes them."
    fi
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
