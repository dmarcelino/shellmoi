# my-shell

Configuration for a bash shell: opinionated defaults, used across different machines.

The repository root mirrors the home directory: a file at `.config/foo` here belongs at
`~/.config/foo`.

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

### 2. Load bash-completion

Some packages load bash-completion for you; the guards below avoid loading it twice. Add
the block for your system near the top of `~/.bashrc`.

Linux:

```bash
# Use bash-completion, if available, and avoid double-sourcing
[[ $PS1 &&
  ! ${BASH_COMPLETION_VERSINFO:-} &&
  -f /usr/share/bash-completion/bash_completion ]] &&
    . /usr/share/bash-completion/bash_completion
```

macOS (Homebrew):

```bash
if [[ -s $HOMEBREW_PREFIX/etc/profile.d/bash_completion.sh ]]; then
  . "$HOMEBREW_PREFIX/etc/profile.d/bash_completion.sh"
fi
```

Open a new shell and check it loaded: `echo "${BASH_COMPLETION_VERSINFO[@]}"` prints a
version.

### 3. Load bash-sensible

Source it after bash-completion, still near the top of `~/.bashrc`:

```bash
if [[ -f ~/.config/bash/sensible/sensible.bash ]]; then
  source ~/.config/bash/sensible/sensible.bash
fi
```

Keep it near the top: it replaces `PROMPT_COMMAND`, so tools that add to `PROMPT_COMMAND`
must be set up after it.
