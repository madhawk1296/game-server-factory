# Game Server Factory

Terraform-provisioned game servers. Starting with Minecraft, one box at a time.

## Roadmap

Each step is pulled by a need, not pushed by a checklist. The trigger matters
more than the feature list.

- **v0 -- one world, proven disposable.** *(done)* One world, one volume, one
  container; the world survives its server being destroyed. Verified by
  replacing the container with an unsaved block in the world, and later by
  destroying and rebuilding an entire cloud host.
- **v1 -- the factory.** *(done)* N worlds from a map on one box: hard memory
  limits with the heap derived from the ceiling, hostname multiplexing proven at
  N>1 on a single port, published ports optional and validated as allocations,
  running/stopped lifecycle with a deliberate path to deletion, and encrypted
  deduplicated backups with a verified restore. 28 acceptance checks in
  local/test.sh.
- **v2 -- cloud and multi-host.** *(done, as scoped)* One DigitalOcean droplet
  running the same module as local, at smp.cheapminecraftservers.com. Reserved
  IP so the address outlives the machine, a single wildcard DNS record so adding
  a world never touches DNS, monitoring, and a boot path verified by destroying
  and rebuilding the real host. Backups, remote state, and a second host were
  deliberately dropped.
- **v3 -- adopt a control panel, do not build one.** *(in progress: panel, node,
  and migration done)* Pelican Panel already is
  this product: accounts, server creation, resource limits, browser console,
  file manager, SFTP, backups, multi-node scheduling. Free, open source, and
  what a large share of independent hosts actually run. Writing our own would
  take months to reach parity and would not be a competitive advantage.

  The split becomes: Terraform provisions nodes, Pelican schedules onto them.
  That retires modules/worlds, since two systems cannot both manage containers
  on one Docker daemon. Not waste -- building it is why the trade-offs Pelican
  makes are legible rather than magic.

  *Trigger: wanting customers rather than friends.*
- **v4 -- billing and signup.** Pelican covers accounts, consoles, and server
  creation, so what is left is taking money and provisioning on payment.
  Paymenter is the open-source billing panel built for exactly this and
  integrates with Pelican; WHMCS is the paid incumbent. Same reasoning as v3 --
  this is solved software, not a differentiator.
  *Trigger: strangers, and money.*

Cloud deliberately does not appear until v2: putting one world on a VM is a
deployment target, not an idea.

## Running locally first

`local/` runs the same architecture on your Mac via the Terraform Docker
provider. No cloud account, no cost, real `terraform plan`/`apply`/state.

```bash
cd local
terraform init
terraform apply
```

It brings up `mc-router` on 25565 plus one world, each with a backup sidecar.
Adding a second world is one entry in `var.servers` -- which is the v1 factory
shape, built for free.

```hcl
servers = {
  smp      = { port = 25566 }
  creative = { port = 25567, memory = "3G", difficulty = "peaceful" }
}
```

Connect directly at `localhost:25566`, or through the router at
`smp.mc.localhost` after adding it to `/etc/hosts`:

```
127.0.0.1  smp.mc.localhost creative.mc.localhost
```

### Provisioning, end to end

An order placed in Paymenter creates a Pelican user, a server, an allocation,
installs the game and starts it -- verified by placing an admin order and
connecting to the result from the internet. No payment gateway is involved in
that path, which is why it could be tested before Stripe existed.

Getting there found six faults, each of which would have reached the first
paying customer:

1. **Disk exhaustion.** The node had 15 GB and the existing server reserved 10 GB
   while using 18 MB, so a 10 GB plan could not deploy. Memory was fine; disk was
   the binding constraint, and the error said only "node is not suitable".
2. **Stale allocations.** Mothballing changed the reserved IP, but allocation
   records still named the old address. DNS was managed in code and updated
   itself; the allocation table was not, and did not. Allocations should be
   created on 0.0.0.0, which binds whatever the host currently has.
