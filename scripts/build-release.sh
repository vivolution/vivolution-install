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

validate_digest() {
    digest_value=$1
    if [ "$digest_value" = PENDING ]; then
        return 0
    fi
    case "$digest_value" in
        ''|*[!0-9a-f]*)
            fail 'archive SHA-256 values must be PENDING or 64 lowercase hexadecimal characters'
            ;;
    esac
    if [ "${#digest_value}" -ne 64 ]; then
        fail 'archive SHA-256 values must be PENDING or 64 lowercase hexadecimal characters'
    fi
}

if [ "$#" -ne 1 ]; then
    fail "usage: $0 /path/to/vivolution-controller"
fi

SOURCE_ROOT=$1
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
validate_digest "$CONTROLLER_ARCHIVE_SHA256"
validate_digest "$EDGE_ENROLLMENT_ARCHIVE_SHA256"

if [ "$(git -C "$SOURCE_ROOT" rev-parse --is-inside-work-tree 2>/dev/null || true)" != true ]; then
    fail "source path is not a Git worktree: ${SOURCE_ROOT}"
fi
if [ "$(git -C "$SOURCE_ROOT" rev-parse HEAD)" != "$SOURCE_COMMIT" ]; then
    fail "source worktree HEAD is not the approved commit ${SOURCE_COMMIT}"
fi
if ! git -C "$SOURCE_ROOT" cat-file -e "${SOURCE_COMMIT}^{commit}"; then
    fail "approved source commit is unavailable: ${SOURCE_COMMIT}"
fi

mkdir -p "$DIST_ROOT"
TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/vivolution-release.XXXXXXXXXX") ||
    fail 'could not create a private release-build directory'

build_archive() {
    archive_name=$1
    archive_root=$2
    expected_sha256=$3
    shift 3

    if [ -n "$(git -C "$SOURCE_ROOT" status --porcelain=v1 --untracked-files=all -- "$@")" ]; then
        fail "approved paths for ${archive_name} contain uncommitted or untracked changes"
    fi
    for source_path in "$@"; do
        if ! git -C "$SOURCE_ROOT" cat-file -e "${SOURCE_COMMIT}:${source_path}"; then
            fail "approved source path is missing at ${SOURCE_COMMIT}: ${source_path}"
        fi
    done
    if git -C "$SOURCE_ROOT" ls-tree -r "$SOURCE_COMMIT" -- "$@" |
        awk '$1 == "120000" { found = 1 } END { exit !found }'
    then
        fail "approved paths for ${archive_name} contain a symbolic link"
    fi

    temporary_archive="${TEMP_ROOT}/${archive_name}"
    git -C "$SOURCE_ROOT" archive \
        --format=tar.gz \
        -9 \
        --prefix="${archive_root}/" \
        --output="$temporary_archive" \
        "$SOURCE_COMMIT" \
        "$@"

    if ! tar -tzf "$temporary_archive" |
        awk -v prefix="${archive_root}/" '
            BEGIN { found = 0 }
            index($0, prefix) != 1 { exit 1 }
            { found = 1 }
            END { if (!found) exit 1 }
        '
    then
        fail "${archive_name} has an unexpected path layout"
    fi

    built_sha256=$(sha256_file "$temporary_archive")
    if [ "$expected_sha256" != PENDING ] && [ "$built_sha256" != "$expected_sha256" ]; then
        fail "generated SHA-256 ${built_sha256} does not match the release record for ${archive_name}"
    fi
    cp "$temporary_archive" "${DIST_ROOT}/${archive_name}"
    chmod 0644 "${DIST_ROOT}/${archive_name}"
}

controller_archive_name="vivolution-controller-${RELEASE_VERSION}.tar.gz"
controller_archive_root="vivolution-controller-${RELEASE_VERSION}"
set -- \
    controller \
    installer/install.sh \
    installer/vivo_cp_installer.py \
    installer/ansible \
    deploy/roles/controller_services \
    deploy/roles/pgbouncer \
    deploy/roles/podman \
    deploy/roles/postgres_local
build_archive \
    "$controller_archive_name" \
    "$controller_archive_root" \
    "$CONTROLLER_ARCHIVE_SHA256" \
    "$@"
controller_actual_sha256=$built_sha256

edge_archive_name="vivolution-edge-enrollment-${RELEASE_VERSION}.tar.gz"
edge_archive_root="vivolution-edge-enrollment-${RELEASE_VERSION}"
set -- \
    installer/install-edge.sh \
    installer/ansible/ansible.cfg \
    edge/enrollment \
    deploy/playbooks/install-edge-enrollment-local.yml \
    deploy/roles/edge_enrollment_install
build_archive \
    "$edge_archive_name" \
    "$edge_archive_root" \
    "$EDGE_ENROLLMENT_ARCHIVE_SHA256" \
    "$@"
edge_actual_sha256=$built_sha256

{
    printf '%s  %s\n' "$controller_actual_sha256" "$controller_archive_name"
    printf '%s  %s\n' "$edge_actual_sha256" "$edge_archive_name"
} > "${DIST_ROOT}/SHA256SUMS"
chmod 0644 "${DIST_ROOT}/SHA256SUMS"

printf 'Built %s\n' "${DIST_ROOT}/${controller_archive_name}"
printf 'Controller SHA-256 %s\n' "$controller_actual_sha256"
printf 'Built %s\n' "${DIST_ROOT}/${edge_archive_name}"
printf 'Edge enrollment SHA-256 %s\n' "$edge_actual_sha256"
printf 'Source commit %s\n' "$SOURCE_COMMIT"
if [ "$CONTROLLER_ARCHIVE_SHA256" = PENDING ] ||
   [ "$EDGE_ENROLLMENT_ARCHIVE_SHA256" = PENDING ]
then
    printf 'Set both digests in release.conf and their respective bootstraps, then rebuild.\n'
fi
