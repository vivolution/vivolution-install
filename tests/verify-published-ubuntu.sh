#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
PUBLIC_ROOT=$(CDPATH='' cd -- "${SCRIPT_DIR}/.." && pwd -P)
# shellcheck disable=SC1091
. "${PUBLIC_ROOT}/release.conf"

CONTROLLER_BOOTSTRAP_URL="https://raw.githubusercontent.com/vivolution/vivolution-install/v${RELEASE_VERSION}/install.sh"
CONTROLLER_LATEST_URL='https://raw.githubusercontent.com/vivolution/vivolution-install/main/install.sh'
EDGE_BOOTSTRAP_URL="https://raw.githubusercontent.com/vivolution/vivolution-install/v${RELEASE_VERSION}/install-edge.sh"
CONTROLLER_ARCHIVE_NAME="vivolution-controller-${RELEASE_VERSION}.tar.gz"
CONTROLLER_ARCHIVE_ROOT="vivolution-controller-${RELEASE_VERSION}"
CONTROLLER_ARCHIVE_URL="https://github.com/vivolution/vivolution-install/releases/download/v${RELEASE_VERSION}/${CONTROLLER_ARCHIVE_NAME}"
TEMP_ROOT=''
STATE_ROOT='/var/lib/vivolution/installer'

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

for command_name in awk cmp curl find mktemp rm sha256sum shellcheck sudo tar wc tr; do
    command -v "$command_name" >/dev/null 2>&1 ||
        fail "required command not found: ${command_name}"
done

[ ! -e "$STATE_ROOT" ] ||
    fail "verification runner is not clean: ${STATE_ROOT} already exists"

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

controller_archive="${TEMP_ROOT}/${CONTROLLER_ARCHIVE_NAME}"
curl --fail --show-error --silent --location \
    --proto '=https' --proto-redir '=https' --tlsv1.2 \
    --output "$controller_archive" \
    "$CONTROLLER_ARCHIVE_URL"
printf '%s  %s\n' "$CONTROLLER_ARCHIVE_SHA256" "$controller_archive" |
    sha256sum --check --strict >/dev/null 2>&1 ||
    fail 'downloaded Controller archive does not match release.conf'

listing_path="${TEMP_ROOT}/controller.list"
metadata_path="${TEMP_ROOT}/controller.metadata"
tar -tzf "$controller_archive" > "$listing_path" ||
    fail 'Controller archive is not a readable gzip-compressed tar archive'
awk -v prefix="${CONTROLLER_ARCHIVE_ROOT}/" '
    BEGIN { found = 0 }
    index($0, prefix) != 1 { exit 1 }
    {
        relative = substr($0, length(prefix) + 1)
        if (relative ~ /(^|\/)\.\.($|\/)/) { exit 1 }
        if (relative ~ /(^|\/)\.($|\/)/) { exit 1 }
        if (seen[$0]++) { exit 1 }
        found = 1
    }
    END { if (!found) exit 1 }
' "$listing_path" ||
    fail 'Controller archive has an unsafe or unexpected path layout'
LC_ALL=C tar -tvzf "$controller_archive" > "$metadata_path" ||
    fail 'Controller archive metadata could not be read'
awk '
    substr($0, 1, 1) != "-" && substr($0, 1, 1) != "d" { exit 1 }
    END { if (NR == 0) exit 1 }
' "$metadata_path" ||
    fail 'Controller archive contains a link or special file'

extract_root="${TEMP_ROOT}/controller-source"
mkdir -p "$extract_root"
tar -xzf "$controller_archive" \
    --directory "$extract_root" \
    --no-same-owner \
    --no-same-permissions ||
    fail 'Controller archive extraction failed'
controller_release_root="${extract_root}/${CONTROLLER_ARCHIVE_ROOT}"
controller_installer="${controller_release_root}/installer/install.sh"
[ -x "$controller_installer" ] ||
    fail 'packaged Controller host-OS entry point is missing or not executable'
[ -z "$(find "$controller_release_root" -type l -print -quit)" ] ||
    fail 'packaged Controller archive contains a symbolic link'

sudo "$controller_installer" check-host-os
curl --fail --show-error --silent --location \
    --proto '=https' --proto-redir '=https' --tlsv1.2 \
    "$EDGE_BOOTSTRAP_URL" \
    | sudo sh -s -- --check-host-os

[ ! -e "$STATE_ROOT" ] ||
    fail 'non-installing host-OS checks created durable installer state'

printf 'Published Ubuntu 24.04 integrity and packaged host-OS verification passed.\n'