3. **Allocation hoarding.** All eleven ports were bound to the first server, so
   provisioning had nothing free and fell back to a stale record.
4. **EULA not accepted.** The egg writes eula.txt but does not agree to it, so
   every provisioned server starts and immediately exits.
5. **MaxRAMPercentage=95 in the egg.** Fixed once by hand on a single server,
   which fixed nothing -- every new server inherited 95 again. Configuration
   belongs at the template, not the instance.
6. **Firewall only allowed 25565.** The allocation pool spanned 25565-25575, so
   ten of eleven ports would provision cleanly and then be unreachable.

Four of the six were invisible until a server was actually created and connected
to. Reading the code would not have surfaced any of them.

### Pricing

Four plans, all Paper on node-1 with daily backups kept 7 days:

| Plan | RAM | Disk | Monthly | Yearly | $/GB |
|---|---|---|---|---|---|
| Dirt | 2 GB | 10 GB | $6 | $61.20 | 3.00 |
| Iron | 4 GB | 20 GB | $10 | $102.00 | 2.50 |
| Diamond | 8 GB | 40 GB | $18 | $183.60 | 2.25 |
| Netherite | 12 GB | 60 GB | $26 | $265.20 | 2.17 |

Priced against the market rather than against the bill, because the bill cannot
be covered here. The droplet costs $51/month and yields about 4.8 GB of sellable
memory once the panel, Paymenter, MariaDB, Redis, Wings and the OS are
subtracted -- roughly **$10.60 per sellable GB** against a market rate of
$2-5/GB. There is no price that both covers this box and sells.

A 64 GB dedicated server at around $115/month leaves ~54 GB sellable, or about
$2.13/GB, at which these same prices carry margin and break even near 60%
occupancy. So the box is the proving ground; the move to bare metal is what
makes the numbers work, and it should happen before the losses scale with
success rather than after.

### Paymenter

The storefront. Reached at the apex over HTTPS; the same hostname on 25565 is
the flagship game server.

Two things that are not obvious:

**Paymenter keeps its URL in the database, not the environment.** APP_URL only
seeds an initial value, and on first boot the seeder wrote the framework default
`http://localhost` regardless -- so every generated link, including the login
redirect, pointed at localhost while `printenv` and `env()` both looked correct.
Fixed in the `settings` table under key `app_url`. Worth checking there first
whenever a URL looks wrong, rather than in the container environment.

**There is no web installer.** Migrations run on first boot and setup happens at
/admin, which is Filament. The admin user comes from
`php artisan app:user:create <first> <last> <email> <password> <role_id>` --
role_id is an integer, so passing "admin" fails on an integer column.

### Backups

Backups go to object storage via restic -- deduplicated, encrypted client-side,
one repository per world so retention and restore are per-world and a corrupt
repo cannot take everything down with it.

With `backup_s3` unset, the stack runs a local MinIO as the S3 target. Be clear
about what that does and does not prove: MinIO here sits on the same Mac as the
world volumes, so it is **not** off-box durability. What it buys is a fully
exercised S3 path -- bucket creation, credentials, repo init, upload, retention,
restore -- so switching to real storage is a config change rather than a block
of untested config:

```hcl
backup_s3 = {
  endpoint   = "https://<account>.r2.cloudflarestorage.com"
  bucket     = "mc-backups"
  access_key = "..."
  secret_key = "..."
}
```

Setting it drops MinIO from the stack entirely and points restic at the real
thing. Cloudflare R2 is the natural target -- S3-compatible, and no egress fees,
which matters on the day you actually restore.

**The restic password is the single point of failure.** Restic encrypts before
anything leaves the host, so the password is all that stands between the bucket
and readable player data -- and equally, losing it makes every backup
permanently unreadable. Terraform generates it into local state, which means
*your state file is now a credential*. Before relying on this, either back up
the state or pin the password somewhere you control.

