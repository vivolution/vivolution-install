#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
PUBLIC_ROOT=$(CDPATH='' cd -- "${SCRIPT_DIR}/.." && pwd -P)
SOURCE_ROOT=${1:-'/Users/jay/Projects/Active/Vivolution SBC'}

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

find_test_python() {
    for candidate in python3.14 python3.13 python3.12 python3.11 python3.10 python3; do
        if command -v "$candidate" >/dev/null 2>&1 &&
            "$candidate" -c 'import sys; raise SystemExit(sys.version_info < (3, 10))'
        then
            command -v "$candidate"
            return 0
        fi
    done
    fail 'Python 3.10 or newer is required for release compatibility tests'
}

CONTROLLER_ARCHIVE_NAME="vivolution-controller-${RELEASE_VERSION}.tar.gz"
CONTROLLER_ARCHIVE_ROOT="vivolution-controller-${RELEASE_VERSION}"
CONTROLLER_ARCHIVE_PATH="${PUBLIC_ROOT}/dist/${CONTROLLER_ARCHIVE_NAME}"
EDGE_ARCHIVE_NAME="vivolution-edge-enrollment-${RELEASE_VERSION}.tar.gz"
EDGE_ARCHIVE_ROOT="vivolution-edge-enrollment-${RELEASE_VERSION}"
EDGE_ARCHIVE_PATH="${PUBLIC_ROOT}/dist/${EDGE_ARCHIVE_NAME}"
TEMP_ROOT=''

cleanup() {
    if [ -n "$TEMP_ROOT" ] && [ -d "$TEMP_ROOT" ]; then
        rm -rf -- "$TEMP_ROOT"
    fi
}
trap cleanup EXIT HUP INT TERM

TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/vivolution-release-test.XXXXXXXXXX") ||
    fail 'could not create test directory'

[ -f "$CONTROLLER_ARCHIVE_PATH" ] ||
    fail "Controller archive is missing: ${CONTROLLER_ARCHIVE_PATH}"
[ -f "$EDGE_ARCHIVE_PATH" ] ||
    fail "Edge enrollment archive is missing: ${EDGE_ARCHIVE_PATH}"
[ "$CONTROLLER_ARCHIVE_SHA256" != PENDING ] ||
    fail 'Controller checksum is still PENDING'
[ "$EDGE_ENROLLMENT_ARCHIVE_SHA256" != PENDING ] ||
    fail 'Edge enrollment checksum is still PENDING'
[ "$(sha256_file "$CONTROLLER_ARCHIVE_PATH")" = "$CONTROLLER_ARCHIVE_SHA256" ] ||
    fail 'Controller archive does not match release.conf'
[ "$(sha256_file "$EDGE_ARCHIVE_PATH")" = "$EDGE_ENROLLMENT_ARCHIVE_SHA256" ] ||
    fail 'Edge enrollment archive does not match release.conf'

expected_sums="${TEMP_ROOT}/expected-sums"
{
    printf '%s  %s\n' "$CONTROLLER_ARCHIVE_SHA256" "$CONTROLLER_ARCHIVE_NAME"
    printf '%s  %s\n' "$EDGE_ENROLLMENT_ARCHIVE_SHA256" "$EDGE_ARCHIVE_NAME"
} > "$expected_sums"
cmp -s "$expected_sums" "${PUBLIC_ROOT}/dist/SHA256SUMS" ||
    fail 'dist/SHA256SUMS does not contain the exact two release records'
rm -f -- "$expected_sums"

for bootstrap in install.sh install-edge.sh; do
    grep -F "RELEASE_VERSION='${RELEASE_VERSION}'" "${PUBLIC_ROOT}/${bootstrap}" >/dev/null ||
        fail "${bootstrap} release version does not match release.conf"
    grep -F "SOURCE_COMMIT='${SOURCE_COMMIT}'" "${PUBLIC_ROOT}/${bootstrap}" >/dev/null ||
        fail "${bootstrap} source commit does not match release.conf"
done
grep -F "ARCHIVE_SHA256='${CONTROLLER_ARCHIVE_SHA256}'" \
    "${PUBLIC_ROOT}/install.sh" >/dev/null ||
    fail 'Controller bootstrap checksum does not match release.conf'
