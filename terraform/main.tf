locals {
  # Hetzner exposes attached volumes at a deterministic path derived from the
  # volume ID. Computing it here (rather than reading it off the attachment)
  # keeps the server from depending on its own attachment, which would cycle.
  volume_device = "/dev/disk/by-id/scsi-0HC_Volume_${hcloud_volume.world.id}"
}

resource "random_password" "rcon" {
  length  = 24
  special = false
}

resource "hcloud_ssh_key" "admin" {
  name       = "${var.name}-admin"
  public_key = file(pathexpand(var.ssh_public_key_path))
}

# The world lives here and nowhere else. The server is disposable; this is not.
resource "hcloud_volume" "world" {
  name     = "${var.name}-world"
  size     = var.world_volume_size
  location = var.location
  format   = "ext4"

  lifecycle {
    prevent_destroy = true
  }
}

resource "hcloud_firewall" "mc" {
  name = "${var.name}-fw"

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = var.ssh_allowed_ips
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "25565"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction  = "in"
    protocol   = "icmp"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # RCON (25575) is deliberately absent. Reach it with `docker exec`, not the internet.
}

resource "hcloud_server" "mc" {
  name         = var.name
  server_type  = var.server_type
  location     = var.location
  image        = "ubuntu-24.04"
  ssh_keys     = [hcloud_ssh_key.admin.id]
  firewall_ids = [hcloud_firewall.mc.id]

  user_data = templatefile("${path.module}/cloud-init.yaml.tftpl", {
    volume_device     = local.volume_device
    mc_type           = var.mc_type
    mc_version        = var.mc_version
    mc_memory         = var.mc_memory
    mc_motd           = var.mc_motd
    mc_difficulty     = var.mc_difficulty
    mc_max_players    = var.mc_max_players
    mc_ops            = join(",", var.mc_ops)
    mc_whitelist      = join(",", var.mc_whitelist)
    rcon_password     = random_password.rcon.result
    backup_interval   = var.backup_interval
    backup_prune_days = var.backup_prune_days
  })

  # user_data changes force a rebuild, which is the intent: the box is cattle.
  # The world volume is untouched by that replacement.
}

resource "hcloud_volume_attachment" "world" {
  volume_id = hcloud_volume.world.id
  server_id = hcloud_server.mc.id
  automount = false # cloud-init handles mounting so the fstab entry survives reboots.
}