```bash
cd local
terraform output -raw restic_password          # save this somewhere safe

docker exec mc-smp-backup restic snapshots     # what exists
docker exec mc-smp-backup restic restore latest --target /tmp/r
```

Restore has been tested, not assumed: a snapshot restored 401 files including
`level.dat` and the region files. An untested backup is not a backup.

### Provisioning, end to end

An order placed in Paymenter creates a Pelican user, a server, an allocation,
installs the game and starts it -- verified by placing an admin order and
connecting to the result from the internet. No payment gateway is involved in
that path, which is why it could be tested before Stripe existed.

Getting there found six faults, each of which would have reached the first
paying customer:

1. **Disk exhaustion.** The node had 15 GB and the existing server reserved 10 GB
   while using 18 MB, so a 10 GB plan could not deploy. Memory was fine; disk was
   the binding constraint, and the error said only "node is not suitable".
2. **Stale allocations.** Mothballing changed the reserved IP, but allocation
   records still named the old address. DNS was managed in code and updated
   itself; the allocation table was not, and did not. Allocations should be
   created on 0.0.0.0, which binds whatever the host currently has.
3. **Allocation hoarding.** All eleven ports were bound to the first server, so
   provisioning had nothing free and fell back to a stale record.
4. **EULA not accepted.** The egg writes eula.txt but does not agree to it, so
   every provisioned server starts and immediately exits.
5. **MaxRAMPercentage=95 in the egg.** Fixed once by hand on a single server,
   which fixed nothing -- every new server inherited 95 again. Configuration
   belongs at the template, not the instance.
6. **Firewall only allowed 25565.** The allocation pool spanned 25565-25575, so
   ten of eleven ports would provision cleanly and then be unreachable.

Four of the six were invisible until a server was actually created and connected
to. Reading the code would not have surfaced any of them.

### Pricing

Four plans, all Paper on node-1 with daily backups kept 7 days:

| Plan | RAM | Disk | Monthly | Yearly | $/GB |
|---|---|---|---|---|---|
| Dirt | 2 GB | 10 GB | $6 | $61.20 | 3.00 |
| Iron | 4 GB | 20 GB | $10 | $102.00 | 2.50 |
| Diamond | 8 GB | 40 GB | $18 | $183.60 | 2.25 |
| Netherite | 12 GB | 60 GB | $26 | $265.20 | 2.17 |

Priced against the market rather than against the bill, because the bill cannot
be covered here. The droplet costs $51/month and yields about 4.8 GB of sellable
memory once the panel, Paymenter, MariaDB, Redis, Wings and the OS are
subtracted -- roughly **$10.60 per sellable GB** against a market rate of
$2-5/GB. There is no price that both covers this box and sells.

A 64 GB dedicated server at around $115/month leaves ~54 GB sellable, or about
$2.13/GB, at which these same prices carry margin and break even near 60%
occupancy. So the box is the proving ground; the move to bare metal is what
makes the numbers work, and it should happen before the losses scale with
success rather than after.

### Paymenter

The storefront. Reached at the apex over HTTPS; the same hostname on 25565 is
the flagship game server.

Two things that are not obvious:

**Paymenter keeps its URL in the database, not the environment.** APP_URL only
seeds an initial value, and on first boot the seeder wrote the framework default
`http://localhost` regardless -- so every generated link, including the login
redirect, pointed at localhost while `printenv` and `env()` both looked correct.
Fixed in the `settings` table under key `app_url`. Worth checking there first
whenever a URL looks wrong, rather than in the container environment.

**There is no web installer.** Migrations run on first boot and setup happens at
/admin, which is Filament. The admin user comes from
`php artisan app:user:create <first> <last> <email> <password> <role_id>` --
role_id is an integer, so passing "admin" fails on an integer column.

### Backups