grep -F "ARCHIVE_SHA256='${EDGE_ENROLLMENT_ARCHIVE_SHA256}'" \
    "${PUBLIC_ROOT}/install-edge.sh" >/dev/null ||
    fail 'Edge enrollment bootstrap checksum does not match release.conf'
grep -F "BOOTSTRAP_MODE='check-host-os'" \
    "${PUBLIC_ROOT}/install-edge.sh" >/dev/null ||
    fail 'public Edge bootstrap does not expose the packaged host OS check'
grep -F "\"\$installer_path\" --check-host-os" \
    "${PUBLIC_ROOT}/install-edge.sh" >/dev/null ||
    fail 'public Edge bootstrap does not invoke the packaged host OS check'

if grep -F 'PENDING' \
    "${PUBLIC_ROOT}/release.conf" \
    "${PUBLIC_ROOT}/install.sh" \
    "${PUBLIC_ROOT}/install-edge.sh" \
    "${PUBLIC_ROOT}/README.md" >/dev/null
then
    fail 'a public release record still contains PENDING'
fi
grep -F -- "- Approved private source commit: \`${SOURCE_COMMIT}\`" \
    "${PUBLIC_ROOT}/README.md" >/dev/null ||
    fail 'README source commit does not match release.conf'
grep -F -- "- Controller asset SHA-256: \`${CONTROLLER_ARCHIVE_SHA256}\`" \
    "${PUBLIC_ROOT}/README.md" >/dev/null ||
    fail 'README Controller checksum does not match release.conf'
grep -F -- "- Edge asset SHA-256: \`${EDGE_ENROLLMENT_ARCHIVE_SHA256}\`" \
    "${PUBLIC_ROOT}/README.md" >/dev/null ||
    fail 'README Edge checksum does not match release.conf'
grep -F -- "- Public release: \`v${RELEASE_VERSION}\`" \
    "${PUBLIC_ROOT}/README.md" >/dev/null ||
    fail 'README public release version does not match release.conf'
grep -F -- "- Controller asset: \`${CONTROLLER_ARCHIVE_NAME}\`" \
    "${PUBLIC_ROOT}/README.md" >/dev/null ||
    fail 'README Controller asset name does not match release.conf'
grep -F -- "- Edge asset: \`${EDGE_ARCHIVE_NAME}\`" \
    "${PUBLIC_ROOT}/README.md" >/dev/null ||
    fail 'README Edge asset name does not match release.conf'
grep -F -- '**Enforced installer minimum:** 2 vCPU, 4 GiB RAM, and a 40 GB root disk.' \
    "${PUBLIC_ROOT}/README.md" >/dev/null ||
    fail 'README does not state the enforced Controller capacity minimum'
grep -F -- "On Azure, use \`Standard_D2as_v5\` with a 64 GiB Premium" \
    "${PUBLIC_ROOT}/README.md" >/dev/null ||
    fail 'README does not state the qualified Controller POC size'

controller_raw_url="https://raw.githubusercontent.com/vivolution/vivolution-install/v${RELEASE_VERSION}/install.sh"
edge_raw_url="https://raw.githubusercontent.com/vivolution/vivolution-install/v${RELEASE_VERSION}/install-edge.sh"
controller_latest_url="https://raw.githubusercontent.com/vivolution/vivolution-install/main/install.sh"
grep -F "$controller_latest_url" "${PUBLIC_ROOT}/README.md" >/dev/null ||
    fail 'README is missing the permanent latest-recommended Controller command'
grep -F "$controller_raw_url | sudo sh -s -- resume" \
    "${PUBLIC_ROOT}/README.md" >/dev/null ||
    fail 'README is missing the version-pinned failed-preflight resume command'
grep -F "$controller_raw_url" "${PUBLIC_ROOT}/README.md" >/dev/null ||
    fail 'README Controller command does not use the release tag'
grep -F "$edge_raw_url" "${PUBLIC_ROOT}/README.md" >/dev/null ||
    fail 'README Edge command does not use the release tag'
