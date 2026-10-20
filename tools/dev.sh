# Development tools. Sourced by install-tools.sh, which provides the helpers.
# shellcheck shell=bash

# Node.js major version from NodeSource
NODE_MAJOR=24

# GitHub CLI
install_gh() {
    add_apt_source github-cli https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        "https://cli.github.com/packages stable main"
    apt_install gh
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

# Rust toolchain installer: rustc, cargo
install_rustup() {
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
}

# Git worktree manager (wt); built from source with cargo
install_worktrunk() {
    ensure rustup
    apt_install build-essential
    cargo install worktrunk
}
installed_worktrunk() { has wt; }

# Go, into /usr/local/go
install_go() {
    local version
    version=$(curl -fsSL 'https://go.dev/VERSION?m=text' | head -n 1)
    enter_tmp
    curl -fsSLO "https://go.dev/dl/$version.linux-$(deb_arch).tar.gz"
    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf "$version.linux-$(deb_arch).tar.gz"
}

# Node.js and npm, from NodeSource
install_node() {
    curl -fsSL "https://deb.nodesource.com/setup_$NODE_MAJOR.x" | sudo -E bash -
    apt_install nodejs
}

# Python 3 with pip and venv
install_python() { apt_install python3 python3-pip python3-venv; }
installed_python() { dpkg -s python3-pip python3-venv >/dev/null 2>&1; }

# Fast Python package and project manager
install_uv() { curl -LsSf https://astral.sh/uv/install.sh | env UV_NO_MODIFY_PATH=1 sh; }

# SDK manager for Java, Maven, Gradle
install_sdkman() {
    apt_install curl zip unzip
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
