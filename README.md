# Game Server Factory

Terraform-provisioned game servers. Starting with Minecraft, one box at a time.

## Roadmap

- **v0 — one server, hardcoded.** *(current)* One VM, one persistent volume, one
  container. The world survives server replacement.
- **v1 — the factory shape.** Extract a `minecraft_server` module, drive it with
  `for_each`, put `mc-router` in front so many worlds share port 25565 by
  subdomain. Ship backups off-box.
- **v2 — control plane.** Terraform owns the host fleet only; a separate service
  reconciles which servers exist from a database.
- **v3 — self-serve.** Auth, web UI, RCON console, scale-to-zero on idle.

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
