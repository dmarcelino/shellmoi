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
  `CLAUDE.md`, `.gitignore`, `install.sh`, `install-tools.sh`, `push.sh`, `pull.sh`,
  `lib/`, `tools/` and `tests/`
- links the files of the [private profiles](#private-profiles) in the clone's `private/`
  folder, if there are any, and prints the `sudo` commands to copy their
  [system files](#system-files) into `/`
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
- removes `.claude/settings.json`, `.codex/config.toml`, `~/.gitconfig` and
  `~/.ssh/config` only if they are still exactly what the install wrote, and
  `~/.config/git/profiles.gitconfig`, which the install generates
- puts back the `.claude/settings.json` from before the merge; the merged one is removed
  if unchanged, else kept as `settings.json.bak.<timestamp>`
- removes directories left empty
- prints the `sudo rm` commands for the profiles' [system files](#system-files) that are
  still in place, unchanged

The clone stays; delete it if you no longer need it, but not before moving your private
profiles out of it. Run `tests/uninstall_test.sh` to check an install and uninstall round
trip in a temporary home.

## Private profiles

Private settings, such as work aliases, SSH hosts and git identities, can't go in this
public repository. They go in profiles: folders in the clone's `private/` folder, which git
ignores. Each profile is laid out like `~`, as this repository is, and `install.sh` links
its files into `~` the same way, with the same backups and uninstall:

```text
~/.local/share/shellmoi/private/
  personal/.bashrc.d/personal.sh
  personal/.config/git/profiles/personal.gitconfig
  work/.bashrc.d/work.sh
  work/.ssh/config.d/work.conf
  work/.config/git/profiles/work.gitconfig
  work/.config/git/profiles/work-identity.inc
  work/.system/etc/resolver/corp.example
```

A machine can have several profiles, so each one only adds files named after itself, in
folders that shellmoi loads:

| Profile file                                 | Loaded by                                                    |
| -------------------------------------------- | ------------------------------------------------------------ |
| `~/.bashrc.d/<profile>.sh`                   | `.bashrc`, before `~/.bashrc.local`                          |
| `~/.ssh/config.d/<profile>.conf`             | `~/.ssh/config`, through `Include config.d/*.conf`           |
| `~/.config/git/profiles/<profile>.gitconfig` | `~/.config/git/profiles.gitconfig`, which the install writes |

- **SSH:** without a `~/.ssh/config`, the install creates one holding only the `Include`.
  It never edits one that is there; it prints the line to add at its top instead.
- **git:** the shared git config includes the generated `profiles.gitconfig` last, so the
  profiles' settings win over the shared ones. An identity for one folder goes in an
  `includeIf`, with the included file named other than `*.gitconfig`:

  ```ini
  [includeIf "gitdir:~/work/"]
  	path = work-identity.inc
  ```

  `~/.gitconfig` is read after all of them, so take `user.email` out of it.
- **Two profiles, one file:** if two profiles have the same file, the first by name wins,
  and the install says so. A profile file at a path shellmoi links itself, such as
  `.bashrc`, is skipped too.
- **Removed or renamed:** the install records what it linked, in
  `~/.local/state/shellmoi/`. A file deleted from a profile, or a profile renamed, has its
  old link removed by the next install, and uninstall removes them all.
- **Not linked:** Finder's `.DS_Store` and editor leftovers (`*~`, `.*.swp`).

### System files

A profile's `.system/` folder is laid out like `/` rather than `~`: for files that belong
to the system, such as `/etc/resolver/corp.example`, which sends a domain's DNS lookups to
its own servers while another VPN, such as Tailscale, handles the rest. The install never
links them, as a link to a file you can edit would let any program running as you change
the system's settings, and never runs `sudo`. It compares each file with the system's and
prints the commands that copy the missing or different ones, owned by root, mode 644:

```text
System files in the private profiles differ from the system's. To install them:
    sudo install -d -m 755 /etc/resolver
    sudo install -m 644 ~/.local/share/shellmoi/private/work/.system/etc/resolver/corp.example /etc/resolver/corp.example
```

- **Two profiles, one file:** the first by name wins, as for the links.
- **Uninstall** prints `sudo rm` for each file still the same as the profile's.
- **Removed from a profile:** the copy stays on the system; remove it with `sudo rm`.
- **Other machines:** `push.sh` copies `.system/` with the rest of the profile, and the
  install there prints the commands for that machine: `push.sh --install`, or
  `install.sh` run there.

Make `private/` a git repository of its own, never pushed anywhere: it keeps the history,
and `git clean` in the clone leaves a nested repository alone.

```bash
git -C ~/.local/share/shellmoi/private init
```

The profiles live in the clone: **deleting the clone deletes them.** Keep a copy on
another machine with `push.sh`.

### Copy profiles to another machine

`push.sh` copies the given profiles over SSH into another machine's clone, and changes
nothing else there. It lists the files it updated and added.

```bash
~/.local/share/shellmoi/push.sh <host> work personal
~/.local/share/shellmoi/push.sh <host> --all              # every profile in private/
~/.local/share/shellmoi/push.sh <host> --install --all    # set up the machine too
```

- **Copy only:** the other machine needs a clone of shellmoi already. A changed file that
  is linked takes effect at once. A new file, one not linked yet, or a changed
  [system file](#system-files) needs `install.sh` there: `push.sh` says so and prints the
  command.
- **`--install`:** first installs shellmoi on the other machine, or updates it, then
  copies, then runs `install.sh` there to link the profiles. With no profiles, it only
  sets up shellmoi.
- **SSH first:** the other machine must accept SSH. On macOS, turn on Remote Login; on
  WSL, install and start `openssh-server`. SSH keys are not copied: make a new one there.
- **rsync:** copies the profiles. It uses the first rsync 3 or later on `PATH` on each
  machine: on macOS, Homebrew's, as the system's is older. Without one, it stops. With
  `--install`, `push.sh` installs it on both machines when it is missing, through
  `install-tools.sh --ensure rsync`, and on the other machine asks for the sudo password
  if needed.
- **Nothing is deleted:** a file on the other machine whose content the copy changes is
  kept in `private/.backups/<time>/` first. A file removed from a profile here stays there.
- **Secrets:** before copying, `push.sh` lists the lines that name something like a
  secret, by file, line and the word found, never the value: the words in `HISTIGNORE`,
  in any case, and `PRIVATE KEY`.

Edit the profiles on one machine and push from there. To bring back a change made on
another machine, pull it.

### Copy profiles back

`pull.sh` is the reverse: it copies the given profiles from another machine's clone into
this one's `private/`, and changes nothing else, here or there.

```bash
~/.local/share/shellmoi/pull.sh <host> work
~/.local/share/shellmoi/pull.sh <host> --all              # every profile on <host>
~/.local/share/shellmoi/pull.sh <host> --install --all    # and link what is new
```

- **The other machine's copy wins:** a file whose content differs is replaced by the other
  machine's, even when this machine's is newer. The replaced file is kept in
  `private/.backups/<time>/` first. A file only here stays.
- **Review with git:** commit in `private/` before pulling. Afterwards, `pull.sh` lists
  the files it updated and added, and prints the `git diff` that shows the changes, or,
  before the first commit, a `diff` against the backups. It warns when a profile has
  changes not committed, as the diff would mix them with the pull's.
- **Linking:** when files were added or are not linked yet, or a
  [system file](#system-files) changed, it prints the `install.sh` command, which links
  them or prints the `sudo` commands. With `--install`, it runs it, which also updates the
  clone.
- **Errors:** if a profile cannot be copied in full, or the install fails, `pull.sh` still
  copies the other profiles and lists what changed, then exits with an error.
- **rsync:** as for `push.sh`, but `--install` installs rsync only here. It never changes
  the other machine.

`tests/private_test.sh`, `tests/push_test.sh` and `tests/pull_test.sh` check this, the last
two against a fake home with an `ssh` stand-in.

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

| File             | Tools                                                                                                                 |
| ---------------- | --------------------------------------------------------------------------------------------------------------------- |
| `tools/shell.sh` | bash (macOS), bash-completion, diff-so-fancy, lazygit, fzf, fd, bat, ripgrep, jq, tmux, dos2unix, rsync               |
| `tools/dev.sh`   | gh, git-lfs, shellcheck, gitleaks, docker-ce, colima, rustup, worktrunk, go, node, bun, python, uv, sdkman, java, mvn |
| `tools/cloud.sh` | kubectl, helm, aws, eksctl, terraform                                                                                 |
| `tools/ai.sh`    | claude, codex, codex-auth, codegraph, openspec, archify, groma, impeccable                                            |

On macOS most tools come from Homebrew, and nothing needs `sudo`. Docker runs in a
[Colima](https://github.com/abiosoft/colima) VM that starts at login: the checklist shows
colima on macOS and docker-ce on Linux. Terraform comes from HashiCorp's own tap, as
Homebrew core no longer has it.

Run it as your own user, not with `sudo`: many tools install into your home directory.
Steps that need root call `sudo` themselves, and the password is asked once. A tool
installs what it needs first, even from another file: codegraph and groma bring in node,
worktrunk brings in rustup on Linux. Missing tools start ticked, and `a` cycles between missing,
all and none. After the checklist, nothing else asks, not even Homebrew before installing
dependencies; on Linux, sudo asks for the password once, right after the checklist.
Installed tools are marked in the checklist; tick one to install it again or update it. No
installer edits `~/.bashrc`: it already sets up `PATH` and the tools that need it.

Scripts can install tools without the checklist: `--ensure` installs the named tools that
are missing and does nothing for the others; sudo asks for the password only if one is
missing.

```bash
~/.local/share/shellmoi/install-tools.sh --ensure rsync
```

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

The terminal title shows the full path, starting from `~` inside the home folder:
`user@host: path` in xterm, and inside tmux the path alone, as the pane title; tmux passes
it on to the terminal's tab only with `set -g set-titles on` and
`set -g set-titles-string '#T'` in `~/.tmux.conf`. Inside tmux, `claude` also runs without `TMUX` and `TMUX_PANE`, so Claude Code shows in the title when
it is working or done, which it does only outside tmux. Claude, and the commands it runs,
then don't know they are inside tmux. `wsc` starts claude through worktrunk, so it keeps
the default.

The title starts with two invisible marks, right-to-left (U+200F) then left-to-right
(U+200E), and ends with a left-to-right one. They let a tab cut a long path at the start,
`…ojects/app/backup`, while other titles, such as Claude Code's, are still cut at the end.
In Tabby, add this under Settings → Appearance → Custom CSS:

```css
tab-header .name { unicode-bidi: plaintext; text-align: left; }
```

`PATH` comes first, before the check that stops non-interactive shells, so `bash -lc`
from an IDE or an agent finds the same commands on `PATH`: Homebrew, then `~/bin`,
`~/.local/bin`, Cargo's, Go's and Bun's bin directories, with `~/.local/bin` first and
repeated entries removed. On macOS this also puts Homebrew's Bash before `/bin/bash`, which
`path_helper` lists first in login shells. What a shell function provides, such as nvm's
and SDKMAN's versions of node and java, still needs an interactive shell. Debian's
`~/.profile` adds `~/bin` and `~/.local/bin` again after `.bashrc` runs, so a login shell
there can list them twice.

The locale is set there too, but only when none is: SSH from Windows sends no `LANG`, and
in the C locale tmux draws every non-ASCII character as `_`. Such a session gets
`en_US.UTF-8`, or `C.UTF-8` on a host without it; a terminal that sends its own locale
keeps it. A tmux server started before keeps the C locale until `tmux kill-server`.
`tests/locale_test.sh` checks this.

A command run over SSH, such as `ssh mac-box claude`, starts a non-interactive shell that
reads none of these files on macOS, so `PATH` is the system's. Run it in a login shell
instead: `ssh mac-box bash -lc claude`.

Over SSH, `code [folder]` prints a link instead of starting VS Code, like `code .` from
WSL: `vscode://vscode-remote/ssh-remote+user@address/path/to/folder`. Click it, or
Ctrl-click, depending on the terminal, to open the folder in the VS Code of the machine you
connect from, through its Remote-SSH extension. Tabby asks once per click before it opens
a `vscode://` link. VS Code makes its own SSH connection, so it needs a key or a password
of its own. The link names the user and the address the SSH connection reached this
machine at, from `SSH_CONNECTION`; inside tmux, panes keep the one from when they started.
Set `SHELLMOI_CODE_HOST`, in `~/.bashrc.local`, to a `Host` from the other machine's
`~/.ssh/config` when that address doesn't work from there, such as behind a jump host.
Locally, and in VS Code's own terminal, `code` is the real one. A folder whose path has
characters other than letters, digits, `.`, `-`, `_`, `~`, `+` and spaces may not become a
clickable link. `tests/code_test.sh` checks this.

`.bashrc` exports `SHELLMOI_DIR`, the path of the clone, which it finds by following the
`~/.bashrc` link, relative links and chains of them included. bash-sensible turns on
`cdable_vars`, so `cd SHELLMOI_DIR` goes to the clone from any folder; `install.sh` and
`push.sh` use it too. A copy of `.bashrc` that is not in a clone leaves it unset.
`tests/shellmoi_dir_test.sh` checks this.

Open a new shell and check bash-completion loaded: `echo "${BASH_COMPLETION_VERSINFO[@]}"`
prints a version.

### 3. Keep private settings local

Put secrets, work-specific aliases and anything else machine-specific in `~/.bashrc.local`.
`.bashrc` sources it last, and git ignores it. Settings you want on several machines go in
a [private profile](#private-profiles) instead: `.bashrc` sources every
`~/.bashrc.d/*.sh` just before `~/.bashrc.local`.

### 4. Secrets stay out of the history

`.bashrc` adds patterns to `HISTIGNORE`, so a command that names a secret in upper case,
such as `export AWS_SECRET_ACCESS_KEY=...` or `GITHUB_TOKEN=... gh api`, is neither saved
nor recalled with Up. The patterns are `SECRET`, `TOKEN`, `PASSWORD`, `PASSWD`, `_KEY`,
`APIKEY`, `JWT` and `CREDENTIAL` anywhere in the line, so `git commit -m "Fix TOKEN
refresh"` is left out too. `tests/history_test.sh` checks this.

### 5. History search with the arrow keys

Type the start of a command, then press Up or Down to step through the history entries
that start with it. bash-sensible sets this for Bash, and `.inputrc` sets it for every
other program that uses Readline, such as `python` and `psql`. `.inputrc` first includes
`/etc/inputrc`, where Debian keeps its Home, End and Ctrl+arrow keys.

## Git

`.config/git/config` holds the shared settings: Git LFS,
[diff-so-fancy](https://github.com/so-fancy/diff-so-fancy) as the pager when it is
installed, and:

| Setting                     | Effect                                                            |
| --------------------------- | ----------------------------------------------------------------- |
| `init.defaultBranch = main` | New repositories start on `main`                                  |
| `help.autocorrect = prompt` | A mistyped command such as `git pul` offers the closest one       |
| `fetch.prune = true`        | Fetching drops remote-tracking branches deleted on the remote     |
| `pull.rebase = true`        | Pulling replays unpushed local commits on top of the remote       |
| `push.autoSetupRemote`      | The first push of a new branch sets its upstream                  |
| `push.followTags = true`    | Pushing also pushes annotated tags that point at pushed commits   |

`.config/git/ignore` is the global ignore file, and
`.config/lazygit/config.yml` makes lazygit show diffs with diff-so-fancy too.

Keep `user.name`, `user.email` and credential helpers in `~/.gitconfig`, which is not
tracked. Git reads it after `.config/git/config`, and `git config --global` writes to it.
The install script creates an empty one if it is missing: without it,
`git config --global` would write to `.config/git/config` in this repository.

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
| `diagnose`      | Finds a root cause from evidence; runs checks before guessing       |
| `gaps`          | Finds gaps, contradictions and ambiguity in a request; asks first   |
| `design-review` | Design review of a PR, branch or local work; edits nothing          |

The install script links `~/.claude/skills/<name>` and `~/.codex/skills/<name>` to each
skill. A skill already at that place is moved to `~/.claude/skills.bak.<timestamp>/` or
`~/.codex/skills.bak.<timestamp>/`, outside the skills folder, so it does not load twice.
