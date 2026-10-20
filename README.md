# shellmoi

Configuration for a bash shell: opinionated defaults, used across different machines.

The repository root mirrors the home directory: a file at `.config/foo` here belongs at
`~/.config/foo`.

## Install

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/dmarcelino/shellmoi/main/install.sh)"
```

The script needs `git`; if it is missing, the script prints the command to install it. It:

- clones this repository into `~/.local/share/shellmoi`, or pulls it if it is already there
- links every tracked file into `~`, except this README, `LICENSE`, `AGENTS.md`,
  `CLAUDE.md`, `.gitignore`, `install.sh`, `install-tools.sh` and `tools/`
- moves a file already at a link's place, such as the system's default `~/.bashrc`, to
  `<file>.bak.<timestamp>`
- copies `.claude/settings.json` and `.codex/config.toml` instead of linking them, and
  only if they do not exist yet, because Claude Code and Codex write to these files
- links each skill directory on its own (see [Skills](#skills)), so other skills already
  in `~/.claude/skills` and `~/.codex/skills` stay
- prints the command to install bash-completion if it is missing (see below); it never
  runs `sudo`

Run the same command again, or `~/.local/share/shellmoi/install.sh`, to update. Files
that are already linked are left alone.

Set `SHELLMOI_DIR` to use another clone location, for example an existing working copy,
and `SHELLMOI_REPO` to clone from a fork.

The clone uses HTTPS, which needs no SSH key. To push from it, switch to SSH:

```bash
git -C ~/.local/share/shellmoi remote set-url origin git@github.com:dmarcelino/shellmoi.git
```

## Tools

`install-tools.sh` installs common tools on Debian and Ubuntu. Give it one or more tool
files, by path or by name; it shows a checklist of their tools and installs the ticked
ones:

```bash
~/.local/share/shellmoi/install-tools.sh ai dev
```

| File             | Tools                                                                                                    |
| ---------------- | -------------------------------------------------------------------------------------------------------- |
| `tools/shell.sh` | bash-completion, diff-so-fancy, lazygit, fzf, fd, bat, ripgrep, jq, tmux, dos2unix                       |
| `tools/dev.sh`   | gh, git-lfs, shellcheck, gitleaks, docker-ce, rustup, worktrunk, go, node, python, uv, sdkman, java, mvn |
| `tools/cloud.sh` | kubectl, helm, aws, eksctl, terraform                                                                    |
| `tools/ai.sh`    | claude, codex, codegraph, openspec, archify, groma                                                       |

Run it as your own user, not with `sudo`: many tools install into your home directory.
Steps that need root call `sudo` themselves, and the password is asked once. A tool
installs what it needs first, even from another file: codegraph and groma bring in node,
worktrunk brings in rustup. Missing tools start ticked, and `a` cycles between missing,
all and none. Installed tools are marked in the checklist; tick one to install it again
or update it. No installer edits `~/.bashrc`: it already sets up `PATH`
and the tools that need it.

To add a tool, add a function to a tool file, with a description line above it:

```bash
# Short description for the checklist
install_mytool() { apt_install mytool; }
installed_mytool() { [ -d "$HOME/.mytool" ]; }  # optional; default: command -v mytool
```

Hyphens in a tool name become underscores in the function name (`install_docker_ce`).
`install-tools.sh` provides the helpers: `ensure <tool>` for dependencies,
`apt_install`, `add_apt_source`, `gh_latest`, `deb_arch`, `os_codename`, `enter_tmp` and
`link_local`.

## Bash

[bash-sensible](https://github.com/mrzool/bash-sensible) provides saner Bash defaults:
history, tab completion and directory navigation. It lives in
`.config/bash/sensible/sensible.bash` and needs Bash 4 or later (`echo $BASH_VERSION`).

### 1. Install bash-completion

bash-sensible depends on [bash-completion](https://github.com/scop/bash-completion).
Install it with your package manager:

| System        | Command                                  |
| ------------- | ---------------------------------------- |
| Debian/Ubuntu | `sudo apt install bash-completion`       |
| Fedora        | `sudo dnf install bash-completion`       |
| Arch Linux    | `sudo pacman -S bash-completion`         |
| macOS         | `brew install bash bash-completion@2`    |

For other systems, see the [package list on Repology](https://repology.org/project/bash-completion).

macOS ships Bash 3.2, which is too old for both projects, hence the Homebrew `bash`. Make
it your login shell with `chsh`, and source `~/.bashrc` from `~/.bash_profile`:

```bash
# ~/.bash_profile
if [[ -f ~/.bashrc ]]; then
  source ~/.bashrc
fi
```

### 2. The repository's `.bashrc`

The install script links `~/.bashrc` to this repository's `.bashrc`, which loads
bash-completion (from the system or Homebrew), then bash-sensible, then `.bash_aliases`.
It also sets the prompt to `user@host:folder(branch)$`, adds `~/bin`, `~/.local/bin`,
Cargo's and Go's bin directories to `PATH`, and sets up kubectl, nvm, worktrunk and SDKMAN
when they are installed.

Open a new shell and check bash-completion loaded: `echo "${BASH_COMPLETION_VERSINFO[@]}"`
prints a version.

### 3. Keep private settings local

Put secrets, work-specific aliases and anything else machine-specific in `~/.bashrc.local`.
`.bashrc` sources it last, and git ignores it.

### 4. History search with the arrow keys

Type the start of a command, then press Up or Down to step through the history entries
that start with it. bash-sensible sets this for Bash, and `.inputrc` sets it for every
other program that uses Readline, such as `python` and `psql`.

## Git

`.config/git/config` holds the shared settings: Git LFS, `push.autoSetupRemote`, and
[diff-so-fancy](https://github.com/so-fancy/diff-so-fancy) as the pager when it is
installed. `.config/git/ignore` is the global ignore file, and
`.config/lazygit/config.yml` makes lazygit show diffs with diff-so-fancy too.

Keep `user.name`, `user.email` and credential helpers in `~/.gitconfig`, which is not
tracked. Git reads it after `.config/git/config`, and `git config --global` writes to it.
The install script creates an empty one if it is missing: without it,
`git config --global` would write to `.config/git/config` in this repository.

## Skills

Skills for Claude Code and Codex, which read the same format. The repository keeps one
copy in `.codex/skills`; `.claude/skills` is a link to it. All are invoked explicitly:
`/<name>` in Claude Code, `$<name>` in Codex.

| Skill        | What it does                                                        |
| ------------ | ------------------------------------------------------------------- |
| `ask`        | Answers a question from the codebase and the web; changes nothing   |
| `brainstorm` | A multi-turn thinking partner: frame, explore, generate, challenge  |
| `plainly`    | Explains something, or the previous answer, in simple words         |
| `owl`        | Slow, multi-perspective analysis of a problem, question or decision |

The install script links `~/.claude/skills/<name>` and `~/.codex/skills/<name>` to each
skill. A skill already at that place is moved to `~/.claude/skills.bak.<timestamp>/` or
`~/.codex/skills.bak.<timestamp>/`, outside the skills folder, so it does not load twice.