Backups go to Cloudflare R2 over the S3 API. Wings uploads directly from the
node using a presigned URL, so backup data never transits the panel and each
node talks to object storage on its own.

R2 rather than DigitalOcean Spaces deliberately: backups should not share a
failure domain with the thing they protect. A DO incident, or an account
suspension over some customer's server, would otherwise take the node and every
backup together. R2 is free under 10 GB -- roughly the first four customers --
and has no egress charges, which matters because you pay to restore on the day
you are already having a bad one.

Configuration lives in Pelican, not Terraform:

- Backup host `R2`, schema `s3`, attached to the node rather than to a server,
  so every server on it inherits the setting. There is no per-server field to
  forget when provisioning.
- Per-server `backup_limit` of 7, with a daily schedule at 04:00. Daily-keep-7
  beats hourly-keep-3 for Minecraft: the disaster is "griefed last night", so
  you want yesterday rather than fine granularity and nothing older.
- Verified by triggering one and confirming it left the box -- Wings logs an
  s3 multipart upload and /var/lib/pelican/backups stays empty. A backup that
  lands locally looks identical in the panel.

Two things measured while setting this up. Pelican sizes the container above the
memory you sell, by a tiered overhead -- 10% at 3072 MB, 5% at 5120 -- so a
3 GB plan gets a 3379 MB container. And Pelican starts the JVM with Xms128M and
lets the heap grow, rather than committing it at boot, so idle servers cost a
fraction of their allocation.

### Layout

```
cloud/host     the node: droplet, volume, firewall, reserved IP, DNS, cloud-init
cloud/panel    Pelican Panel as a container
cloud/billing  Paymenter, MariaDB and Redis -- the storefront
modules/worlds local development only -- superseded on the cloud by Pelican
local          the local stack, still useful as a sandbox
```

One host serves three things on three ports, all behind the panel's Caddy:

```
cheapminecraftservers.com        :443    the shop
cheapminecraftservers.com        :25565  the flagship game server
panel.cheapminecraftservers.com  :443    Pelican
node.cheapminecraftservers.com   :443    Wings, proxied
```

The apex answering as both a website and a Minecraft server is not a trick --
they are different ports, and a client only ever tries one of them.

Terraform provisions nodes; Pelican schedules game servers onto them. The
pre-migration world is retained on the node in three places -- the mc-smp-data
volume, a staged copy under /mnt/docker/migration, and live under Pelican --
until the migration has been trusted for long enough to prune the first two.

### Pelican

The cloud node runs Pelican: the panel at panel.cheapminecraftservers.com, Wings
on the host, and game servers created through the panel rather than Terraform.
Terraform still owns the node itself -- droplet, volume, firewall, reserved IP,
DNS, Docker, Wings, and the panel container.

Four things that cost time when migrating onto it:

**Allocations cannot use the reserved IP.** DigitalOcean routes a reserved IP to
the droplet's anchor address rather than configuring it on eth0, so no process
can bind it -- Docker fails with "cannot assign requested address". Use 0.0.0.0
with a display alias. The droplet's own address would work today and break on
the next rebuild, which is the fragility the reserved IP exists to prevent.

**Server files must be owned by 997:986**, the host's pelican user, which is what
Wings runs containers as. Not root, and not the image's own default uid.

**The Paper egg ships MaxRAMPercentage=95.** On a 5 GB server that leaves ~256 MB
for a JVM whose non-heap overhead measured 400-700 MB on this workload. 80 is
the number that matches what was measured. The default is fine on large servers
where 5% is still a gigabyte; it is small servers where the percentage model
breaks, because overhead does not shrink proportionally.

**Memory behaves differently than it did under Terraform.** Pelican starts the
JVM with Xms128M and lets the heap grow, where the previous setup used Aikar
flags with Xms=Xmx and committed everything at boot. Idle servers now sit near
900 MB rather than their full allocation, which is what makes the node's
overallocate percentage a usable strategy rather than a gamble.

