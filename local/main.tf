locals {
  backups_root = abspath("${path.root}/backups")
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
  for_each = var.servers

  name                  = "mc-${each.key}"
  image                 = docker_image.mc.image_id
  restart               = "unless-stopped"
  stdin_open            = true
  tty                   = true
  destroy_grace_seconds = 120

  env = [
    "EULA=TRUE",
    "TYPE=${each.value.type}",
    "VERSION=${each.value.version}",
    "MEMORY=${each.value.memory}",
    "USE_AIKAR_FLAGS=true",
    "MOTD=${each.value.motd}",
    "DIFFICULTY=${each.value.difficulty}",
    "OPS=${join(",", each.value.ops)}",
    "ENABLE_RCON=true",
    "RCON_PASSWORD=${random_password.rcon[each.key].result}",
    "TZ=UTC",
  ]

  # Direct port too, so you can connect without touching /etc/hosts.
  ports {
    internal = 25565
    external = each.value.port
  }

  volumes {
    volume_name    = docker_volume.world[each.key].name
    container_path = "/data"
  }

  networks_advanced {
    name    = docker_network.mc.name
    aliases = ["mc-${each.key}"]
  }
}

resource "docker_container" "backup" {
  for_each = var.servers

  name    = "mc-${each.key}-backup"
  image   = docker_image.backup.image_id
  restart = "unless-stopped"

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

  # Terraform already knows every world, so it renders the routing table
  # directly. The alternative -- --in-docker label discovery -- needs the Docker
  # socket mounted into the container, which means running it as root. Not worth
  # the privilege for a table we can generate deterministically.
  command = [
    "--mapping",
    join(",", [for k, v in var.servers : "${k}.mc.localhost=mc-${k}:25565"]),
  ]

  ports {
    internal = 25565
    external = 25565
  }

  networks_advanced {
    name = docker_network.mc.name
  }
}
