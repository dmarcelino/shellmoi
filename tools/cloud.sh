# Cloud and Kubernetes tools. Sourced by install-tools.sh, which provides the helpers.
# shellcheck shell=bash

# Kubernetes CLI
install_kubectl() {
    if is_mac; then brew_install kubernetes-cli; return; fi
    local version
    version=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
    enter_tmp
    curl -fsSLO "https://dl.k8s.io/release/$version/bin/linux/$(deb_arch)/kubectl"
    curl -fsSLO "https://dl.k8s.io/release/$version/bin/linux/$(deb_arch)/kubectl.sha256"
    echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
}

# Kubernetes package manager
install_helm() {
    if is_mac; then brew_install helm; return; fi
    enter_tmp
    curl -fsSLo get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4
    bash get_helm.sh
}

# AWS CLI v2
install_aws() {
    if is_mac; then brew_install awscli; return; fi
    apt_install unzip
    enter_tmp
    curl -fsSLo awscliv2.zip "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip"
    unzip -q awscliv2.zip
    sudo ./aws/install --update
}

# Amazon EKS CLI
install_eksctl() {
    if is_mac; then brew_install eksctl; return; fi
    local platform
    platform="Linux_$(deb_arch)"
    enter_tmp
    curl -fsSLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$platform.tar.gz"
    curl -fsSL https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_checksums.txt |
        grep "$platform" | sha256sum --check
    tar -xzf "eksctl_$platform.tar.gz"
    sudo install -m 0755 eksctl /usr/local/bin
}

# Infrastructure as code
install_terraform() {
    # From HashiCorp's own tap and apt repository: Homebrew core no longer has it
    if is_mac; then brew_install hashicorp/tap/terraform; return; fi
    apt_install gnupg
    add_apt_source hashicorp https://apt.releases.hashicorp.com/gpg \
        "https://apt.releases.hashicorp.com $(os_codename) main"
    apt_install terraform
}
