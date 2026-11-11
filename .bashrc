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
for dir in /usr/local/go/bin "$HOME/go/bin" "$HOME/.cargo/bin" "$HOME/bin" "$HOME/.local/bin"; do
    if [ -d "$dir" ]; then
        _shellmoi_path_prepend "$dir"
    fi
done
unset dir
_shellmoi_path_dedupe
unset -f _shellmoi_path_prepend _shellmoi_path_dedupe
export PATH

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

# If this is an xterm set the title to user@host: dir
case "$TERM" in
xterm*|rxvt*)
    PS1="\[\e]0;\u@\h: \w\a\]$PS1"
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

# Machine-specific or private settings (secrets, work aliases); never committed
if [ -f ~/.bashrc.local ]; then
    . ~/.bashrc.local
fi
