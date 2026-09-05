locals {
  backups_root = abspath("${path.root}/backups")

  # One source of truth for memory: the map states the container ceiling, the
  # heap is computed from it. Setting both by hand is the classic way to ship a
  # server that runs fine for a week and then gets OOM-killed under load.
  #
  # Note the heap is sized so RSS lands just under the limit by design, so high
  # utilisation percentages here are expected, not a warning sign. The number
  # that matters is absolute slack, not percent.
  heap_mb = { for k, v in var.servers : k => v.memory_mb - var.jvm_overhead_mb }

  # Only running worlds get containers and routes. Volumes and RCON passwords
  # are keyed off the full map, so a stopped world keeps its data and its
  # identity -- and, critically, removing a container never plans a volume
  # destroy. prevent_destroy has to be a literal, so the guard cannot be
  # relaxed per-world; the fan-out must simply never ask to delete a volume.
  running = { for k, v in var.servers : k => v if v.state == "running" }

  # The routing table, rendered from the same map that defines the worlds. One
  # source of truth: a world cannot exist without a route, or keep a stale one.
  routes = { for k, v in local.running : "${k}.${var.world_domain}" => "mc-${k}:25565" }
}

resource "random_password" "rcon" {
  for_each = var.servers
  length   = 24
  special  = false
}

resource "docker_network" "mc" {
  name = "mc"
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
    name    = docker_network.mc.name
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
    "BACKUP_INTERVAL=${var.backup_interval}",
    "PRUNE_BACKUPS_DAYS=${var.backup_prune_days}",
    "INITIAL_DELAY=2m",
    "RCON_HOST=mc-${each.key}",
    "RCON_PASSWORD=${random_password.rcon[each.key].result}",
  ]

  volumes {
    volume_name    = docker_volume.world[each.key].name
    container_path = "/data"
    read_only      = true
  }

  # Backups are bind-mounted so you can see them in Finder. Low, sequential
  # I/O, so the VM boundary does not matter here the way it does for /data.
  volumes {
    host_path      = "${local.backups_root}/${each.key}"
    container_path = "/backups"
  }

  networks_advanced {
    name = docker_network.mc.name
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
    name = docker_network.mc.name
  }
}
