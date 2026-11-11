# Development tools. Sourced by install-tools.sh, which provides the helpers.
# shellcheck shell=bash

# Node.js major version from NodeSource
NODE_MAJOR=24

# GitHub CLI
install_gh() {
    if is_mac; then brew_install gh; return; fi
    add_apt_source github-cli https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        "https://cli.github.com/packages stable main"
    apt_install gh
}

# Large file storage for git; the git config expects it
install_git_lfs() { pkg_install git-lfs; }

# Finds bugs in shell scripts
install_shellcheck() { pkg_install shellcheck; }

# Finds secrets in git history and files
install_gitleaks() {
    # On Linux from GitHub, as the apt package lags far behind
    if is_mac; then brew_install gitleaks; return; fi
    local version arch
    version=$(gh_latest gitleaks/gitleaks)
    version=${version#v}
    arch=$(deb_arch | sed -e 's/amd64/x64/')
    enter_tmp
    curl -fsSLo gitleaks.tar.gz \
        "https://github.com/gitleaks/gitleaks/releases/download/v$version/gitleaks_${version}_linux_$arch.tar.gz"
    tar xf gitleaks.tar.gz gitleaks
    sudo install gitleaks -D -t /usr/local/bin/
}

# Docker Engine, with the buildx and compose plugins
install_docker_ce() {
    local distro
    distro=$(. /etc/os-release && echo "$ID")
    add_apt_source docker "https://download.docker.com/linux/$distro/gpg" \
        "https://download.docker.com/linux/$distro $(os_codename) stable"
    apt_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo usermod -aG docker "$USER"
}
installed_docker_ce() { has docker; }
supported_docker_ce() { ! is_mac; }

# Docker on macOS: the docker CLI with Compose and Buildx, in a Colima VM started at login
install_colima() {
    brew_install colima docker docker-compose docker-buildx
    docker_plugin_dirs
    brew services start colima
}
supported_colima() { is_mac; }

# Lets docker find the Compose and Buildx plugins Homebrew installs
docker_plugin_dirs() {
    local config="$HOME/.docker/config.json" dir
    dir="$(brew --prefix)/lib/docker/cli-plugins"
    mkdir -p "$HOME/.docker"
    if [ ! -s "$config" ]; then
        printf '{\n  "cliPluginsExtraDirs": ["%s"]\n}\n' "$dir" > "$config"
        return
    fi
    ensure jq
    jq --arg dir "$dir" '.cliPluginsExtraDirs = ((.cliPluginsExtraDirs // []) - [$dir] + [$dir])' \
        "$config" > "$config.new"
    mv "$config.new" "$config"
}

# Rust toolchain installer: rustc, cargo
install_rustup() {
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
}

# Git worktree manager (wt)
install_worktrunk() {
    # Not `wt config shell install`: ~/.bashrc already loads the shell integration
    if is_mac; then brew_install worktrunk; return; fi
    ensure rustup
    apt_install build-essential
    cargo install worktrunk
}
installed_worktrunk() { has wt; }

# Go
install_go() {
    if is_mac; then brew_install go; return; fi
    local version
    version=$(curl -fsSL 'https://go.dev/VERSION?m=text' | head -n 1)
    enter_tmp
    curl -fsSLO "https://go.dev/dl/$version.linux-$(deb_arch).tar.gz"
    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf "$version.linux-$(deb_arch).tar.gz"
}

# Node.js and npm
install_node() {
    if is_mac; then
        # Versioned formulae are keg-only: link it so node and npm are on PATH
        brew_install "node@$NODE_MAJOR"
        brew link --force "node@$NODE_MAJOR"
        return
    fi
    curl -fsSL "https://deb.nodesource.com/setup_$NODE_MAJOR.x" | sudo -E bash -
    apt_install nodejs
}

# Python 3 with pip and venv
install_python() {
    if is_mac; then brew_install python; return; fi
    apt_install python3 python3-pip python3-venv
}
installed_python() {
    if is_mac; then
        # Not /usr/bin/python3: that is the Xcode Command Line Tools stub
        [ -x "$(brew --prefix)/bin/python3" ]
    else
        dpkg -s python3-pip python3-venv >/dev/null 2>&1
    fi
}

# Fast Python package and project manager
install_uv() {
    if is_mac; then brew_install uv; return; fi
    curl -LsSf https://astral.sh/uv/install.sh | env UV_NO_MODIFY_PATH=1 sh
}

# SDK manager for Java, Maven, Gradle
install_sdkman() {
    # macOS ships curl, zip and unzip
    is_mac || apt_install curl zip unzip
    # rcupdate=false: ~/.bashrc already loads SDKMAN
    curl -fsSL "https://get.sdkman.io?rcupdate=false" | bash
}
installed_sdkman() { [ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]; }

# Runs sdk without prompts; SDKMAN's own code does not support set -eu
sdk_install() {
    (
        set +eu
        # shellcheck source=/dev/null
        . "$HOME/.sdkman/bin/sdkman-init.sh"
        sdkman_auto_answer=true sdk install "$1"
    )
}

# Java (SDKMAN's default JDK)
install_java() {
    ensure sdkman
    sdk_install java
}
installed_java() { [ -d "$HOME/.sdkman/candidates/java/current" ]; }

# Maven, through SDKMAN
install_mvn() {
    ensure java
    sdk_install maven
}
installed_mvn() { [ -d "$HOME/.sdkman/candidates/maven/current" ]; }
