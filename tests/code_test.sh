#!/usr/bin/env bash
# Sources .bash_aliases in a clean shell and checks `code`: over SSH it prints a vscode://
# Remote-SSH link to the folder; locally and in VS Code's terminal it runs the real `code`.
#
#   tests/code_test.sh

set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
. "$repo/tests/lib.sh"

# A stand-in for the real `code`, so the test can tell it ran
mkdir -p "$work/bin" "$work/my project"
printf '#!/bin/sh\necho "real code $*"\n' > "$work/bin/code"
chmod +x "$work/bin/code"
folder=$(cd "$work/my project" && pwd -P)

# Runs `code` with the arguments from the folder, with only the given variables set;
# prints stdout, then stderr and the exit status
run_code() {
    local vars=()
    while [ $# -gt 0 ] && [ "$1" != -- ]; do
        vars+=("$1")
        shift
    done
    shift
    (cd "$folder" && env -i HOME="$work" PATH="$work/bin:/usr/bin:/bin" USER=alice ${vars[@]+"${vars[@]}"} \
        bash -c '. "$1"; shift; code "$@"' _ "$repo/.bash_aliases" "$@" 2>&1; echo "status $?")
}

ssh=SSH_CONNECTION="192.0.2.1 50000 192.0.2.10 22"

expect_same "over SSH, current folder" \
    "vscode://vscode-remote/ssh-remote+alice@192.0.2.10${folder// /%20}
status 0" "$(run_code "$ssh" --)"

expect_same "over SSH, folder given" \
    "vscode://vscode-remote/ssh-remote+alice@192.0.2.10${folder// /%20}
status 0" "$(run_code "$ssh" -- "$folder")"

expect_same "over SSH, host from SHELLMOI_CODE_HOST" \
    "vscode://vscode-remote/ssh-remote+box${folder// /%20}
status 0" "$(run_code "$ssh" SHELLMOI_CODE_HOST=box --)"

expect_same "over SSH, not a folder" \
    "code: not a folder: $work/missing
status 1" "$(run_code "$ssh" -- "$work/missing")"

expect_same "local shell runs the real code" \
    "real code .
status 0" "$(run_code -- .)"

expect_same "VS Code's terminal runs the real code" \
    "real code .
status 0" "$(run_code "$ssh" TERM_PROGRAM=vscode -- .)"

echo "PASS: code"