grep -F "CONTROLLER_BOOTSTRAP_URL='${controller_raw_url}'" \
    "${PUBLIC_ROOT}/tests/verify-published-ubuntu.sh" >/dev/null ||
    fail 'published Ubuntu verifier has a stale Controller URL'
grep -F "CONTROLLER_LATEST_URL='${controller_latest_url}'" \
    "${PUBLIC_ROOT}/tests/verify-published-ubuntu.sh" >/dev/null ||
    fail 'published Ubuntu verifier is missing the latest-recommended Controller URL'
grep -F "EDGE_BOOTSTRAP_URL='${edge_raw_url}'" \
    "${PUBLIC_ROOT}/tests/verify-published-ubuntu.sh" >/dev/null ||
    fail 'published Ubuntu verifier has a stale Edge URL'

controller_extract="${TEMP_ROOT}/controller-extract"
edge_extract="${TEMP_ROOT}/edge-extract"
mkdir -p "$controller_extract" "$edge_extract"
tar -xzf "$CONTROLLER_ARCHIVE_PATH" --directory "$controller_extract"
tar -xzf "$EDGE_ARCHIVE_PATH" --directory "$edge_extract"
controller_release_root="${controller_extract}/${CONTROLLER_ARCHIVE_ROOT}"
edge_release_root="${edge_extract}/${EDGE_ARCHIVE_ROOT}"

[ -x "${controller_release_root}/installer/install.sh" ] ||
    fail 'packaged Controller installer is not executable'
[ ! -e "${controller_release_root}/installer/install-edge.sh" ] ||
    fail 'Controller asset unexpectedly contains the Edge enrollment entry point'
[ -x "${edge_release_root}/installer/install-edge.sh" ] ||
    fail 'packaged Edge enrollment installer is not executable'
[ ! -e "${edge_release_root}/installer/install.sh" ] ||
    fail 'Edge enrollment asset unexpectedly contains the Controller entry point'
[ -z "$(find "$controller_release_root" -type l -print -quit)" ] ||
    fail 'packaged Controller source contains a link'
[ -z "$(find "$edge_release_root" -type l -print -quit)" ] ||
    fail 'packaged Edge enrollment source contains a link'

controller_caddyfile="${controller_release_root}/installer/ansible/roles/ubuntu_ingress/templates/Caddyfile.j2"
controller_installer="${controller_release_root}/installer/vivo_cp_installer.py"
edge_installer="${edge_release_root}/installer/install-edge.sh"
issuer_count=$(awk 'index($0, "cert_issuer acme") { count++ } END { print count + 0 }' \
    "$controller_caddyfile")
[ "$issuer_count" -eq 1 ] ||
    fail 'packaged Controller must configure exactly one ACME certificate issuer'
grep -F 'dir https://acme-v02.api.letsencrypt.org/directory' \
    "$controller_caddyfile" >/dev/null ||
    fail "packaged Controller is not pinned to Let's Encrypt production"
grep -F 'email {{ cp_acme_email | to_json }}' "$controller_caddyfile" >/dev/null ||
    fail 'packaged Controller does not safely render the ACME contact email'
if grep -i -E 'zerossl|tls[[:space:]]+internal' "$controller_caddyfile" >/dev/null; then
    fail 'packaged Controller contains an alternate or local certificate issuer'
fi
grep -F 'INSTALLER_VERSION = "0.3.0-rc7"' "$controller_installer" >/dev/null ||
    fail 'packaged launcher has a stale internal version'
grep -F 'LEDGER_SCHEMA_VERSION = 5' "$controller_installer" >/dev/null ||
    fail 'packaged launcher does not use the rc7 schema-5 ledger'
grep -F 'DEFAULT_STATE_DIR = "/var/lib/vivolution/installer"' \
    "$controller_installer" >/dev/null ||
    fail 'packaged launcher does not use the secured rc7 state namespace'
grep -F 'DEFAULT_LOG_DIR = "/var/log/vivolution/installer"' \
    "$controller_installer" >/dev/null ||
    fail 'packaged launcher does not use the secured rc7 log namespace'
