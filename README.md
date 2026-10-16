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

### 2. Use the repository's `.bashrc`

`.bashrc` loads bash-completion (from the system or Homebrew), then bash-sensible, then
`.bash_aliases`. It also sets the prompt to `user@host:folder(branch)$`, adds `~/bin` and
`~/.local/bin` to `PATH`, and sets up kubectl, nvm, worktrunk and SDKMAN when they are
installed.

Open a new shell and check bash-completion loaded: `echo "${BASH_COMPLETION_VERSINFO[@]}"`
prints a version.

### 3. Keep private settings local

Put secrets, work-specific aliases and anything else machine-specific in `~/.bashrc.local`.
`.bashrc` sources it last, and git ignores it.
