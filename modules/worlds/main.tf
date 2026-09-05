# The product: worlds, their sidecars, and the router that fronts them.
#
# Deliberately knows nothing about *where* its Docker daemon is. The caller
# configures the provider -- a local socket, or ssh://root@host for a real
# machine -- and the same definitions apply either way. That is what makes the
# local stack and the cloud stack the same code rather than two dialects.

locals {
  heap_mb = { for k, v in var.servers : k => v.memory_mb - var.jvm_overhead_mb }

  running = { for k, v in var.servers : k => v if v.state == "running" }

  routes = { for k, v in local.running : "${k}.${var.world_domain}" => "mc-${k}:25565" }
}

resource "random_password" "rcon" {
  for_each = var.servers
  length   = 24
  special  = false
}

# One repository password for all worlds. Restic encrypts client-side, so this
# is the only thing standing between the bucket and readable player data --
# which is exactly why backups going off-box want restic rather than raw tar.
resource "random_password" "restic" {
  length  = 32
  special = false
}


resource "docker_image" "mc" {
  name = "itzg/minecraft-server:latest"
}

resource "docker_image" "backup" {
  name = "itzg/mc-backup:latest"
}

resource "docker_image" "router" {
  name = "itzg/mc-router:latest"
}

# World data lives in named volumes, not bind mounts. Bind mounts cross the
# macOS/Linux VM boundary and chunk I/O is slow enough to cause tick lag.
resource "docker_volume" "world" {
  for_each = var.servers
  name     = "mc-${each.key}-data"

  lifecycle {
    prevent_destroy = true
  }
}

resource "docker_container" "mc" {
  for_each = local.running

  name                  = "mc-${each.key}"
  image                 = docker_image.mc.image_id
  restart               = "unless-stopped"
  stdin_open            = true
  tty                   = true
  destroy_grace_seconds = 120

  # Memory is a hard ceiling: it is the scarce, non-shareable resource, and it
  # is what a host actually sells. memory_swap set equal to memory disables swap
  # entirely -- a swapping Minecraft server does not slow down gracefully, it
  # stutters, because the tick loop cannot wait on disk.
  memory      = each.value.memory_mb
  memory_swap = each.value.memory_mb

  # CPU is a *weight*, not a cap. A hard quota would throttle the tick loop and
  # show up as lag even when the host is idle. Shares only matter under
  # contention, which is exactly when you want fairness.
  cpu_shares = each.value.cpu_shares

  env = [
    "EULA=TRUE",
    "TYPE=${each.value.type}",
    "VERSION=${each.value.version}",
    "MEMORY=${local.heap_mb[each.key]}M",
    "USE_AIKAR_FLAGS=true",
    "MOTD=${each.value.motd}",
    "MODE=${each.value.gamemode}",
    "DIFFICULTY=${each.value.difficulty}",
    "OPS=${join(",", each.value.ops)}",
    "ENABLE_RCON=true",
    "RCON_PASSWORD=${random_password.rcon[each.key].result}",
    "TZ=UTC",
  ]

  # Published only when the map asks for it. Most worlds should not be: every
  # published port is exposed surface that the router already covers.
  dynamic "ports" {
    for_each = each.value.port == null ? [] : [each.value.port]
    content {
      internal = 25565
      external = ports.value
    }
  }

  volumes {
    volume_name    = docker_volume.world[each.key].name
    container_path = "/data"
  }

  networks_advanced {
    name    = var.network_name
    aliases = ["mc-${each.key}"]
  }

  lifecycle {
    precondition {
      condition     = each.value.memory_mb >= var.jvm_overhead_mb + 512
      error_message = "World '${each.key}': memory_mb (${each.value.memory_mb}) leaves less than 512 MB of heap after the ${var.jvm_overhead_mb} MB JVM reserve. Raise memory_mb."
    }
  }
}

resource "docker_container" "backup" {
  for_each = local.running

  name    = "mc-${each.key}-backup"
  image   = docker_image.backup.image_id
  restart = "unless-stopped"

  memory      = 256
  memory_swap = 256

  env = [
    "BACKUP_METHOD=restic",
    "BACKUP_INTERVAL=${var.backup_interval}",
    "INITIAL_DELAY=${var.backup_initial_delay}",
    "PRUNE_RESTIC_RETENTION=--keep-daily 7 --keep-weekly 4",

    # One repository per world, so retention and restore are per-world and a
    # corrupt repo cannot take every world down with it.
    "RESTIC_REPOSITORY=s3:${var.backup_s3.endpoint}/${var.backup_s3.bucket}/${each.key}",
    "RESTIC_PASSWORD=${random_password.restic.result}",
    "AWS_ACCESS_KEY_ID=${var.backup_s3.access_key}",
    "AWS_SECRET_ACCESS_KEY=${var.backup_s3.secret_key}",

    "RCON_HOST=mc-${each.key}",
    "RCON_PASSWORD=${random_password.rcon[each.key].result}",
  ]

  volumes {
    volume_name    = docker_volume.world[each.key].name
    container_path = "/data"
    read_only      = true
  }

  networks_advanced {
    name = var.network_name
  }

  depends_on = [docker_container.mc]
}

resource "docker_container" "router" {
  name    = "mc-router"
  image   = docker_image.router.image_id
  restart = "unless-stopped"

  # Small, but it must never be the thing that gets squeezed -- if the router
  # dies every world becomes unreachable at once.
  memory      = 128
  memory_swap = 128

  # Terraform already knows every world, so it renders the routing table
  # directly. The alternative -- --in-docker label discovery -- needs the Docker
  # socket mounted into the container, which means running it as root. Not worth
  # the privilege for a table we can generate deterministically.
  command = [
    "--mapping",
    join(",", [for host, backend in local.routes : "${host}=${backend}"]),
  ]

  ports {
    internal = 25565
    external = 25565
  }

  networks_advanced {
    name = var.network_name
  }
}
