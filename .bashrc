# ~/.bashrc: executed by bash(1) for interactive non-login shells, and by ~/.bash_profile.

# Tells ~/.bash_profile this file already ran
SHELLMOI_BASHRC=1

## PATH ##

# Set before the interactive check below, so non-interactive shells (bash -lc from IDEs and
# agents, ssh commands on Debian) find the same tools as an interactive one

# Moves the directory to the front of PATH, removing any other copy of it
_shellmoi_path_prepend() {
    local path=":$PATH:"
    while [[ $path == *":$1:"* ]]; do
        path=${path//":$1:"/:}
    done
    path=${path#:}
    path=${path%:}
    PATH="$1${path:+:$path}"
}

# Removes repeated PATH entries, keeping the first, such as those an inherited PATH brings
_shellmoi_path_dedupe() {
    local rest="$PATH:" dir new=":"
    while [ -n "$rest" ]; do
        dir=${rest%%:*}
        rest=${rest#*:}
        if [ -n "$dir" ] && [[ $new != *":$dir:"* ]]; then
            new="$new$dir:"
        fi
    done
    new=${new#:}
    PATH=${new%:}
}

# Homebrew (macOS or Linux), if installed; before the directories below, which go in front.
# On macOS, path_helper puts Homebrew after /bin in login shells, where /bin/bash is 3.2.
# Its full environment (HOMEBREW_PREFIX, MANPATH) only in interactive shells, once: running
# brew for every ssh command, scp or agent's bash -lc would slow them all down.
for brew in /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew; do
    if [ -x "$brew" ]; then
        if [[ $- == *i* ]] && [ -z "${HOMEBREW_PREFIX:-}" ]; then
            eval "$("$brew" shellenv bash)"
        fi
        _shellmoi_path_prepend "${brew%/bin/brew}/sbin"
        _shellmoi_path_prepend "${brew%/bin/brew}/bin"
        break
    fi
done
unset brew

# Tool and private bin directories, if they exist; ~/.local/bin ends up first, even when
# path_helper (macOS login shells, tmux) moved it behind the system directories
for dir in /usr/local/go/bin "$HOME/go/bin" "$HOME/.cargo/bin" "$HOME/.bun/bin" "$HOME/bin" "$HOME/.local/bin"; do
    if [ -d "$dir" ]; then
        _shellmoi_path_prepend "$dir"
    fi
done
unset dir
_shellmoi_path_dedupe
unset -f _shellmoi_path_prepend _shellmoi_path_dedupe
export PATH

## LOCALE ##

# SSH from Windows sends no locale, so the shell, and any tmux it starts, falls back to C;
# tmux then draws every non-ASCII character as "_". Fill one in only when none is set, so
# terminals that send their own keep it. Only a locale this host has, or bash warns.
if [ -z "${LC_ALL:-}${LC_CTYPE:-}${LANG:-}" ]; then
    available=$(locale -a 2>/dev/null)
    for candidate in en_US.UTF-8 C.UTF-8; do
        # locale -a spells them en_US.utf8 / C.utf8 on most Linux systems
        if grep -qix "${candidate%%.*}\.utf-\?8" <<<"$available"; then
            export LANG=$candidate
            break
        fi
    done
    unset available candidate
fi

# If not running interactively, don't do anything more
case $- in
    *i*) ;;
      *) return;;
esac

## DEFAULTS ##

# bash-completion, if available; the guard avoids loading it twice
if ! shopt -oq posix && [ -z "${BASH_COMPLETION_VERSINFO:-}" ]; then
    if [ -f /usr/share/bash-completion/bash_completion ]; then
        . /usr/share/bash-completion/bash_completion
    elif [ -s "${HOMEBREW_PREFIX:-}/etc/profile.d/bash_completion.sh" ]; then
        . "$HOMEBREW_PREFIX/etc/profile.d/bash_completion.sh"
    fi
fi

# git completion for Apple's git, which keeps it where bash-completion does not look;
# Homebrew's git ships its own. The files first: they only exist on macOS.
for git_completion in \
    /Library/Developer/CommandLineTools/usr/share/git-core/git-completion.bash \
    /Applications/Xcode.app/Contents/Developer/usr/share/git-core/git-completion.bash; do
    if [ -f "$git_completion" ]; then
        if [ "$(command -v git)" = /usr/bin/git ]; then
            . "$git_completion"
        fi
        break
    fi
done
unset git_completion

# Saner history, tab completion and directory navigation
if [ -f ~/.config/bash/sensible/sensible.bash ]; then
    # bash-sensible replaces PROMPT_COMMAND; keep what was there, such as the hook macOS
    # Terminal uses to open new tabs in the same folder
    prompt_command=${PROMPT_COMMAND:-}
    prompt_command=${prompt_command#history -a}
    prompt_command=${prompt_command#; }
    . ~/.config/bash/sensible/sensible.bash
    if [ -n "$prompt_command" ]; then
        PROMPT_COMMAND="$PROMPT_COMMAND; $prompt_command"
    fi
    unset prompt_command
fi

# The clone this file is in, from the ~/.bashrc link: `cd SHELLMOI_DIR` goes there
# (bash-sensible's cdable_vars), and install.sh and push.sh use it. Follows relative links
# and chains of them; left unset outside a clone, such as for a copy of this file, so the
# scripts use their default.
shellmoi_rc=${BASH_SOURCE[0]}
while [ -L "$shellmoi_rc" ]; do
    shellmoi_link=$(readlink "$shellmoi_rc")
    case $shellmoi_link in
        /*) shellmoi_rc=$shellmoi_link ;;
        *) shellmoi_rc=$(dirname "$shellmoi_rc")/$shellmoi_link ;;
    esac
done
# CDPATH empty: with bash-sensible's ".", cd prints the folder too
if shellmoi_dir=$(CDPATH='' cd -P -- "$(dirname "$shellmoi_rc")" && pwd) &&
    [ -f "$shellmoi_dir/install.sh" ]; then
    export SHELLMOI_DIR=$shellmoi_dir
fi
unset shellmoi_rc shellmoi_link shellmoi_dir

# Keep commands that name a secret out of the history, such as `export AWS_SECRET_ACCESS_KEY=...`
# or `GITHUB_TOKEN=... gh api`. Upper case only, as environment variables are written, so
# `./get_jwt_token.py` is kept
HISTIGNORE="${HISTIGNORE:+$HISTIGNORE:}*SECRET*:*TOKEN*:*PASSWORD*:*PASSWD*:*_KEY*:*APIKEY*:*JWT*:*CREDENTIAL*"

# make less more friendly for non-text input files, see lesspipe(1)
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# Colors for ls
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
fi

## PROMPT ##

# Current git branch, e.g. "(main)"; empty outside a repository
parse_git_branch() {
    git branch 2> /dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/(\1)/'
}

# Current kubectl namespace, e.g. "[default]"; only inside a path containing "helm"
parse_kubectl_namespace() {
    if [[ $PWD == *helm* ]] && command -v kubectl >/dev/null 2>&1; then
        printf '[%s]' "$(kubectl config view --minify --output 'jsonpath={..namespace}' 2>/dev/null)"
    fi
}

# user@host:folder(branch)[namespace]$
PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\W\[\033[01;31m\]$(parse_git_branch)\[\033[01;33m\]$(parse_kubectl_namespace)\[\033[00m\]\$ '

# Terminal title: the full path, from ~ inside home; "user@host: path" in xterm, and inside
# tmux the path alone, as the pane title (#T), which shows in a tab only with
# `set -g set-titles on` or #T in window-status-format.
# Not \w: PROMPT_DIRTRIM (bash-sensible) shortens it to the last folders.
# Invisible marks wrap the title: \342\200\217\342\200\216 (U+200F U+200E) before it and
# \342\200\216 (U+200E) after it. With `unicode-bidi: plaintext` on its tab names, a terminal
# such as Tabby then cuts a long title at the start, not the end (see the README)
# Outside tmux, OSC 1337 CurrentDir also reports the folder, so Tabby can open a new tab or
# SFTP there, even over SSH. tmux does not pass it on.
case "$TERM" in
xterm*|rxvt*)
    PS1='\[\e]0;\342\200\217\342\200\216\u@\h: ${PWD/#"$HOME"/\~}\342\200\216\a\]\[\e]1337;CurrentDir=${PWD}\a\]'"$PS1"
    ;;
tmux*|screen*)
    PS1='\[\e]2;\342\200\217\342\200\216${PWD/#"$HOME"/\~}\342\200\216\a\]'"$PS1"
    ;;
esac

## ALIASES ##

if [ -f ~/.bash_aliases ]; then
    . ~/.bash_aliases
fi

## TOOLS ##

if command -v kubectl >/dev/null 2>&1; then
    source <(kubectl completion bash)
fi

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# fzf key bindings: Ctrl-R searches history, Ctrl-T picks files, Alt-C changes folder.
# fzf before 0.48 (older apt versions) has no --bash; Debian ships the bindings as a file.
if command -v fzf >/dev/null 2>&1; then
    if fzf_init=$(fzf --bash 2>/dev/null) && [ -n "$fzf_init" ]; then
        eval "$fzf_init"
    elif [ -f /usr/share/doc/fzf/examples/key-bindings.bash ]; then
        . /usr/share/doc/fzf/examples/key-bindings.bash
    fi
    unset fzf_init
fi

# worktrunk shell integration, so `wt switch` can change directory
if command -v wt >/dev/null 2>&1; then eval "$(command wt config shell init bash)"; fi

# SDKMAN must be initialised after other PATH changes
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]] && source "$SDKMAN_DIR/bin/sdkman-init.sh"

## LOCAL ##

# Drop-in files, one per private profile (see "Private profiles" in the README)
for file in ~/.bashrc.d/*.sh; do
    if [ -r "$file" ]; then
        . "$file"
    fi
done
unset file

# Machine-specific or private settings (secrets, work aliases); never committed
if [ -f ~/.bashrc.local ]; then
    . ~/.bashrc.local
fi
