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

Run this from a normal sudo-enabled account on a fresh Ubuntu Server 24.04 LTS
machine:

```sh
curl --fail --show-error --silent --location --proto '=https' --tlsv1.2 https://raw.githubusercontent.com/vivolution/vivolution-install/v0.3.0-rc2/install.sh | sudo sh
```

This command installs **standalone CP1 only**. CP2, CP3, automatic controller
failover, the SBC voice data plane, Microsoft Teams, and SIP carriers are not
silently installed.

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
machine's declared public IPv4 address. Allow inbound TCP 22, 80, and 443. In a
future qualified multi-controller deployment, each Controller keeps its unique
VM FQDN while the shared FQDN remains stable in front of the Controller service.

## 2. Enrollment-only Edge client (not an SBC installer)

This command installs only the outbound Edge enrollment client/placeholder on
a separate fresh Ubuntu Server 24.04 LTS machine:

```sh
curl --fail --show-error --silent --location --proto '=https' --tlsv1.2 https://raw.githubusercontent.com/vivolution/vivolution-install/v0.3.0-rc2/install-edge.sh | sudo sh
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
curl --fail --show-error --silent --location --proto '=https' --tlsv1.2 \
  https://raw.githubusercontent.com/vivolution/vivolution-install/v0.3.0-rc2/install.sh \
  | sudo sh -s -- --verify-only

curl --fail --show-error --silent --location --proto '=https' --tlsv1.2 \
  https://raw.githubusercontent.com/vivolution/vivolution-install/v0.3.0-rc2/install-edge.sh \
  | sudo sh -s -- --verify-only
```

Both interactive bootstraps explicitly reopen `/dev/tty`; they fail clearly
without a controlling terminal instead of reading prompts from the exhausted
curl pipe.

## Immutable release record

- Public release: `v0.3.0-rc2`
- Approved private source commit: `d0dd678c75cf8fc5f61f03614e092d70c15e2494`
- Controller asset: `vivolution-controller-0.3.0-rc2.tar.gz`
- Controller asset SHA-256: `3896506c93f5241be39d137705118bbed5738ca9ff1c432c8fef21376687d01a`
- Edge asset: `vivolution-edge-enrollment-0.3.0-rc2.tar.gz`
- Edge asset SHA-256: `75bf36f88e85106bf51f8122a68b0626f829f834b7c438c86a30218c059f6700`

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
