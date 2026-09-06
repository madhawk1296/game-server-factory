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
- **v3 -- adopt a control panel, do not build one.** Pelican Panel already is
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

### Operating the cloud host

The two roots tear down in reverse order, and the order matters:

```bash
cd cloud/worlds && terraform destroy   # stops containers gracefully first
cd ../host      && terraform destroy   # then the machine
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
cd cloud/worlds && terraform destroy
cd ../host      && terraform destroy -target=digitalocean_droplet.host
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

`--full` deliberately mutates: it replaces smp's container to prove the world
survives, and edits `variables.tf` to stop and restart creative, restoring the
file afterwards via a trap. Do not run it while anyone is playing.

What it cannot check is the part that needs a human: that two clients on two
worlds genuinely cannot see each other, and that the routed hostnames work in
the real launcher rather than only in the protocol prober. For that:

```bash
echo "$(cd local && terraform output -raw etc_hosts_line)" | sudo tee -a /etc/hosts
```

Then add both `smp.mc.localhost` and `creative.mc.localhost` in Minecraft --
no port -- and confirm you arrive in different worlds with separate inventories.

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
