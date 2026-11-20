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

# Fails with the label and a diff when the two strings differ
expect_same() {
    local label=$1 expected=$2 actual=$3
    if [ "$expected" != "$actual" ]; then
        diff <(echo "$expected") <(echo "$actual") >&2 || true
        fail "$label"
    fi
}
