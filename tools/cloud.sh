# Cloud and Kubernetes tools. Sourced by install-tools.sh, which provides the helpers.
# shellcheck shell=bash

# Kubernetes CLI
install_kubectl() {
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
    enter_tmp
    curl -fsSLo get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4
    bash get_helm.sh
}

# AWS CLI v2
install_aws() {
    apt_install unzip
    enter_tmp
    curl -fsSLo awscliv2.zip "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip"
    unzip -q awscliv2.zip
    sudo ./aws/install --update
}

# Amazon EKS CLI
install_eksctl() {
    local platform
    platform="Linux_$(deb_arch)"
    enter_tmp
    curl -fsSLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$platform.tar.gz"
    curl -fsSL https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_checksums.txt |
        grep "$platform" | sha256sum --check
    tar -xzf "eksctl_$platform.tar.gz"
    sudo install -m 0755 eksctl /usr/local/bin
}

# Infrastructure as code, from HashiCorp's apt repository
install_terraform() {
    apt_install gnupg
    add_apt_source hashicorp https://apt.releases.hashicorp.com/gpg \
        "https://apt.releases.hashicorp.com $(os_codename) main"
    apt_install terraform
}
