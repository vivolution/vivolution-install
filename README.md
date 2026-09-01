# Vivolution verified installer bootstraps

This public repository contains small, auditable entry points for two separate
Ubuntu 24.04 artifacts:

- the Vivolution Turnkey Installer, whose currently enabled deployment role is
  one new standalone Controller Plane; and
- a compatibility enrollment-only Edge client/placeholder that is explicitly
  not presented as an SBC installer.

Each bootstrap downloads one versioned GitHub Release asset, enforces a size
ceiling, verifies its complete SHA-256 digest, rejects links and unexpected
archive layouts, and then runs the packaged installer from a private temporary
directory. The source repository may remain private because the release
builder exports only an explicit reviewed allowlist.

These release candidates are checksum-verified over GitHub HTTPS. They do not
yet have an independent detached publisher signature.

## 1. Vivolution Turnkey Installer

### Permanent latest-recommended command

Run this same command from a normal sudo-enabled account on every fresh Ubuntu
Server 24.04 LTS machine:

```sh
curl --fail --show-error --silent --location --proto '=https' --proto-redir '=https' --tlsv1.2 https://raw.githubusercontent.com/vivolution/vivolution-install/main/install.sh | sudo sh
```

The `main/install.sh` path is Vivolution's mutable **latest-recommended
channel**. It currently installs `v0.3.0-rc8`. Each approved release advances
this channel only after its exact version, source commit, asset name, and
SHA-256 digest have been updated and the release checks pass. The bootstrap
does not blindly execute an asset selected by the GitHub API: the channel
script still downloads one exact versioned archive and verifies its embedded
SHA-256 digest before running it.

### Version-pinned command

Use this form when a deployment must remain reproducible on one exact release:

```sh
curl --fail --show-error --silent --location --proto '=https' --proto-redir '=https' --tlsv1.2 https://raw.githubusercontent.com/vivolution/vivolution-install/v0.3.0-rc8/install.sh | sudo sh
```

The command opens this neutral menu:

```text
Vivolution Turnkey Installer

> Create a new Controller Plane
  Join an existing Controller Plane          [Unavailable]
  Deploy an Edge Appliance (SBC)             [Unavailable]
  Manage an existing installation
  Diagnostics / network readiness test
```

The menu uses Up/Down arrows on a capable terminal and a numbered fallback.
This beta can create **one standalone Controller Plane**, run non-mutating
diagnostics, inspect/create a redacted support bundle, resume/reconcile a
schema-5 installation, and discard only a proven pre-mutation incomplete run.
Controller joining/HA, full SBC/SIP/RTP/Teams/carrier deployment, legacy-state
deletion, and post-mutation uninstall remain unavailable.

### rc8 Ubuntu and Azure qualification corrections

rc8 incorporates four defects found by running the real installer on clean
Ubuntu hosts rather than relying only on static tests:

- it stops a package-replaced `systemd-timesyncd` process even when systemd
  reports the old unit as `LoadState=not-found` but still active;
- it keeps strict synchronized-clock checks without waiting for Chrony's
  initial frequency-skew estimate to converge after synchronization;
- it installs Ubuntu `runc` and pins the Controller Quadlet to that runtime so
  the enforced `containers-default` AppArmor profile and
  `NoNewPrivileges=true` work together instead of `crun` denying Gunicorn's
  loopback socket creation; and
- it verifies Caddy's official stable-repository primary key and immutable
  key-file SHA-256, pins exact Caddy `2.11.4`, and verifies the installed
  package, binary, and repository origin. Ubuntu Noble's Caddy `2.6.2`
  completed live ACME challenges but failed current Let's Encrypt production
  order finalization.

A clean Ubuntu 24.04.4 ARM64 UTM run passed through Controller activation to
the expected NAT-only public-certificate boundary. A separate disposable
Ubuntu 24.04 AMD64 Azure VM then completed rc8 from zero state: PostgreSQL,
PgBouncer, the runc/AppArmor Controller, session maintenance, production
Let's Encrypt certificates for both FQDNs, public recovery, reconcile, and a
full VM reboot all passed. Database and application ports remained loopback
only. This is standalone-Controller beta qualification, not HA, SBC, live-call,
or production qualification.

### Controller VM sizing

- **Enforced installer minimum:** 2 vCPU, 4 GiB RAM, and a 40 GB root disk.
- **Recommended for the current POC/test:** 2 vCPU, 8 GiB RAM, and a 64 GiB
  SSD-backed root disk. On Azure, use `Standard_D2as_v5` with a 64 GiB Premium
  SSD LRS OS disk.
