# AI coding tools. Sourced by install-tools.sh, which provides the helpers.
# shellcheck shell=bash

# Claude Code
install_claude() { curl -fsSL https://claude.ai/install.sh | bash; }

# OpenAI Codex CLI
install_codex() { curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 sh; }

# Code knowledge graph for AI agents
install_codegraph() {
    ensure node
    sudo npm install -g @colbymchenry/codegraph
}

# Spec-driven development for AI agents
install_openspec() {
    ensure node
    sudo npm install -g @fission-ai/openspec@latest
}

# Agent skill: architecture diagrams from a codebase
install_archify() {
    ensure node
    npx -y skills add tt-a1i/archify --skill archify --agent claude-code codex --global --yes
}
installed_archify() { [ -e "$HOME/.claude/skills/archify" ]; }

# Architecture as Markdown in git
install_groma() {
    ensure node
    sudo npm install -g groma.md
}
