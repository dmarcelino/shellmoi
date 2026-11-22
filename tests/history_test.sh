#!/usr/bin/env bash
# Runs commands in an interactive shell started from .bashrc and checks which of them reach
# the history file: those naming a secret, such as `export AWS_SECRET_ACCESS_KEY=...`, must
# not; others must.
#
#   tests/history_test.sh

set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

# .bashrc loads bash-sensible from ~/.config, where the install links it
mkdir -p "$work/.config/bash"
ln -s "$repo/.config/bash/sensible" "$work/.config/bash/sensible"

secret_commands=(
    "export AWS_ACCESS_KEY_ID=example"
    "export AWS_SECRET_ACCESS_KEY=example"
    "export AWS_SESSION_TOKEN=example"
    "export OPENAI_API_KEY=example"
    "export APIKEY=example"
    "export DB_PASSWORD=example"
    "export DB_PASSWD=example"
    "export QAS_JWT=example"
    "export GOOGLE_APPLICATION_CREDENTIALS=example"
    "GITHUB_TOKEN=example true"
)
kept_commands=(
    "true kept-command"
    "true ./get_jwt_token.py"
)

printf '%s\n' "${kept_commands[@]}" "${secret_commands[@]}" |
    env -i HOME="$work" PATH=/usr/bin:/bin TERM=dumb \
        bash --rcfile "$repo/.bashrc" -i > /dev/null 2>&1

[ -f "$work/.bash_history" ] || fail "the shell wrote no history file"
history=$(grep -v '^#' "$work/.bash_history")

for command in "${kept_commands[@]}"; do
    grep -qxF "$command" <<< "$history" || fail "not in history: $command"
done
for command in "${secret_commands[@]}"; do
    grep -qxF "$command" <<< "$history" && fail "in history: $command"
done

echo "PASS: history"
