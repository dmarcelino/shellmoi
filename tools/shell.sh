# Tools for any shell. Sourced by install-tools.sh, which provides the helpers.
# shellcheck shell=bash

# Tab completion for commands and their options
install_bash_completion() { apt_install bash-completion; }
installed_bash_completion() { [ -f /usr/share/bash-completion/bash_completion ]; }

# Readable git diffs; git and lazygit config expect it
install_diff_so_fancy() {
    ensure node
    sudo npm install -g diff-so-fancy
}

# Terminal UI for git
install_lazygit() {
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
install_fzf() { apt_install fzf; }

# Finds files by name; a faster, simpler find
install_fd() {
    apt_install fd-find
    link_local fdfind fd
}

# Shows files with syntax colors and line numbers; cat with colors
install_bat() {
    apt_install bat
    link_local batcat bat
}
