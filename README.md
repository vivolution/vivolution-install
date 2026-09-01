# Vivolution verified installer bootstraps

This public repository contains small, auditable entry points for two separate
Ubuntu 24.04 modules:

- the standalone Controller CP1; and
- the enrollment-only Edge client/placeholder.

Each bootstrap downloads one versioned GitHub Release asset, enforces a size
ceiling, verifies its complete SHA-256 digest, rejects links and unexpected
archive layouts, and then runs the packaged installer from a private temporary
directory. The source repository may remain private because the release
builder exports only an explicit reviewed allowlist.

These release candidates are checksum-verified over GitHub HTTPS. They do not
yet have an independent detached publisher signature.

## 1. Install standalone Controller CP1

### Permanent latest-recommended command

Run this same command from a normal sudo-enabled account on every fresh Ubuntu
Server 24.04 LTS machine:

```sh
curl --fail --show-error --silent --location --proto '=https' --proto-redir '=https' --tlsv1.2 https://raw.githubusercontent.com/vivolution/vivolution-install/main/install.sh | sudo sh
```

The `main/install.sh` path is Vivolution's mutable **latest-recommended
channel**. It currently installs `v0.3.0-rc4`. Each approved release advances
this channel only after its exact version, source commit, asset name, and
SHA-256 digest have been updated and the release checks pass. The bootstrap
does not blindly execute an asset selected by the GitHub API: the channel
script still downloads one exact versioned archive and verifies its embedded
SHA-256 digest before running it.

### Version-pinned command

Use this form when a deployment must remain reproducible on one exact release:

```sh
curl --fail --show-error --silent --location --proto '=https' --proto-redir '=https' --tlsv1.2 https://raw.githubusercontent.com/vivolution/vivolution-install/v0.3.0-rc4/install.sh | sudo sh
```

This command installs **standalone CP1 only**. CP2, CP3, automatic controller
failover, the SBC voice data plane, Microsoft Teams, and SIP carriers are not
silently installed.

### Controller VM sizing

- **Enforced installer minimum:** 2 vCPU, 4 GiB RAM, and a 40 GB root disk.
- **Recommended for the current POC/test:** 2 vCPU, 8 GiB RAM, and a 64 GiB
  SSD-backed root disk. On Azure, use `Standard_D2as_v5` with a 64 GiB Premium
  SSD LRS OS disk.
- **Starting point for a production pilot:** 4 vCPU, 16 GiB RAM, and at least a
  128 GiB Premium SSD, followed by measurement-based resizing and off-VM
  backups.

Avoid burstable CPU SKUs for a Controller that will run continuously. This
standalone CP1 hosts PostgreSQL, PgBouncer, Caddy, and the Controller application
on the same VM. The production-pilot figure is planning guidance, not a claim
that this prerelease is production-qualified.

### Controller addresses requested by the wizard

The installer is domain-neutral. It does not hard-code
`controller.voice.vivolution.ae` or any other customer/domain name. It asks for
two distinct DNS hostnames; enter hostnames only, without `https://` or a path:

- **Controller VM FQDN** — the unique address of this Controller VM, for
  example `cp1.cloudpremises.com`.
- **Controller shared FQDN** — the stable central address used by operators and
  every future Edge node, for example `controller.voice.vivolution.ae`,
  `probe.cloudpremises.com`, or `cp.cloudved.com`.

For standalone CP1, both public DNS A records must resolve only to this Ubuntu
machine's declared public IPv4 address and neither name may publish an AAAA
record. Allow inbound TCP 22, 80, and 443. In a future qualified
multi-controller deployment, each Controller keeps its unique VM FQDN while
the shared FQDN remains stable in front of the Controller service.

### Let's Encrypt certificates

The wizard asks for a **Let's Encrypt ACME contact email**, defaulting to the
validated Controller administrator email. Caddy is configured with exactly one
certificate issuer: the Let's Encrypt production ACME directory. It requests
public certificates for both the unique Controller VM FQDN and stable shared
FQDN, stores the managed keys under Caddy's protected service data directory,
redirects HTTP to HTTPS, and renews the certificates automatically.

There is no ZeroSSL or local/self-signed fallback in this Controller profile.
If public issuance is unavailable, the trusted HTTPS readiness checks fail the
installation instead of accepting an untrusted certificate. Before installing,
ensure both A records are fully propagated, remove stale/incorrect AAAA records,
make public TCP 80/443 reach this VM, and permit `letsencrypt.org` in any CAA
policy. This rc4 candidate requires a fresh host or an rc3 run that stopped in
the initial read-only OS preflight; it does not claim to convert certificates
cached by an rc2 installation.

Stock Ubuntu 24.04 normally exposes `/etc/os-release` as the canonical relative
symlink `../usr/lib/os-release`. rc4 accepts that exact safe layout and adds a
non-installing packaged host-OS check. If rc3 stopped with `OS metadata is
missing or unsafe` before asking any configuration questions, resume the same
protected ledger after rc4 is promoted with this one-time recovery command:

```sh
curl --fail --show-error --silent --location --proto '=https' --proto-redir '=https' --tlsv1.2 https://raw.githubusercontent.com/vivolution/vivolution-install/main/install.sh | sudo sh -s -- resume
```