- **Starting point for a production pilot:** 4 vCPU, 16 GiB RAM, and at least a
  128 GiB Premium SSD, followed by measurement-based resizing and off-VM
  backups.

Avoid burstable CPU SKUs for a Controller that will run continuously. This
standalone Controller hosts PostgreSQL, PgBouncer, Caddy, and the Controller
application on the same VM. The production-pilot figure is planning guidance,
not a claim that this prerelease is production-qualified.

### Controller addresses requested by the wizard

The installer is domain-neutral. It does not hard-code
`controller.voice.vivolution.ae` or any other customer/domain name. It asks for
two distinct DNS hostnames; enter hostnames only, without `https://` or a path:

- **Controller VM FQDN** — the unique address of this Controller VM, for
  example `node-a.cloudpremises.com`.
- **Controller shared FQDN** — the stable central address used by operators and
  every future Edge node, for example `controller.voice.vivolution.ae`,
  `probe.cloudpremises.com`, or `cp.cloudved.com`.

For a standalone Controller, both public DNS A records must resolve only to
this Ubuntu machine's declared public IPv4 address and neither name may publish
an AAAA record. Allow inbound TCP 22, 80, and 443. In a future qualified
multi-controller deployment, each Controller keeps its unique VM FQDN while
the shared FQDN remains stable in front of the Controller service.

### Public IPv4 and DNS recovery

The wizard queries three bounded HTTPS IPv4-echo sources, including
`https://ifconfig.me/ip`, compares their observations, warns on disagreement,
and asks the operator to confirm or override the inbound public address. An
egress/NAT observation is never silently assumed to be a load-balancer address.

Both names must resolve only to the confirmed IPv4 and must not publish AAAA.
If a record is absent, wrong, or still propagating, the wizard keeps the
validated answers and offers **Retry now**, **Wait and retry**, **Change
FQDN/public IPv4**, or **Exit safely and resume later**. Retries make a bounded
best-effort local resolver-cache flush and display direct Google DNS Toolbox
links. A local cache flush cannot accelerate authoritative propagation.

### Firewall ownership and SSH

The default is **Infrastructure-managed firewall**. In that mode the installer
does not install, enable, reset, or modify UFW; the Azure NSG, cloud firewall,
or on-premises firewall owns exposure. The alternative **Installer-managed
firewall** applies deny-by-default UFW, exposes TCP 80/443 publicly, and asks
for up to sixteen exact administrator IPv4 `/32` sources for SSH.

In installer-managed mode, when the active SSH client address is available
through `SSH_CONNECTION`, the wizard displays that exact `/32` as the default.
Additional trusted addresses may be comma-separated. `0.0.0.0/0` is
intentionally refused. In infrastructure-managed mode, the script publishes
the contract and leaves all host-firewall ownership untouched.

From the same non-root SSH shell, this prints the usual value to enter when
automatic detection is unavailable:

```sh
printf '%s\n' "$SSH_CONNECTION" | awk 'NF == 4 { print $1 "/32" }'
```

Current Controller network contract:

- inbound TCP 22: SSH, governed by the selected firewall owner;
- inbound TCP 80/443: Let's Encrypt HTTP validation, redirect, web/API;
- outbound TCP 80/443: repositories, GitHub/container downloads, ACME/status;
- outbound UDP/TCP 53: DNS; outbound UDP 123: NTP; and
- never expose TCP 5432, 6432, or 8000 publicly.

### Time synchronization and timezone

The operator selects a valid IANA timezone from a generated list—there is no
free-text timezone field. Chrony is installed and must synchronize before
Controller/database/ingress activation. Choose automatic Ubuntu/provider
sources or custom NTP server 1 plus optional server 2/additional sources. The
hardware clock and all durable application/audit timestamps remain UTC; the
selected host/display timezone is presentation context.

### Let's Encrypt certificates

The wizard asks for a **Let's Encrypt ACME contact email**, defaulting to the
validated Controller administrator email. The installer obtains exact Caddy
`2.11.4` from its verified official repository and configures exactly one
certificate issuer: the Let's Encrypt production ACME directory. It requests
public certificates for both the unique Controller VM FQDN and stable shared
FQDN, stores the managed keys under Caddy's protected service data directory,
redirects HTTP to HTTPS, and renews the certificates automatically.

There is no ZeroSSL or local/self-signed fallback in this Controller profile.
If public issuance is unavailable, the trusted HTTPS readiness checks fail the
installation instead of accepting an untrusted certificate. Before installing,
ensure both A records are fully propagated, remove stale/incorrect AAAA records,
make public TCP 80/443 reach this VM, and permit `letsencrypt.org` in any CAA
policy. rc8 requires a fresh host. It does not resume/delete a legacy schema-4
run or claim to convert certificates cached by an older installation.

