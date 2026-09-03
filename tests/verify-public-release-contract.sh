#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
PUBLIC_ROOT=$(CDPATH='' cd -- "${SCRIPT_DIR}/.." && pwd -P)
# shellcheck disable=SC1091
. "${PUBLIC_ROOT}/release.conf"

RELEASE_BASE_URL="https://github.com/vivolution/vivolution-install/releases/download/v${RELEASE_VERSION}"
RELEASE_API_URL="https://api.github.com/repos/vivolution/vivolution-install/releases/tags/v${RELEASE_VERSION}"
CONTROLLER_ARCHIVE_NAME="vivolution-controller-${RELEASE_VERSION}.tar.gz"
EDGE_ARCHIVE_NAME="vivolution-edge-enrollment-${RELEASE_VERSION}.tar.gz"
TEMP_ROOT=''
EVIDENCE_DIR=${PUBLIC_RELEASE_EVIDENCE_DIR:-}

fail() {
    printf 'Public release contract: %s\n' "$*" >&2
    exit 1
}

cleanup() {
    if [ -n "$TEMP_ROOT" ] && [ -d "$TEMP_ROOT" ]; then
        rm -rf -- "$TEMP_ROOT"
    fi
}
trap cleanup EXIT HUP INT TERM

for command_name in awk cat chmod cmp cp curl grep mkdir mktemp python3 rm sed sha256sum sort tar wc; do
    command -v "$command_name" >/dev/null 2>&1 ||
        fail "required command not found: ${command_name}"
done

TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/vivolution-public-contract.XXXXXXXXXX") ||
    fail 'could not create a temporary directory'
if [ -z "$EVIDENCE_DIR" ]; then
    EVIDENCE_DIR="${TEMP_ROOT}/evidence"
fi
mkdir -p "$EVIDENCE_DIR"

fetch_release_file() {
    name=$1
    curl --fail --show-error --silent --location \
        --proto '=https' --proto-redir '=https' --tlsv1.2 \
        --retry 3 --retry-all-errors --connect-timeout 10 --max-time 300 \
        --output "${TEMP_ROOT}/${name}" \
        "${RELEASE_BASE_URL}/${name}"
}

fetch_release_file "$CONTROLLER_ARCHIVE_NAME"
fetch_release_file "$EDGE_ARCHIVE_NAME"
fetch_release_file SHA256SUMS
curl --fail --show-error --silent --location \
    --proto '=https' --proto-redir '=https' --tlsv1.2 \
    --retry 3 --retry-all-errors --connect-timeout 10 --max-time 60 \
    --header 'Accept: application/vnd.github+json' \
    --header 'X-GitHub-Api-Version: 2022-11-28' \
    --output "${TEMP_ROOT}/release.json" \
    "$RELEASE_API_URL"

expected_sums="${TEMP_ROOT}/expected-sums"
actual_sums="${TEMP_ROOT}/actual-sums"
{
    printf '%s  %s\n' "$CONTROLLER_ARCHIVE_SHA256" "$CONTROLLER_ARCHIVE_NAME"
    printf '%s  %s\n' "$EDGE_ENROLLMENT_ARCHIVE_SHA256" "$EDGE_ARCHIVE_NAME"
} | LC_ALL=C sort > "$expected_sums"
LC_ALL=C sort "${TEMP_ROOT}/SHA256SUMS" > "$actual_sums"
cmp -s "$expected_sums" "$actual_sums" ||
    fail 'published SHA256SUMS is not the exact expected two-artifact ledger'
(
    cd "$TEMP_ROOT"
    sha256sum --check --strict SHA256SUMS
) >/dev/null 2>&1 ||
    fail 'a published archive does not match SHA256SUMS'

python3 - "$TEMP_ROOT" "$EVIDENCE_DIR" "$RELEASE_VERSION" "$SOURCE_COMMIT" \
    "$CONTROLLER_ARCHIVE_NAME" "$CONTROLLER_ARCHIVE_SHA256" \
    "$EDGE_ARCHIVE_NAME" "$EDGE_ENROLLMENT_ARCHIVE_SHA256" <<'PY'
from __future__ import annotations

import datetime as dt
import hashlib
import json
from pathlib import Path
import sys
import tarfile