This automation covers the Controller web/API certificate only. Future SBC
certificates for Microsoft Teams Direct Routing and SIP trunks use a separate
certificate workflow and are not installed by this enrollment-only release.

## 2. Enrollment-only Edge client (not an SBC installer)

This command installs only the outbound Edge enrollment client/placeholder on
a separate fresh Ubuntu Server 24.04 LTS machine:

```sh
curl --fail --show-error --silent --location --proto '=https' --proto-redir '=https' --tlsv1.2 https://raw.githubusercontent.com/vivolution/vivolution-install/v0.3.0-rc4/install-edge.sh | sudo sh
```

It does **not** install or configure an SBC, SIP services, RTP/media, Microsoft
Teams Direct Routing, a carrier/Twilio trunk, firewall rules for voice, or a
working call path. It implements only the bounded provider-neutral enrollment
and fleet-visibility slice. Desired-state delivery, secrets, remote actions, mTLS/client
certificate issuance, and complete Controller management remain later gates.

### Create the one-time grant first

After CP1 is installed:

1. Sign in at `https://<Controller-shared-FQDN>/admin/`.
2. Create the expected Edge cluster and Edge node, including its unique name,
   slot A/B, and real amd64/arm64 architecture.
3. Select exactly that Edge node and run **Issue a display-once enrollment
   grant**.
4. Keep the displayed shared Controller URL and ten-minute one-time grant ready.
5. Run the Edge command above. Enter the displayed canonical shared HTTPS
   Controller URL when prompted, then paste the grant into the hidden prompt.
6. Back in the Controller, compare the exact node key fingerprint and approve
   the pending claim.

The Edge generates its Ed25519 identity locally. The raw grant is never stored
by the Controller or Edge, accepted in argv/environment variables, or reused
for heartbeats. Pending nodes poll the shared Controller URL over outbound
HTTPS. Approved nodes send signed heartbeats and become visible in the
Controller with last-seen time, health, boot/sequence, and inventory/release
digests. Revocation blocks all further node challenges and requests.

## Non-installing verification

These commands exercise the download, archive checksum, layout, and content
checks without installing anything:

```sh
curl --fail --show-error --silent --location --proto '=https' --proto-redir '=https' --tlsv1.2 \
  https://raw.githubusercontent.com/vivolution/vivolution-install/v0.3.0-rc4/install.sh \
  | sudo sh -s -- --verify-only

curl --fail --show-error --silent --location --proto '=https' --proto-redir '=https' --tlsv1.2 \
  https://raw.githubusercontent.com/vivolution/vivolution-install/v0.3.0-rc4/install-edge.sh \
  | sudo sh -s -- --verify-only
```

Both interactive bootstraps explicitly reopen `/dev/tty`; they fail clearly
without a controlling terminal instead of reading prompts from the exhausted
curl pipe.

On Ubuntu 24.04, these commands additionally exercise the packaged OS-metadata
compatibility check without creating installer state or installing packages:

```sh
curl --fail --show-error --silent --location --proto '=https' --proto-redir '=https' --tlsv1.2 \
  https://raw.githubusercontent.com/vivolution/vivolution-install/v0.3.0-rc4/install.sh \
  | sudo sh -s -- check-host-os

curl --fail --show-error --silent --location --proto '=https' --proto-redir '=https' --tlsv1.2 \
  https://raw.githubusercontent.com/vivolution/vivolution-install/v0.3.0-rc4/install-edge.sh \
  | sudo sh -s -- --check-host-os
```

## Immutable release record

- Public release: `v0.3.0-rc4`
- Approved private source commit: `337f8717c72d4734e78195ac83a02828ab424738`
- Controller asset: `vivolution-controller-0.3.0-rc4.tar.gz`
- Controller asset SHA-256: `5e2d24d490defbac3da3f6792a6cfdee5c0bfbe39635a497f693b3b4bb80a5db`
- Edge asset: `vivolution-edge-enrollment-0.3.0-rc4.tar.gz`
- Edge asset SHA-256: `888f9cec11162930e99fd224345ca122d35476e7b803357b9155f7df2371ed9b`

Both assets are built from the same immutable private source commit but have
separate explicit reviewed allowlists. The release test proves that the Controller's
supported Edge digest, the Edge role's pinned digest, and the exact exported
Edge source digest are identical.

## Local release build

From this repository:

```sh
./scripts/build-release.sh "/path/to/Vivolution SBC"
```

The builder requires the approved source commit at `HEAD`, refuses changes in
either exported allowlist, rejects source links, exports deterministic separate
archives, and writes both entries to `dist/SHA256SUMS`.

Before publication:

```sh
shellcheck install.sh install-edge.sh scripts/build-release.sh \
  tests/test-release.sh tests/verify-published-ubuntu.sh
./scripts/build-release.sh "/path/to/Vivolution SBC"
./tests/test-release.sh "/path/to/Vivolution SBC"
```

After publication, run the live Ubuntu download/checksum verification:

```sh
./tests/verify-published-ubuntu.sh
```

Never publish placeholder release values, and never replace an existing release
asset or tag. Create a new immutable release candidate instead.