for menu_label in \
    'Create a new Controller Plane' \
    'Join an existing Controller Plane' \
    'Deploy an Edge Appliance (SBC)' \
    'Manage an existing installation' \
    'Diagnostics / network readiness test'
do
    grep -F "$menu_label" "$controller_installer" >/dev/null ||
        fail "packaged launcher is missing menu label: ${menu_label}"
done
grep -F '("join-controller", "Join an existing Controller Plane", False)' \
    "$controller_installer" >/dev/null ||
    fail 'packaged launcher unexpectedly enables Controller joining'
grep -F '("deploy-edge", "Deploy an Edge Appliance (SBC)", False)' \
    "$controller_installer" >/dev/null ||
    fail 'packaged launcher unexpectedly enables full SBC deployment'
grep -F 'DISCARD_CONFIRMATION_TOKEN = "DISCARD-INCOMPLETE"' \
    "$controller_installer" >/dev/null ||
    fail 'packaged launcher is missing guarded incomplete-run cleanup'
grep -F '_authorization_pattern = re.compile(' "$controller_installer" >/dev/null ||
    fail 'packaged launcher is missing pattern-based authorization redaction'
grep -F "Let's Encrypt ACME contact email" "$controller_installer" >/dev/null ||
    fail 'packaged Controller does not ask for the ACME contact email'
grep -F 'detected_ssh_cidr = current_ssh_client_cidr' "$controller_installer" >/dev/null ||
    fail 'packaged Controller does not default to a validated active SSH source'
grep -F '0.0.0.0/0 is intentionally refused' "$controller_installer" >/dev/null ||
    fail 'packaged Controller does not explain its world-open SSH refusal'
grep -F 'link_target == "../usr/lib/os-release"' "$controller_installer" >/dev/null ||
    fail 'packaged Controller does not accept the canonical Ubuntu OS metadata link'
for host_check_installer in "$controller_installer" "$edge_installer"; do
    grep -F 'os.O_CLOEXEC | os.O_NOFOLLOW | os.O_NONBLOCK' \
        "$host_check_installer" >/dev/null ||
        fail 'a packaged installer does not enforce no-follow OS metadata reads'
    grep -F 'check-host-os' "$host_check_installer" >/dev/null ||
        fail 'a packaged installer is missing the non-installing host OS check'
done

compare_allowlist() {
    release_root=$1
    label=$2
    shift 2
    expected_paths="${TEMP_ROOT}/${label}-expected-paths"
    actual_paths="${TEMP_ROOT}/${label}-actual-paths"
    git -C "$SOURCE_ROOT" ls-tree -r --name-only "$SOURCE_COMMIT" -- "$@" |
        LC_ALL=C sort > "$expected_paths"
    find "$release_root" -type f |
        sed "s#^${release_root}/##" |
        LC_ALL=C sort > "$actual_paths"
    if ! cmp -s "$expected_paths" "$actual_paths"; then
        fail "${label} packaged file allowlist differs from the approved source commit"
    fi
    while IFS= read -r source_path; do
        expected_file="${TEMP_ROOT}/${label}-expected-file"
        git -C "$SOURCE_ROOT" show "${SOURCE_COMMIT}:${source_path}" > "$expected_file"
        cmp -s "$expected_file" "${release_root}/${source_path}" ||
            fail "${label} packaged file differs from approved source: ${source_path}"
    done < "$expected_paths"
}

set -- \
    controller \
    installer/install.sh \
    installer/vivo_cp_installer.py \
    installer/ansible \
    deploy/roles/controller_services \
    deploy/roles/pgbouncer \
    deploy/roles/podman \
    deploy/roles/postgres_local
compare_allowlist "$controller_release_root" controller "$@"

set -- \
    installer/install-edge.sh \
    installer/ansible/ansible.cfg \
    edge/enrollment \
    deploy/playbooks/install-edge-enrollment-local.yml \
    deploy/roles/edge_enrollment_install
compare_allowlist "$edge_release_root" edge-enrollment "$@"