(
    temp_text,
    evidence_text,
    release_version,
    source_commit,
    controller_name,
    controller_sha,
    edge_name,
    edge_sha,
) = sys.argv[1:]
temp_root = Path(temp_text)
evidence_dir = Path(evidence_text)
release = json.loads((temp_root / "release.json").read_text(encoding="utf-8"))

if release.get("tag_name") != f"v{release_version}":
    raise SystemExit("release tag does not match release.conf")
if release.get("draft") is not False or release.get("prerelease") is not True:
    raise SystemExit("release must be a published prerelease, not a draft")

expected = {
    "SHA256SUMS": None,
    controller_name: controller_sha,
    edge_name: edge_sha,
}
assets = release.get("assets") or []
asset_names = {item.get("name") for item in assets}
if asset_names != set(expected):
    raise SystemExit(f"unexpected published asset set: {sorted(asset_names)}")
for item in assets:
    name = item["name"]
    expected_sha = expected[name]
    digest = item.get("digest")
    if expected_sha is not None and digest != f"sha256:{expected_sha}":
        raise SystemExit(f"GitHub asset digest mismatch for {name}")
    local_path = temp_root / name
    if item.get("size") != local_path.stat().st_size:
        raise SystemExit(f"GitHub asset byte count mismatch for {name}")

body = release.get("body") or ""
for expected_text in (source_commit, controller_sha, edge_sha):
    if expected_text not in body:
        raise SystemExit("release notes are missing immutable provenance data")

published_at = release.get("published_at")
if not published_at:
    raise SystemExit("release has no publication timestamp")

artifact_records = []
for name, expected_sha in ((controller_name, controller_sha), (edge_name, edge_sha)):
    path = temp_root / name
    observed_sha = hashlib.sha256(path.read_bytes()).hexdigest()
    if observed_sha != expected_sha:
        raise SystemExit(f"local digest mismatch for {name}")
    artifact_records.append(
        {
            "name": name,
            "url": f"https://github.com/vivolution/vivolution-install/releases/download/v{release_version}/{name}",
            "sha256": observed_sha,
            "bytes": path.stat().st_size,
        }
    )

manifest = {
    "schema_version": 1,
    "product": "Vivolution Turnkey Voice Platform",
    "release": release_version,
    "source_commit": source_commit,
    "release_published_at": published_at,
    "verification_generated_at": dt.datetime.now(dt.timezone.utc).isoformat(),
    "artifacts": artifact_records,
}
(evidence_dir / "verification-manifest.json").write_text(
    json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
)

files = []
packages = []
relationships = []
for package_index, record in enumerate(artifact_records, start=1):
    package_id = f"SPDXRef-Package-{package_index}"
    packages.append(
        {
            "SPDXID": package_id,
            "name": record["name"],
            "versionInfo": release_version,
            "downloadLocation": record["url"],
            "filesAnalyzed": True,
            "checksums": [{"algorithm": "SHA256", "checksumValue": record["sha256"]}],
            "licenseConcluded": "NOASSERTION",
            "licenseDeclared": "NOASSERTION",
            "copyrightText": "NOASSERTION",
        }
    )
    with tarfile.open(temp_root / record["name"], mode="r:gz") as archive:
        for member in archive.getmembers():
            if not member.isfile():
                continue
            extracted = archive.extractfile(member)
            if extracted is None:
                raise SystemExit(f"could not read archive member {member.name}")
            digest = hashlib.sha256(extracted.read()).hexdigest()
            stable = hashlib.sha256(f"{record['name']}:{member.name}".encode()).hexdigest()[:24]
            file_id = f"SPDXRef-File-{stable}"
            files.append(
                {
                    "SPDXID": file_id,
                    "fileName": f"./{record['name']}/{member.name}",
                    "checksums": [{"algorithm": "SHA256", "checksumValue": digest}],
                    "licenseConcluded": "NOASSERTION",
                    "licenseInfoInFiles": ["NOASSERTION"],
                    "copyrightText": "NOASSERTION",
                }
            )
            relationships.append(
                {
                    "spdxElementId": package_id,
                    "relationshipType": "CONTAINS",
                    "relatedSpdxElement": file_id,
                }
            )

