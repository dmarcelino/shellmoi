# ~/.bashrc: executed by bash(1) for interactive non-login shells.

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

## PATH ##

# Tool and private bin directories, if they exist; ~/.local/bin ends up first
for dir in /usr/local/go/bin "$HOME/go/bin" "$HOME/.cargo/bin" "$HOME/bin" "$HOME/.local/bin"; do
    if [ -d "$dir" ] && [[ ":$PATH:" != *":$dir:"* ]]; then
        PATH="$dir:$PATH"
    fi
done
unset dir

# Homebrew (macOS or Linux), if installed
for brew in /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew; do
    if [ -x "$brew" ]; then
        eval "$("$brew" shellenv bash)"
        break
    fi
done
unset brew

## DEFAULTS ##

# bash-completion, if available; the guard avoids loading it twice
if ! shopt -oq posix && [ -z "${BASH_COMPLETION_VERSINFO:-}" ]; then
    if [ -f /usr/share/bash-completion/bash_completion ]; then
        . /usr/share/bash-completion/bash_completion
    elif [ -s "${HOMEBREW_PREFIX:-}/etc/profile.d/bash_completion.sh" ]; then
        . "$HOMEBREW_PREFIX/etc/profile.d/bash_completion.sh"
    fi
fi

# Saner history, tab completion and directory navigation
if [ -f ~/.config/bash/sensible/sensible.bash ]; then
    . ~/.config/bash/sensible/sensible.bash
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