Stock Ubuntu 24.04 normally exposes `/etc/os-release` as the canonical relative
symlink `../usr/lib/os-release`; the packaged check accepts that exact safe
layout. An interrupted compatible rc8 schema-5 run can be resumed with:

```sh
curl --fail --show-error --silent --location --proto '=https' --proto-redir '=https' --tlsv1.2 https://raw.githubusercontent.com/vivolution/vivolution-install/v0.3.0-rc8/install.sh | sudo sh -s -- resume
```

This automation covers the Controller web/API certificate only. Future SBC
certificates for Microsoft Teams Direct Routing and SIP trunks use a separate
certificate workflow and are not installed by this enrollment-only release.

### Logs, support bundle, and incomplete-run cleanup

rc8 stores root-only transaction state under `/var/lib/vivolution/installer`,
human/JSONL evidence under `/var/log/vivolution/installer`, and its stable
non-secret PID-bearing lock under `/run/vivolution/installer.lock`. Logs use
RFC 3339 UTC timestamps, severity plus AUDIT events, contextual IDs, bounded
rotation/output, and registered plus pattern-based redaction for authorization
headers, credential assignments/URLs, and private-key blocks. There is no
unredacted or shell-trace mode.

The support bundle is allowlist-based and excludes protected credential files.
**Discard incomplete deployment** is available only when the exact schema-5
ledger and ownership manifest prove that packages/services/system integration
never began. It previews the exact persistent files, holds the stable lock
through confirmation and deletion, and requires `DISCARD-INCOMPLETE`. The
PID-bearing `/run` lock intentionally remains until reboot for race safety;
persistent installer state/log objects in the displayed plan are removed.

## 2. Enrollment-only Edge client (not an SBC installer)

This command installs only the outbound Edge enrollment client/placeholder on
a separate fresh Ubuntu Server 24.04 LTS machine:

```sh
curl --fail --show-error --silent --location --proto '=https' --proto-redir '=https' --tlsv1.2 https://raw.githubusercontent.com/vivolution/vivolution-install/v0.3.0-rc8/install-edge.sh | sudo sh
```

It does **not** install or configure an SBC, SIP services, RTP/media, Microsoft
Teams Direct Routing, a carrier/Twilio trunk, firewall rules for voice, or a
working call path. It implements only the bounded provider-neutral enrollment
and fleet-visibility slice. Desired-state delivery, secrets, remote actions,
mTLS/client certificate issuance, and complete Controller management remain
later gates.

### Create the one-time grant first

After the Controller is installed:

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
  https://raw.githubusercontent.com/vivolution/vivolution-install/v0.3.0-rc8/install.sh \
  | sudo sh -s -- --verify-only

curl --fail --show-error --silent --location --proto '=https' --proto-redir '=https' --tlsv1.2 \
  https://raw.githubusercontent.com/vivolution/vivolution-install/v0.3.0-rc8/install-edge.sh \
  | sudo sh -s -- --verify-only
```

Both interactive bootstraps explicitly reopen `/dev/tty`; they fail clearly
without a controlling terminal instead of reading prompts from the exhausted
curl pipe.

On Ubuntu 24.04, these commands additionally exercise the packaged OS-metadata
compatibility check without creating installer state or installing packages:

```sh
curl --fail --show-error --silent --location --proto '=https' --proto-redir '=https' --tlsv1.2 \
  https://raw.githubusercontent.com/vivolution/vivolution-install/v0.3.0-rc8/install.sh \
  | sudo sh -s -- check-host-os

curl --fail --show-error --silent --location --proto '=https' --proto-redir '=https' --tlsv1.2 \
  https://raw.githubusercontent.com/vivolution/vivolution-install/v0.3.0-rc8/install-edge.sh \
  | sudo sh -s -- --check-host-os
```

## Immutable release record

- Public release: `v0.3.0-rc8`
- Approved private source commit: `e8a8a7cf35f8693f8f7750abf9a4c20b883b539a`
- Controller asset: `vivolution-controller-0.3.0-rc8.tar.gz`
- Controller asset SHA-256: `996aebaaed63efeab957c6d80f0fa5789da0cba3bab0b0e6757b630fbe788f84`
- Edge asset: `vivolution-edge-enrollment-0.3.0-rc8.tar.gz`
- Edge asset SHA-256: `13b31839e8c43856afd77239e30df67abd3e808bdfdf097f9a5bd51538a684de`

Both assets are built from the same immutable private source commit but have
separate explicit reviewed allowlists. The release test proves that the
Controller's supported Edge digest, the Edge role's pinned digest, and the
exact exported Edge source digest are identical.

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
