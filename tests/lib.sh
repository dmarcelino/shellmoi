# Helpers the tests share. Sourced, not run.
# shellcheck shell=bash

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

# Writes the lines to the file, creating its folder
put() {
    mkdir -p "$(dirname "$1")"
    printf '%s\n' "$2" > "$1"
}

# Lists every path under the folder with its link target or checksum
snapshot() {
    (cd "$1" && find . -mindepth 1 | LC_ALL=C sort | while IFS= read -r path; do
        if [ -L "$path" ]; then
            echo "$path -> $(readlink "$path")"
        elif [ -d "$path" ]; then
            echo "$path/"
        else
            echo "$path $(cksum < "$path")"
        fi
    done)
}

# Links the first rsync 3 or later on PATH into the folder, which the tests put first on a
# PATH of /usr/bin:/bin: there, macOS has only its own rsync, which is older
link_rsync3() {
    local rsync re='^rsync +version +([0-9]+)\.'
    while IFS= read -r rsync; do
        if [[ $("$rsync" --version 2>/dev/null) =~ $re ]] && [ "${BASH_REMATCH[1]}" -ge 3 ]; then
            ln -sf "$rsync" "$1/rsync"
            return 0
        fi
    done < <(type -ap rsync)
    fail "this test needs rsync 3 or later on PATH"
}

# Fails with the label and a diff when the two strings differ
expect_same() {
    local label=$1 expected=$2 actual=$3
    if [ "$expected" != "$actual" ]; then
        diff <(echo "$expected") <(echo "$actual") >&2 || true
        fail "$label"
    fi
}
