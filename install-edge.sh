#!/bin/sh
set -eu

# These values are immutable for this tagged bootstrap. The source archive is
# accepted only when its complete SHA-256 digest matches this release record.
RELEASE_VERSION='0.3.0-rc4'
SOURCE_COMMIT='337f8717c72d4734e78195ac83a02828ab424738'
ARCHIVE_SHA256='888f9cec11162930e99fd224345ca122d35476e7b803357b9155f7df2371ed9b'
ARCHIVE_NAME="vivolution-edge-enrollment-${RELEASE_VERSION}.tar.gz"
ARCHIVE_ROOT="vivolution-edge-enrollment-${RELEASE_VERSION}"
ARCHIVE_URL="https://github.com/vivolution/vivolution-install/releases/download/v${RELEASE_VERSION}/${ARCHIVE_NAME}"
MAX_ARCHIVE_BYTES=8388608
MAX_ARCHIVE_ENTRIES=512
BOOTSTRAP_MODE='install'

BOOTSTRAP_TMP=''

fail() {
    printf 'Vivolution Edge enrollment bootstrap: %s\n' "$*" >&2
    exit 1
}

cleanup() {
    if [ -n "$BOOTSTRAP_TMP" ] && [ -d "$BOOTSTRAP_TMP" ]; then
        rm -rf -- "$BOOTSTRAP_TMP"
    fi
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

if [ "${1:-}" = '--verify-only' ]; then
    BOOTSTRAP_MODE='verify-only'
    shift
elif [ "${1:-}" = '--check-host-os' ]; then
    BOOTSTRAP_MODE='check-host-os'
    shift
fi
if [ "$#" -ne 0 ]; then
    fail 'the public bootstrap accepts only --verify-only or --check-host-os'
fi

if [ "$(id -u)" -ne 0 ]; then
    fail 'run this bootstrap as root (the published command uses sudo)'
fi

for required_command in curl sha256sum tar awk find wc tr mktemp rm id; do
    require_command "$required_command"
done

umask 077
BOOTSTRAP_TMP=$(mktemp -d "${TMPDIR:-/tmp}/vivolution-edge-bootstrap.XXXXXXXXXX") ||
    fail 'could not create a private temporary directory'
trap cleanup EXIT HUP INT TERM

archive_path="${BOOTSTRAP_TMP}/${ARCHIVE_NAME}"
listing_path="${BOOTSTRAP_TMP}/archive.list"
metadata_path="${BOOTSTRAP_TMP}/archive.metadata"
extract_path="${BOOTSTRAP_TMP}/source"

printf 'Downloading Vivolution Edge enrollment client %s BETA...\n' \
    "$RELEASE_VERSION"
printf 'This installs enrollment/visibility only, not an SBC or voice data plane.\n'
curl \
    --fail \
    --show-error \
    --silent \
    --location \
    --proto '=https' \
    --proto-redir '=https' \
    --tlsv1.2 \
    --retry 3 \
    --retry-all-errors \
    --connect-timeout 10 \
    --max-time 300 \
    --output "$archive_path" \
    "$ARCHIVE_URL" || fail 'release archive download failed'

archive_bytes=$(wc -c < "$archive_path" | tr -d '[:space:]')
case "$archive_bytes" in
    ''|*[!0-9]*) fail 'downloaded archive has an invalid size' ;;
esac
if [ "$archive_bytes" -eq 0 ] || [ "$archive_bytes" -gt "$MAX_ARCHIVE_BYTES" ]; then
    fail "downloaded archive size is outside the allowed range: ${archive_bytes} bytes"
fi

if ! printf '%s  %s\n' "$ARCHIVE_SHA256" "$archive_path" |
    sha256sum --check --strict >/dev/null 2>&1
then
    fail 'release archive SHA-256 verification failed'
fi
printf 'Verified SHA-256 %s (source commit %s).\n' "$ARCHIVE_SHA256" "$SOURCE_COMMIT"

if ! tar -tzf "$archive_path" > "$listing_path"; then
    fail 'verified release archive is not a readable gzip-compressed tar archive'
fi
if ! awk -v prefix="${ARCHIVE_ROOT}/" -v maximum="$MAX_ARCHIVE_ENTRIES" '
    BEGIN { found = 0; count = 0 }
    index($0, prefix) != 1 { exit 1 }
    {
        relative = substr($0, length(prefix) + 1)
        if (relative ~ /(^|\/)\.\.($|\/)/) { exit 1 }
        if (relative ~ /(^|\/)\.($|\/)/) { exit 1 }
        if (seen[$0]++) { exit 1 }
        count++
        if (count > maximum) { exit 1 }
        found = 1
    }
    END { if (!found) exit 1 }
' "$listing_path"
then
    fail 'verified release archive has an unsafe or unexpected path layout'
fi
if ! LC_ALL=C tar -tvzf "$archive_path" > "$metadata_path"; then
    fail 'verified release archive metadata could not be read'
fi
if ! awk '
    substr($0, 1, 1) != "-" && substr($0, 1, 1) != "d" { exit 1 }
    END { if (NR == 0) exit 1 }
' "$metadata_path"
then
    fail 'verified release archive contains a link or special file'
fi

mkdir -p "$extract_path"
if ! tar -xzf "$archive_path" \
    --directory "$extract_path" \
    --no-same-owner \
    --no-same-permissions
then
    fail 'verified release archive extraction failed'
fi

source_root="${extract_path}/${ARCHIVE_ROOT}"
installer_path="${source_root}/installer/install-edge.sh"
if [ ! -d "$source_root" ] || [ -L "$source_root" ]; then
    fail 'verified release archive did not create the expected source directory'
fi
if [ -n "$(find "$source_root" -type l -print -quit)" ]; then
    fail 'verified release archive contains a symbolic link'
fi
if [ ! -f "$installer_path" ] || [ -L "$installer_path" ] || [ ! -x "$installer_path" ]; then
    fail 'verified release archive is missing its executable enrollment entry point'
fi
for required_path in \
    installer/ansible/ansible.cfg \
    edge/enrollment/release.py \
    edge/enrollment/cli.py \
    edge/enrollment/client.py \
    deploy/playbooks/install-edge-enrollment-local.yml \
    deploy/roles/edge_enrollment_install/tasks/main.yml \
    deploy/roles/edge_enrollment_install/defaults/main.yml
do
    if [ ! -f "${source_root}/${required_path}" ] || [ -L "${source_root}/${required_path}" ]; then
        fail "verified release archive is incomplete: ${required_path}"
    fi
done

if [ "$BOOTSTRAP_MODE" = 'verify-only' ]; then
    printf 'Vivolution Edge enrollment %s BETA archive verification passed; nothing was installed.\n' \
        "$RELEASE_VERSION"
    exit 0
fi
if [ "$BOOTSTRAP_MODE" = 'check-host-os' ]; then
    "$installer_path" --check-host-os
    exit 0
fi

printf 'Starting the verified enrollment-only installer...\n'
if [ -c /dev/tty ] && ( : </dev/tty ) 2>/dev/null; then
    "$installer_path" </dev/tty
else
    fail 'no controlling terminal is available; use --verify-only for CI or run the bootstrap from an interactive sudo session'
fi
