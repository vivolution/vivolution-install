#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
PUBLIC_ROOT=$(CDPATH='' cd -- "${SCRIPT_DIR}/.." && pwd -P)
SOURCE_ROOT=${1:-'/Users/jay/Projects/Active/Vivolution CP Installer'}

# release.conf is resolved from this script's canonical directory at runtime.
# shellcheck disable=SC1091
. "${PUBLIC_ROOT}/release.conf"

fail() {
    printf 'Release test: %s\n' "$*" >&2
    exit 1
}

sha256_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

ARCHIVE_NAME="vivolution-controller-${RELEASE_VERSION}.tar.gz"
ARCHIVE_ROOT="vivolution-controller-${RELEASE_VERSION}"
ARCHIVE_PATH="${PUBLIC_ROOT}/dist/${ARCHIVE_NAME}"
TEMP_ROOT=''

cleanup() {
    if [ -n "$TEMP_ROOT" ] && [ -d "$TEMP_ROOT" ]; then
        rm -rf -- "$TEMP_ROOT"
    fi
}
trap cleanup EXIT HUP INT TERM

[ -f "$ARCHIVE_PATH" ] || fail "release archive is missing: ${ARCHIVE_PATH}"
[ "$ARCHIVE_SHA256" != PENDING ] || fail 'release checksum is still PENDING'
[ "$(sha256_file "$ARCHIVE_PATH")" = "$ARCHIVE_SHA256" ] ||
    fail 'release archive does not match release.conf'
grep -F "RELEASE_VERSION='${RELEASE_VERSION}'" "${PUBLIC_ROOT}/install.sh" >/dev/null ||
    fail 'bootstrap release version does not match release.conf'
grep -F "SOURCE_COMMIT='${SOURCE_COMMIT}'" "${PUBLIC_ROOT}/install.sh" >/dev/null ||
    fail 'bootstrap source commit does not match release.conf'
grep -F "ARCHIVE_SHA256='${ARCHIVE_SHA256}'" "${PUBLIC_ROOT}/install.sh" >/dev/null ||
    fail 'bootstrap checksum does not match release.conf'

TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/vivolution-release-test.XXXXXXXXXX") ||
    fail 'could not create test directory'
extract_root="${TEMP_ROOT}/extract"
mkdir -p "$extract_root"
tar -xzf "$ARCHIVE_PATH" --directory "$extract_root"
release_root="${extract_root}/${ARCHIVE_ROOT}"

[ -x "${release_root}/installer/install.sh" ] || fail 'packaged installer is not executable'
[ -z "$(find "$release_root" -type l -print -quit)" ] || fail 'packaged source contains a link'

set -- \
    controller \
    installer \
    deploy/roles/controller_services \
    deploy/roles/pgbouncer \
    deploy/roles/podman \
    deploy/roles/postgres_local

expected_paths="${TEMP_ROOT}/expected-paths"
actual_paths="${TEMP_ROOT}/actual-paths"
git -C "$SOURCE_ROOT" ls-tree -r --name-only "$SOURCE_COMMIT" -- "$@" |
    LC_ALL=C sort > "$expected_paths"
find "$release_root" -type f |
    sed "s#^${release_root}/##" |
    LC_ALL=C sort > "$actual_paths"
if ! cmp -s "$expected_paths" "$actual_paths"; then
    fail 'packaged file allowlist differs from the approved source commit'
fi

while IFS= read -r source_path; do
    expected_file="${TEMP_ROOT}/expected-file"
    git -C "$SOURCE_ROOT" show "${SOURCE_COMMIT}:${source_path}" > "$expected_file"
    cmp -s "$expected_file" "${release_root}/${source_path}" ||
        fail "packaged file differs from approved source: ${source_path}"
done < "$expected_paths"

fake_bin="${TEMP_ROOT}/fake-bin"
mkdir -p "$fake_bin"

cat > "${fake_bin}/curl" <<'EOF'
#!/bin/sh
set -eu
output=''
while [ "$#" -gt 0 ]; do
    case "$1" in
        --output)
            output=$2
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done
[ -n "$output" ]
cp "$VIVO_TEST_ARCHIVE" "$output"
if [ "${VIVO_TEST_TAMPER:-0}" = 1 ]; then
    printf 'tamper\n' >> "$output"
fi
EOF

cat > "${fake_bin}/id" <<'EOF'
#!/bin/sh
if [ "${1:-}" = -u ]; then
    printf '0\n'
else
    /usr/bin/id "$@"
fi
EOF

cat > "${fake_bin}/fake-python" <<'EOF'
#!/bin/sh
set -eu
if [ "${1:-}" = -c ]; then
    exit 0
fi
script=$1
shift
case "$script" in
    */installer/vivo_cp_installer.py) ;;
    *) exit 90 ;;
esac
{
    printf '%s\n' "$script"
    printf '%s\n' "$@"
} > "$VIVO_TEST_MARKER"
EOF

# macOS' compatibility sha256sum lacks GNU --strict, while Ubuntu 24.04 has
# the required GNU implementation. This adapter preserves the target command
# contract while letting the release flow be tested on the packaging Mac.
cat > "${fake_bin}/sha256sum" <<'EOF'
#!/bin/sh
set -eu
if [ "${1:-}" = --check ] && [ "${2:-}" = --strict ]; then
    IFS='  ' read -r expected filename
    actual=$(/usr/bin/shasum -a 256 "$filename" | awk '{print $1}')
    [ "$actual" = "$expected" ]
else
    exec /sbin/sha256sum "$@"
fi
EOF
chmod 0700 \
    "${fake_bin}/curl" \
    "${fake_bin}/id" \
    "${fake_bin}/fake-python" \
    "${fake_bin}/sha256sum"

marker="${TEMP_ROOT}/installer-called"
PATH="${fake_bin}:${PATH}" VIVO_TEST_ARCHIVE="$ARCHIVE_PATH" \
    "${PUBLIC_ROOT}/install.sh" --verify-only > "${TEMP_ROOT}/verify.out"
[ ! -e "$marker" ] || fail '--verify-only unexpectedly invoked the packaged installer'
grep -F 'archive verification passed; nothing was installed' "${TEMP_ROOT}/verify.out" >/dev/null ||
    fail '--verify-only did not report a successful non-installing verification'

rm -f "$marker"
if PATH="${fake_bin}:${PATH}" \
    VIVO_TEST_ARCHIVE="$ARCHIVE_PATH" \
    VIVO_TEST_TAMPER=1 \
    VIVO_TEST_MARKER="$marker" \
    VIVO_INSTALLER_PYTHON=fake-python \
    "${PUBLIC_ROOT}/install.sh" --verify-only > "${TEMP_ROOT}/tamper.out" 2>&1
then
    fail 'bootstrap accepted a tampered release archive'
fi
[ ! -e "$marker" ] || fail 'bootstrap invoked the installer after checksum failure'
grep -F 'SHA-256 verification failed' "${TEMP_ROOT}/tamper.out" >/dev/null ||
    fail 'bootstrap did not report checksum verification failure'

printf 'Release archive, provenance, verify-only, and tamper tests passed.\n'