namespace_digest = hashlib.sha256(
    f"{release_version}:{source_commit}:{controller_sha}:{edge_sha}".encode()
).hexdigest()
sbom = {
    "spdxVersion": "SPDX-2.3",
    "dataLicense": "CC0-1.0",
    "SPDXID": "SPDXRef-DOCUMENT",
    "name": f"Vivolution-{release_version}-verification-SBOM",
    "documentNamespace": f"https://vivolution.example/spdx/{release_version}/{namespace_digest}",
    "creationInfo": {
        "created": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "creators": ["Tool: Vivolution public release verifier"],
    },
    "documentDescribes": [item["SPDXID"] for item in packages],
    "packages": packages,
    "files": files,
    "relationships": relationships,
}
(evidence_dir / "verification-sbom.spdx.json").write_text(
    json.dumps(sbom, indent=2, sort_keys=True) + "\n", encoding="utf-8"
)

summary = {
    "release": release_version,
    "source_commit": source_commit,
    "artifact_count": len(artifact_records),
    "file_count": len(files),
    "result": "passed",
}
(evidence_dir / "verification-summary.json").write_text(
    json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8"
)
PY

# Exercise the production bootstrap against a deliberately modified archive.
tampered_archive="${TEMP_ROOT}/tampered-${CONTROLLER_ARCHIVE_NAME}"
cp "${TEMP_ROOT}/${CONTROLLER_ARCHIVE_NAME}" "$tampered_archive"
printf 'tamper' >> "$tampered_archive"
if printf '%s  %s\n' "$CONTROLLER_ARCHIVE_SHA256" "$tampered_archive" |
    sha256sum --check --strict >/dev/null 2>&1
then
    fail 'tampered archive unexpectedly retained the approved digest'
fi

fake_bin="${TEMP_ROOT}/fake-bin"
mkdir -p "$fake_bin"
cat > "${fake_bin}/curl" <<'FAKECURL'
#!/bin/sh
set -eu
output=''
while [ "$#" -gt 0 ]; do
    case "$1" in
        --output)
            [ "$#" -ge 2 ] || exit 2
            output=$2
            shift 2
            ;;
        --output=*)
            output=${1#--output=}
            shift
            ;;
        *)
            shift
            ;;
    esac
done
[ -n "$output" ] || exit 2
cp "$FAKE_CURL_SOURCE" "$output"
FAKECURL
chmod 0700 "${fake_bin}/curl"

tamper_log="${TEMP_ROOT}/tamper.log"
if sudo env PATH="${fake_bin}:/usr/bin:/bin" FAKE_CURL_SOURCE="$tampered_archive" \
    sh "${PUBLIC_ROOT}/install.sh" --verify-only >"$tamper_log" 2>&1
then
    fail 'production bootstrap accepted a tampered Controller archive'
fi
grep -F 'release archive SHA-256 verification failed' "$tamper_log" >/dev/null ||
    fail 'tamper rejection did not fail at the digest boundary'

# Rebind only a disposable bootstrap copy to a digest-valid but unsafe archive
# so archive-layout rejection is tested independently from checksum rejection.
unsafe_source="${TEMP_ROOT}/wrong-root"
mkdir -p "$unsafe_source"
printf 'unsafe layout fixture\n' > "${unsafe_source}/payload.txt"
unsafe_archive="${TEMP_ROOT}/unsafe.tar.gz"
tar -czf "$unsafe_archive" -C "$TEMP_ROOT" wrong-root
unsafe_sha=$(sha256sum "$unsafe_archive" | awk '{print $1}')
unsafe_bootstrap="${TEMP_ROOT}/unsafe-bootstrap.sh"
sed "s/^ARCHIVE_SHA256='[^']*'/ARCHIVE_SHA256='${unsafe_sha}'/" \
    "${PUBLIC_ROOT}/install.sh" > "$unsafe_bootstrap"
unsafe_log="${TEMP_ROOT}/unsafe.log"
if sudo env PATH="${fake_bin}:/usr/bin:/bin" FAKE_CURL_SOURCE="$unsafe_archive" \
    sh "$unsafe_bootstrap" --verify-only >"$unsafe_log" 2>&1
then
    fail 'bootstrap accepted a digest-valid archive with an unsafe root'
fi
grep -F 'unsafe or unexpected path layout' "$unsafe_log" >/dev/null ||
    fail 'unsafe archive was not rejected at the path-layout boundary'

printf 'Public release metadata, checksums, provenance, tamper rejection, and archive safety passed.\n'
printf 'Verification evidence: %s\n' "$EVIDENCE_DIR"
