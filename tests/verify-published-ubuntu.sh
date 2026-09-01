#!/bin/sh
set -eu

BOOTSTRAP_URL='https://raw.githubusercontent.com/vivolution/vivolution-install/v0.3.0-rc1/install.sh'
TEMP_SCRIPT=''

fail() {
    printf 'Published-release verification: %s\n' "$*" >&2
    exit 1
}

cleanup() {
    if [ -n "$TEMP_SCRIPT" ] && [ -f "$TEMP_SCRIPT" ]; then
        rm -f -- "$TEMP_SCRIPT"
    fi
}
trap cleanup EXIT HUP INT TERM

[ -r /etc/os-release ] || fail '/etc/os-release is unavailable'
# shellcheck disable=SC1091
. /etc/os-release
[ "${ID:-}" = ubuntu ] || fail 'this verification must run on Ubuntu'
[ "${VERSION_ID:-}" = 24.04 ] || fail 'Ubuntu 24.04 is required'

for command_name in curl shellcheck sudo; do
    command -v "$command_name" >/dev/null 2>&1 ||
        fail "required command not found: ${command_name}"
done

TEMP_SCRIPT=$(mktemp "${TMPDIR:-/tmp}/vivolution-published.XXXXXXXXXX") ||
    fail 'could not create a temporary file'

curl --fail --show-error --silent --location \
    --proto '=https' --tlsv1.2 \
    --output "$TEMP_SCRIPT" \
    "$BOOTSTRAP_URL"
shellcheck "$TEMP_SCRIPT"

curl --fail --show-error --silent --location \
    --proto '=https' --tlsv1.2 \
    "$BOOTSTRAP_URL" \
    | sudo sh -s -- --verify-only

printf 'Published Ubuntu 24.04 bootstrap verification passed.\n'