TEST_PYTHON=$(find_test_python)
edge_source_digest=$(
    "$TEST_PYTHON" \
        "${edge_release_root}/edge/enrollment/release.py" \
        "${edge_release_root}/edge/enrollment"
)
controller_supported_digest=$(
    "$TEST_PYTHON" - "${controller_release_root}/controller/cp1/edge_release.py" <<'PY'
import ast
import sys
from pathlib import Path

tree = ast.parse(Path(sys.argv[1]).read_text(encoding="utf-8"))
for node in tree.body:
    if isinstance(node, ast.Assign):
        if any(
            isinstance(target, ast.Name)
            and target.id == "SUPPORTED_EDGE_ENROLLMENT_RELEASE_DIGEST"
            for target in node.targets
        ):
            print(ast.literal_eval(node.value))
            break
else:
    raise SystemExit("Controller supported Edge digest is missing")
PY
)
role_pinned_digest=$(sed -n \
    's/^edge_enrollment_release_digest: \(sha256:[0-9a-f][0-9a-f]*\)$/\1/p' \
    "${edge_release_root}/deploy/roles/edge_enrollment_install/defaults/main.yml")
[ "$edge_source_digest" = "$controller_supported_digest" ] ||
    fail 'Controller-supported digest differs from the exported Edge source digest'
[ "$edge_source_digest" = "$role_pinned_digest" ] ||
    fail 'Edge role pin differs from the exported Edge source digest'

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

# macOS' compatibility sha256sum lacks GNU --strict, while Ubuntu 24.04 has
# the required GNU implementation. This adapter preserves the target contract.
cat > "${fake_bin}/sha256sum" <<'EOF'
#!/bin/sh
set -eu
if [ "${1:-}" = --check ] && [ "${2:-}" = --strict ]; then
    IFS='  ' read -r expected filename
    if [ -x /usr/bin/sha256sum ]; then
        actual=$(/usr/bin/sha256sum "$filename" | awk '{print $1}')
    elif [ -x /usr/bin/shasum ]; then
        actual=$(/usr/bin/shasum -a 256 "$filename" | awk '{print $1}')
    elif [ -x /sbin/sha256sum ]; then
        actual=$(/sbin/sha256sum "$filename" | awk '{print $1}')
    else
        exit 127
    fi
    [ "$actual" = "$expected" ]
elif [ -x /usr/bin/sha256sum ]; then
    exec /usr/bin/sha256sum "$@"
elif [ -x /sbin/sha256sum ]; then
    exec /sbin/sha256sum "$@"
else
    exec /usr/bin/shasum -a 256 "$@"
fi
EOF
chmod 0700 "${fake_bin}/curl" "${fake_bin}/id" "${fake_bin}/sha256sum"

verify_bootstrap() {
    bootstrap=$1
    archive=$2
    expected_text=$3
    label=$4
    PATH="${fake_bin}:${PATH}" VIVO_TEST_ARCHIVE="$archive" \
        "$bootstrap" --verify-only > "${TEMP_ROOT}/${label}-verify.out"
    grep -F "$expected_text" "${TEMP_ROOT}/${label}-verify.out" >/dev/null ||
        fail "${label} --verify-only did not report successful verification"

    if PATH="${fake_bin}:${PATH}" \
        VIVO_TEST_ARCHIVE="$archive" \
        VIVO_TEST_TAMPER=1 \
        "$bootstrap" --verify-only > "${TEMP_ROOT}/${label}-tamper.out" 2>&1
    then
        fail "${label} bootstrap accepted a tampered release archive"
    fi
    grep -F 'SHA-256 verification failed' "${TEMP_ROOT}/${label}-tamper.out" >/dev/null ||
        fail "${label} bootstrap did not report checksum verification failure"
}

verify_bootstrap \
    "${PUBLIC_ROOT}/install.sh" \
    "$CONTROLLER_ARCHIVE_PATH" \
    'archive verification passed; nothing was installed' \
    controller
verify_bootstrap \
    "${PUBLIC_ROOT}/install-edge.sh" \
    "$EDGE_ARCHIVE_PATH" \
    'archive verification passed; nothing was installed' \
    edge-enrollment

printf 'Separate Controller/Edge assets, provenance, compatibility, verify-only, and tamper tests passed.\n'
