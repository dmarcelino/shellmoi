# Tools for any shell. Sourced by install-tools.sh, which provides the helpers.
# shellcheck shell=bash

# Tab completion for commands and their options
install_bash_completion() {
    if is_mac; then brew_install bash-completion@2; return; fi
    apt_install bash-completion
}
installed_bash_completion() {
    if is_mac; then
        [ -s "$(brew --prefix)/etc/profile.d/bash_completion.sh" ]
    else
        [ -f /usr/share/bash-completion/bash_completion ]
    fi
}

# Readable git diffs; git and lazygit config expect it
install_diff_so_fancy() {
    if is_mac; then brew_install diff-so-fancy; return; fi
    ensure node
    npm_global diff-so-fancy
}

# Terminal UI for git
install_lazygit() {
    if is_mac; then brew_install lazygit; return; fi
    local version arch
    version=$(gh_latest jesseduffield/lazygit)
    version=${version#v}
    arch=$(uname -m | sed -e 's/aarch64/arm64/')
    enter_tmp
    curl -fsSLo lazygit.tar.gz \
        "https://github.com/jesseduffield/lazygit/releases/download/v$version/lazygit_${version}_Linux_$arch.tar.gz"
    tar xf lazygit.tar.gz lazygit
    sudo install lazygit -D -t /usr/local/bin/
}

# Fuzzy finder: pick files, branches or past commands by typing part of the name
install_fzf() { pkg_install fzf; }

# Finds files by name; a faster, simpler find
install_fd() {
    if is_mac; then brew_install fd; return; fi
    apt_install fd-find
    link_local fdfind fd
}

# Shows files with syntax colors and line numbers; cat with colors
install_bat() {
    if is_mac; then brew_install bat; return; fi
    apt_install bat
    link_local batcat bat
}

# Searches file contents by pattern; a faster grep that skips ignored files (rg)
install_ripgrep() { pkg_install ripgrep; }
installed_ripgrep() { has rg; }

# Reads, filters and reshapes JSON
install_jq() { pkg_install jq; }

# Terminal multiplexer: split panes, sessions that survive a closed terminal
install_tmux() { pkg_install tmux; }

# Converts line endings between Windows (CRLF) and Unix (LF)
install_dos2unix() { pkg_install dos2unix; }
