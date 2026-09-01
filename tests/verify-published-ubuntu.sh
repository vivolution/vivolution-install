#!/bin/sh
set -eu

CONTROLLER_BOOTSTRAP_URL='https://raw.githubusercontent.com/vivolution/vivolution-install/v0.3.0-rc7/install.sh'
CONTROLLER_LATEST_URL='https://raw.githubusercontent.com/vivolution/vivolution-install/main/install.sh'
EDGE_BOOTSTRAP_URL='https://raw.githubusercontent.com/vivolution/vivolution-install/v0.3.0-rc7/install-edge.sh'
TEMP_ROOT=''

fail() {
    printf 'Published-release verification: %s\n' "$*" >&2
    exit 1
}

cleanup() {
    if [ -n "$TEMP_ROOT" ] && [ -d "$TEMP_ROOT" ]; then
        rm -rf -- "$TEMP_ROOT"
    fi
}
trap cleanup EXIT HUP INT TERM

[ -r /etc/os-release ] || fail '/etc/os-release is unavailable'
# shellcheck disable=SC1091
. /etc/os-release
[ "${ID:-}" = ubuntu ] || fail 'this verification must run on Ubuntu'
[ "${VERSION_ID:-}" = 24.04 ] || fail 'Ubuntu 24.04 is required'

for command_name in cmp curl shellcheck sudo mktemp; do
    command -v "$command_name" >/dev/null 2>&1 ||
        fail "required command not found: ${command_name}"
done

TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/vivolution-published.XXXXXXXXXX") ||
    fail 'could not create a temporary directory'

verify_bootstrap() {
    label=$1
    url=$2
    script_path="${TEMP_ROOT}/${label}.sh"
    curl --fail --show-error --silent --location \
        --proto '=https' --proto-redir '=https' --tlsv1.2 \
        --output "$script_path" \
        "$url"
    shellcheck "$script_path"
    curl --fail --show-error --silent --location \
        --proto '=https' --proto-redir '=https' --tlsv1.2 \
        "$url" \
        | sudo sh -s -- --verify-only
}

verify_bootstrap controller-tagged "$CONTROLLER_BOOTSTRAP_URL"
verify_bootstrap controller-latest "$CONTROLLER_LATEST_URL"
cmp "${TEMP_ROOT}/controller-tagged.sh" "${TEMP_ROOT}/controller-latest.sh" ||
    fail 'latest-recommended Controller bootstrap differs from the approved tagged bootstrap'
verify_bootstrap edge-enrollment "$EDGE_BOOTSTRAP_URL"

curl --fail --show-error --silent --location \
    --proto '=https' --proto-redir '=https' --tlsv1.2 \
    "$CONTROLLER_BOOTSTRAP_URL" \
    | sudo sh -s -- check-host-os
curl --fail --show-error --silent --location \
    --proto '=https' --proto-redir '=https' --tlsv1.2 \
    "$CONTROLLER_LATEST_URL" \
    | sudo sh -s -- check-host-os
curl --fail --show-error --silent --location \
    --proto '=https' --proto-redir '=https' --tlsv1.2 \
    "$EDGE_BOOTSTRAP_URL" \
    | sudo sh -s -- --check-host-os

printf 'Published Ubuntu 24.04 integrity and packaged host-OS verification passed.\n'
