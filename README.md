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
- links every tracked file into `~`, except this README, `AGENTS.md`, `CLAUDE.md`,
  `.gitignore` and `install.sh`
- moves a file already at a link's place, such as the system's default `~/.bashrc`, to
  `<file>.bak.<timestamp>`
- copies `.claude/settings.json` and `.codex/config.toml` instead of linking them, and
  only if they do not exist yet, because Claude Code and Codex write to these files
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
It also sets the prompt to `user@host:folder(branch)$`, adds `~/bin` and `~/.local/bin`
to `PATH`, and sets up kubectl, nvm, worktrunk and SDKMAN when they are installed.

Open a new shell and check bash-completion loaded: `echo "${BASH_COMPLETION_VERSINFO[@]}"`
prints a version.

### 3. Keep private settings local

Put secrets, work-specific aliases and anything else machine-specific in `~/.bashrc.local`.
`.bashrc` sources it last, and git ignores it.
