# Vivolution verified installer bootstrap

This public repository is the small, auditable entry point for the Vivolution
Controller installer. It does not contain credentials and it does not fetch the
private Git repository at install time.

The bootstrap downloads one versioned GitHub Release asset, enforces a 25 MiB
size ceiling, verifies its complete SHA-256 digest, rejects an unexpected
archive layout or links, and then runs the packaged `installer/install.sh` from
a private temporary directory. The release asset contains only the controller,
the turnkey installer, and the Ansible roles required by standalone CP1.

## Release candidate command

After the `v0.3.0-rc1` tag and matching GitHub Release asset exist, run this on
a fresh Ubuntu Server 24.04 LTS host:

```sh
curl --fail --show-error --silent --location --proto '=https' --tlsv1.2 \
  https://raw.githubusercontent.com/vivolution/vivolution-install/v0.3.0-rc1/install.sh \
  | sudo sh
```

This is a **beta standalone CP1-only** release candidate for clean-host
qualification. CP2,
CP3, SBC, carrier, and Teams configuration are separate modules and are not
silently installed by this command.

The piped bootstrap explicitly reopens `/dev/tty` before starting the
interactive installer. It fails clearly when no controlling terminal exists;
it never lets an interactive installation continue on the exhausted curl
pipe. CI can exercise the complete download, checksum, archive-layout, and
content verification path without installing anything:

```sh
curl --fail --show-error --silent --location --proto '=https' --tlsv1.2 \
  https://raw.githubusercontent.com/vivolution/vivolution-install/v0.3.0-rc1/install.sh \
  | sudo sh -s -- --verify-only
```

## Immutable release record

- Public release: `v0.3.0-rc1`
- Approved private source commit: `9a356881985824bb6434cff45be8be39b95fd559`
- Release asset: `vivolution-controller-0.3.0-rc1.tar.gz`
- Asset SHA-256: set in `release.conf` and embedded in `install.sh`
- Expected asset URL:
  `https://github.com/vivolution/vivolution-install/releases/download/v0.3.0-rc1/vivolution-controller-0.3.0-rc1.tar.gz`

The source repository may remain private: the release process exports only the
explicit allowlist needed by the standalone controller installer. Publishing
the release asset does make that packaged subset publicly downloadable.

## Local release build

From this repository:

```sh
./scripts/build-release.sh "/path/to/Vivolution CP Installer"
```

The builder requires the approved commit at `HEAD`, refuses changes within the
exported paths, rejects source links, exports a deterministic archive, and
writes `dist/SHA256SUMS`. For a new release, first set the new version and
source commit in `release.conf` and `install.sh`, build once with
`ARCHIVE_SHA256='PENDING'`, replace both checksum placeholders with the emitted
digest, then build and test again. Never publish a `PENDING` bootstrap.

Run the local gates before publication:

```sh
shellcheck install.sh scripts/build-release.sh tests/test-release.sh
./scripts/build-release.sh "/path/to/Vivolution CP Installer"
./tests/test-release.sh "/path/to/Vivolution CP Installer"
```

Publication is deliberately not automated here. Create the public repository,
push the reviewed files, create the immutable `v0.3.0-rc1` tag, and upload the
exact file from `dist/` only after the local digest and tests pass.
