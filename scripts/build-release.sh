#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
PUBLIC_ROOT=$(CDPATH='' cd -- "${SCRIPT_DIR}/.." && pwd -P)

# release.conf is resolved from this script's canonical directory at runtime.
# shellcheck disable=SC1091
. "${PUBLIC_ROOT}/release.conf"

fail() {
    printf 'Release build: %s\n' "$*" >&2
    exit 1
}

sha256_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        fail 'sha256sum or shasum is required'
    fi
}

if [ "$#" -ne 1 ]; then
    fail "usage: $0 /path/to/vivolution-controller"
fi

SOURCE_ROOT=$1
ARCHIVE_NAME="vivolution-controller-${RELEASE_VERSION}.tar.gz"
ARCHIVE_ROOT="vivolution-controller-${RELEASE_VERSION}"
DIST_ROOT="${PUBLIC_ROOT}/dist"
TEMP_ROOT=''

cleanup() {
    if [ -n "$TEMP_ROOT" ] && [ -d "$TEMP_ROOT" ]; then
        rm -rf -- "$TEMP_ROOT"
    fi
}
trap cleanup EXIT HUP INT TERM

case "$RELEASE_VERSION" in
    *[!A-Za-z0-9._-]*|'') fail 'release version contains unsafe characters' ;;
esac
case "$SOURCE_COMMIT" in
    [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;;
    *) fail 'source commit must be a full lowercase SHA-1 object name' ;;
esac
case "$ARCHIVE_SHA256" in
    PENDING) ;;
    [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;;
    *) fail 'archive SHA-256 must be PENDING or 64 lowercase hexadecimal characters' ;;
esac

if [ "$(git -C "$SOURCE_ROOT" rev-parse --is-inside-work-tree 2>/dev/null || true)" != true ]; then
    fail "source path is not a Git worktree: ${SOURCE_ROOT}"
fi
if [ "$(git -C "$SOURCE_ROOT" rev-parse HEAD)" != "$SOURCE_COMMIT" ]; then
    fail "source worktree HEAD is not the approved commit ${SOURCE_COMMIT}"
fi
if ! git -C "$SOURCE_ROOT" cat-file -e "${SOURCE_COMMIT}^{commit}"; then
    fail "approved source commit is unavailable: ${SOURCE_COMMIT}"
fi

set -- \
    controller \
    installer \
    deploy/roles/controller_services \
    deploy/roles/pgbouncer \
    deploy/roles/podman \
    deploy/roles/postgres_local

if [ -n "$(git -C "$SOURCE_ROOT" status --porcelain=v1 --untracked-files=all -- "$@")" ]; then
    fail 'approved release paths contain uncommitted or untracked changes'
fi

for source_path in "$@"; do
    if ! git -C "$SOURCE_ROOT" cat-file -e "${SOURCE_COMMIT}:${source_path}"; then
        fail "approved source path is missing at ${SOURCE_COMMIT}: ${source_path}"
    fi
done

if git -C "$SOURCE_ROOT" ls-tree -r "$SOURCE_COMMIT" -- "$@" |
    awk '$1 == "120000" { found = 1 } END { exit !found }'
then
    fail 'approved release paths contain a symbolic link'
fi

mkdir -p "$DIST_ROOT"
TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/vivolution-release.XXXXXXXXXX") ||
    fail 'could not create a private release-build directory'
temporary_archive="${TEMP_ROOT}/${ARCHIVE_NAME}"

git -C "$SOURCE_ROOT" archive \
    --format=tar.gz \
    -9 \
    --prefix="${ARCHIVE_ROOT}/" \
    --output="$temporary_archive" \
    "$SOURCE_COMMIT" \
    "$@"

if ! tar -tzf "$temporary_archive" |
    awk -v prefix="${ARCHIVE_ROOT}/" '
        BEGIN { found = 0 }
        index($0, prefix) != 1 { exit 1 }
        { found = 1 }
        END { if (!found) exit 1 }
    '
then
    fail 'generated archive has an unexpected path layout'
fi

actual_sha256=$(sha256_file "$temporary_archive")
if [ "$ARCHIVE_SHA256" != PENDING ] && [ "$actual_sha256" != "$ARCHIVE_SHA256" ]; then
    fail "generated SHA-256 ${actual_sha256} does not match release.conf ${ARCHIVE_SHA256}"
fi

cp "$temporary_archive" "${DIST_ROOT}/${ARCHIVE_NAME}"
printf '%s  %s\n' "$actual_sha256" "$ARCHIVE_NAME" > "${DIST_ROOT}/SHA256SUMS"
chmod 0644 "${DIST_ROOT}/${ARCHIVE_NAME}" "${DIST_ROOT}/SHA256SUMS"

printf 'Built %s\n' "${DIST_ROOT}/${ARCHIVE_NAME}"
printf 'SHA-256 %s\n' "$actual_sha256"
printf 'Source commit %s\n' "$SOURCE_COMMIT"
if [ "$ARCHIVE_SHA256" = PENDING ]; then
    printf 'Set ARCHIVE_SHA256 to this digest in release.conf and install.sh, then rebuild.\n'
fi