The panel shows a suggested Wings config that does not match what is deployed:
it assumes Wings terminates its own TLS, whereas here Caddy terminates for both
hostnames and proxies to Wings on 8080. Do not use "Auto Deploy Command" -- it
would overwrite the working config with one pointing at certificates that do not
exist.

### Operating the cloud host

The two roots tear down in reverse order, and the order matters:

```bash
# Stop the game containers gracefully. NOT `terraform destroy` on this root --
# that tries to delete the world volumes too, hits prevent_destroy, and aborts
# before stopping anything.
cd cloud/worlds
terraform destroy -auto-approve \
  -target='module.worlds.docker_container.mc' \
  -target='module.worlds.docker_container.backup'

cd ../host && terraform destroy        # then the machine
```

Destroying the host while worlds are still deployed is a hard power-off for
everything on it. Paper never receives SIGTERM, never flushes, and anything
since its last autosave (~5 minutes by default) is gone. The world directory
itself survives -- it lives on the block volume -- but in-memory state does not.
`destroy_grace_seconds` only applies when Terraform destroys the *container*;
the host root has no idea containers exist.

The same bound applies to any unplanned host loss, which no ordering protects
against. With backups disabled, ~5 minutes is the exposure.

**Mothballing.** Destroying just the droplet keeps the volume and the reserved
IP, dropping cost from ~$50/month to a few dollars:

```bash
cd cloud/worlds
terraform destroy -auto-approve -target='module.worlds.docker_container.mc' \
                                -target='module.worlds.docker_container.backup'
cd ../host && terraform destroy -target=digitalocean_droplet.host
```

`terraform apply` in both brings it back in about three minutes with the same
world and the same address -- DNS needs no change, because the reserved IP
belongs to the account rather than the machine.

**Verified by rebuilding the real host:** the volume reattached to a brand-new
droplet with the world intact, the reserved IP did not move so DNS needed no
update, and after a reboot the volume remounted from fstab, Docker came up on
the right data-root, and the containers restarted on their own.

### Testing

```bash
cd local
./test.sh          # 21 non-destructive checks
./test.sh --full   # 28 checks, including a container replace and a stop/start cycle
```

The suite is self-contained -- it places its own world marker and waits for the
first backup rather than assuming a long-lived stack -- so it runs against a
freshly created environment as happily as an established one.

**CI** (`.github/workflows/ci.yml`) runs two jobs on every push:

- **static** -- `terraform fmt -check` and `validate` across all five roots,
  including the cloud ones. Those can only be validated, never applied: an apply
  would need credentials and would create billable infrastructure per push.
- **acceptance suite** -- stands the local stack up on real Docker inside the
  runner and runs the same 21 checks. Isolation, hostname routing, enforced
  memory limits, and a restored backup, verified on every change rather than
  when someone notices.

CI uses `local/ci.tfvars`: two 1536 MB worlds instead of 3072 and 2048, because
runners have about 7 GB. 1536 is close to the floor the module's own
precondition allows -- `memory_mb` must exceed `jvm_overhead_mb` by 512 -- which
leaves a 768 MB heap, enough for Paper to boot with nobody on it.

### World lifecycle and decommissioning

A world has a `state`, and it is not the same thing as existing:

```hcl
creative = { state = "stopped", memory_mb = 2048 }
```

`stopped` destroys the container and its backup sidecar, frees the memory, and
drops the route -- while keeping the volume, the RCON password, and the map
entry. The world still exists; it is not running. Flip it back to `running` and
it returns with its data intact.

This is the mothballing mode, and on the cloud it is what takes a world's cost
down to just its volume.

**Deleting a world is deliberately not a config edit.** The volume carries
`lifecycle.prevent_destroy`, which Terraform requires to be a literal -- it
cannot be relaxed per-world. So removing a map entry outright does not delete a
world, it aborts the entire plan, including unrelated changes to every other
world. That is the guard working, not a bug.

