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
  `CLAUDE.md`, `.gitignore`, `install.sh`, `install-tools.sh`, `tools/` and `tests/`
- moves a file already at a link's place, such as the system's default `~/.bashrc`, to
  `<file>.bak.<timestamp>`
- copies `.claude/settings.json` and `.codex/config.toml` instead of linking them,
  because Claude Code and Codex write to these files. `.codex/config.toml` is copied only
  if it does not exist yet. An existing `.claude/settings.json`, which Claude Code creates
  on first run, gets shellmoi's settings merged in with `jq` once, on the first install:
  settings already there win, including whole lists such as `permissions.allow`, and the
  original is kept in `~/.local/state/shellmoi/`. Later runs leave the file alone, so a
  setting you remove stays removed. Without `jq` it is left alone, and the script prints
  a `diff` command to compare
- links each skill directory on its own (see [Skills](#skills)), so other skills already
  in `~/.claude/skills` and `~/.codex/skills` stay
- prints the command to install bash-completion if it is missing (see below), and on
  macOS the commands to make Homebrew's Bash the login shell if it is not; it never runs
  `sudo`
- lists files of the clone with local changes: the files in `~` are links into it, so an
  installer that appends to `~/.bashrc` edits this public repository. Move such lines to
  `~/.bashrc.local`

Run the same command again, or `~/.local/share/shellmoi/install.sh`, to update. Files
that are already linked are left alone.

Set `SHELLMOI_DIR` to use another clone location, for example an existing working copy,
and `SHELLMOI_REPO` to clone from a fork.

The clone uses HTTPS, which needs no SSH key. To push from it, switch to SSH:

```bash
git -C ~/.local/share/shellmoi remote set-url origin git@github.com:dmarcelino/shellmoi.git
```

## Uninstall

```bash
~/.local/share/shellmoi/install.sh uninstall
```

It undoes the install:

- removes every link into the clone and moves back the oldest `<file>.bak.<timestamp>`,
  which holds what was there before the first install; newer backups stay, and are listed
- leaves alone a file that is no longer a link into the clone
- removes `.claude/settings.json`, `.codex/config.toml` and `~/.gitconfig` only if they
  are still exactly what the install wrote
- puts back the `.claude/settings.json` from before the merge; the merged one is removed
  if unchanged, else kept as `settings.json.bak.<timestamp>`
- removes directories left empty

The clone stays; delete it if you no longer need it. Run `tests/uninstall_test.sh` to
check an install and uninstall round trip in a temporary home.

## Tools

`install-tools.sh` installs common tools on Debian, Ubuntu and macOS (with Homebrew); it
needs Bash 4.3 or later. On macOS, started by the system's Bash 3.2, it starts again under
Homebrew's Bash, and offers to install it if it is missing. Give it one or more tool
files, by path or by name; it shows a checklist of their tools and installs the ticked
ones:

```bash
~/.local/share/shellmoi/install-tools.sh ai dev
```

On a new machine, `all` goes through every tool file, one checklist each:

```bash
~/.local/share/shellmoi/install-tools.sh all
```

| File             | Tools                                                                                                            |
| ---------------- | ---------------------------------------------------------------------------------------------------------------- |
| `tools/shell.sh` | bash (macOS), bash-completion, diff-so-fancy, lazygit, fzf, fd, bat, ripgrep, jq, tmux, dos2unix                 |
| `tools/dev.sh`   | gh, git-lfs, shellcheck, gitleaks, docker-ce, colima, rustup, worktrunk, go, node, python, uv, sdkman, java, mvn |
| `tools/cloud.sh` | kubectl, helm, aws, eksctl, terraform                                                                            |
| `tools/ai.sh`    | claude, codex, codegraph, openspec, archify, groma, impeccable                                                   |

On macOS most tools come from Homebrew, and nothing needs `sudo`. Docker runs in a
[Colima](https://github.com/abiosoft/colima) VM that starts at login: the checklist shows
colima on macOS and docker-ce on Linux. Terraform comes from HashiCorp's own tap, as
Homebrew core no longer has it.

Run it as your own user, not with `sudo`: many tools install into your home directory.
Steps that need root call `sudo` themselves, and the password is asked once. A tool
installs what it needs first, even from another file: codegraph and groma bring in node,
worktrunk brings in rustup on Linux. Missing tools start ticked, and `a` cycles between missing,
all and none. After the checklist, the installs run without further questions, including
Homebrew's confirmation before installing dependencies. Installed tools are marked in the
checklist; tick one to install it again or update it. No installer edits `~/.bashrc`: it already sets up `PATH`
and the tools that need it.

To add a tool, add a function to a tool file, with a description line above it:

```bash
# Short description for the checklist
install_mytool() { pkg_install mytool; }
installed_mytool() { [ -d "$HOME/.mytool" ]; }  # optional; default: command -v mytool
supported_mytool() { ! is_mac; }                # optional; false hides it on this system
```

`pkg_install` uses apt on Linux and Homebrew on macOS, for packages with the same name in
both. Otherwise start the function with `if is_mac; then brew_install <formula>; return; fi`.
Hyphens in a tool name become underscores in the function name (`install_docker_ce`).
`install-tools.sh` provides the helpers: `ensure <tool>` for dependencies, `is_mac`,
`pkg_install`, `apt_install`, `brew_install`, `npm_global`, `add_apt_source`,
`gh_latest`, `deb_arch`, `os_codename`, `enter_tmp` and `link_local`.

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

macOS ships Bash 3.2, which is too old for both projects, hence the Homebrew `bash`
(also in `install-tools.sh shell`). Make it your login shell:

```bash
echo "$(brew --prefix)/bin/bash" | sudo tee -a /etc/shells
chsh -s "$(brew --prefix)/bin/bash"
```

macOS terminals start login shells, which read `~/.bash_profile` rather than `~/.bashrc`.
The install script links this repository's `.bash_profile`, which loads `~/.profile`
and then `~/.bashrc`.

### 2. The repository's `.bashrc`

The install script links `~/.bashrc` to this repository's `.bashrc`, which loads
bash-completion (from the system or Homebrew), then bash-sensible, then `.bash_aliases`.
It also sets the prompt to `user@host:folder(branch)$`, and sets up kubectl, nvm, fzf's
key bindings (Ctrl-R history, Ctrl-T files, Alt-C folders), worktrunk and SDKMAN when they
are installed. With Apple's git, it loads git's completion from the Command Line Tools,
where bash-completion does not look.

`PATH` comes first, before the check that stops non-interactive shells, so `bash -lc`
from an IDE or an agent finds the same commands on `PATH`: Homebrew, then `~/bin`,
`~/.local/bin`, Cargo's and Go's bin directories, with `~/.local/bin` first and repeated
entries removed. On macOS this also puts Homebrew's Bash before `/bin/bash`, which
`path_helper` lists first in login shells. What a shell function provides, such as nvm's
and SDKMAN's versions of node and java, still needs an interactive shell. Debian's
`~/.profile` adds `~/bin` and `~/.local/bin` again after `.bashrc` runs, so a login shell
there can list them twice.

A command run over SSH, such as `ssh mac-box claude`, starts a non-interactive shell that
reads none of these files on macOS, so `PATH` is the system's. Run it in a login shell
instead: `ssh mac-box bash -lc claude`.

Open a new shell and check bash-completion loaded: `echo "${BASH_COMPLETION_VERSINFO[@]}"`
prints a version.

### 3. Keep private settings local

Put secrets, work-specific aliases and anything else machine-specific in `~/.bashrc.local`.
`.bashrc` sources it last, and git ignores it.

### 4. History search with the arrow keys

Type the start of a command, then press Up or Down to step through the history entries
that start with it. bash-sensible sets this for Bash, and `.inputrc` sets it for every
other program that uses Readline, such as `python` and `psql`. `.inputrc` first includes
`/etc/inputrc`, where Debian keeps its Home, End and Ctrl+arrow keys.

## Git

`.config/git/config` holds the shared settings: Git LFS, `push.autoSetupRemote`, and
[diff-so-fancy](https://github.com/so-fancy/diff-so-fancy) as the pager when it is
installed. `.config/git/ignore` is the global ignore file, and
`.config/lazygit/config.yml` makes lazygit show diffs with diff-so-fancy too.

Keep `user.name`, `user.email` and credential helpers in `~/.gitconfig`, which is not
tracked. Git reads it after `.config/git/config`, and `git config --global` writes to it.
The install script creates an empty one if it is missing: without it,
`git config --global` would write to `.config/git/config` in this repository.

## WezTerm

`.config/wezterm/wezterm.lua` shows the folder in tab titles and uses a slim window frame.
Hosts and usernames stay in `~/.config/wezterm/wezterm_private.lua`, which git ignores;
copy `wezterm_private.example.lua` to start one. With it, WezTerm offers its SSH domains
and opens the default one on launch; without it, WezTerm opens a local shell. Ctrl+Alt+V
pastes a clipboard image to the SSH host of the pane, on Windows only.

## Skills

Skills for Claude Code and Codex, which read the same format. The repository keeps one
copy in `.codex/skills`; `.claude/skills` is a link to it. All are invoked explicitly:
`/<name>` in Claude Code, `$<name>` in Codex.

| Skill           | What it does                                                        |
| --------------- | ------------------------------------------------------------------- |
| `ask`           | Answers a question from the codebase and the web; changes nothing   |
| `brainstorm`    | A multi-turn thinking partner: frame, explore, generate, challenge  |
| `plainly`       | Explains something, or the previous answer, in simple words         |
| `owl`           | Slow, multi-perspective analysis of a problem, question or decision |
| `tdd`           | Test first: failing test, smallest fix, then passing test           |
| `diagnose`      | Finds a root cause from evidence; asks for 3 checks before guessing |
| `gaps`          | Finds gaps, contradictions and ambiguity in a request; asks first   |
| `design-review` | Design review of a PR, branch or local work; edits nothing          |

The install script links `~/.claude/skills/<name>` and `~/.codex/skills/<name>` to each
skill. A skill already at that place is moved to `~/.claude/skills.bak.<timestamp>/` or
`~/.codex/skills.bak.<timestamp>/`, outside the skills folder, so it does not load twice.