To actually retire a world, in this order:

```bash
# 1. While it is still RUNNING, take a final backup and get it off the host.
docker exec -i mc-<name> rcon-cli save-all
cp local/backups/<name>/*.tar.gz ~/somewhere-safe/

# 2. Stop it, and leave it stopped long enough to be sure nobody wants it.
#    state = "stopped" in the map, then apply.

# 3. Tell Terraform to forget the volume. Nothing is deleted by this.
terraform state rm 'docker_volume.world["<name>"]'

# 4. Now remove the map entry and apply. Clean, because the volume is no
#    longer in state, so no destroy is planned.

# 5. Finally, delete the data for real.
docker volume rm mc-<name>-data
```

Step 1 comes first because the backup sidecar is torn down by step 2 -- once a
world is stopped, nothing is taking backups of it any more.

Steps 3 and 5 each name the world explicitly on the command line. That friction
is the point: destroying player data should take two deliberate commands, never
be a side effect of editing a map.

### What carries over to the cloud

Everything that matters, as it turns out: the `for_each` factory pattern, the
`mc-router` hostname multiplexing, the container env and JVM tuning, the backup
sidecar, and the volume-outlives-the-server discipline. What does not carry over
is the cloud plumbing -- server, block volume, firewall, cloud-init -- which is
maybe 80 lines.

### Limits worth knowing

- Docker Desktop's VM gets a slice of your RAM, not all of it. Check
  Settings -> Resources before adding worlds.
- Your Mac has to stay awake and online. `caffeinate -s` helps; a closed lid does not.
- Residential upload is the usual bottleneck once several people are on.
- World volumes are marked `prevent_destroy`, same as the cloud stack, so
  `terraform destroy` fails on purpose.

## v0

### What it builds

A Hetzner CX33 (4 vCPU / 8 GB x86, €8.49/mo ex-VAT) running `itzg/minecraft-server` and
`itzg/mc-backup` under Docker Compose, with world data on a separate block volume.

The volume is the point. The server is cattle — replacing it is routine and
takes about 90 seconds. The volume is marked `prevent_destroy` and is the only
thing here holding state.

### Prerequisites

- A Hetzner Cloud project and an API token
- An SSH keypair at `~/.ssh/id_ed25519.pub`
- Terraform >= 1.6

### Run it

```bash
export HCLOUD_TOKEN=your-token-here
cd terraform
cp terraform.tfvars.example terraform.tfvars   # edit mc_ops at minimum
terraform init
terraform apply
```

First boot takes 2–4 minutes: cloud-init installs Docker, mounts the volume,
then the container downloads the server jar and generates the world. Watch it:

```bash
ssh root@$(terraform output -raw server_ip) 'docker logs -f mc'
```

### The test that matters

Join the server, place a block, then replace the machine underneath it:

```bash
terraform apply -replace=hcloud_server.mc
```

New server, new IP, same world. If that works, the state boundary is right and
everything in v1 gets easier.

### Operating it

```bash
ssh root@<ip>

docker exec -i mc rcon-cli          # server console
docker logs -f mc                   # live log
ls -la /mnt/minecraft/backups       # tarballs, every 2h, pruned at 7 days
```

### Known gaps at v0

- **Backups are on the same host.** `mc-backup` protects against griefing and bad
  chunks, not volume loss. Pushing to object storage is a v1 item.
- **No DNS.** You connect by IP. A name only becomes load-bearing at v1, when
  `mc-router` needs the hostname to decide which world you meant.
- **Local state.** Fine for one person on one laptop; move it before that changes.
- **RCON password lives in cloud-init**, which is readable from the Hetzner
  console. Acceptable at v0, worth fixing when there's a real secret store.

### Tearing down

`terraform destroy` will fail on purpose — the volume has `prevent_destroy`.
Drop that lifecycle block first, and understand you're deleting the world.
