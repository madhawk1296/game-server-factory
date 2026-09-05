locals {
  # DigitalOcean exposes attached volumes at a deterministic path derived from
  # the volume name, so the droplet does not have to depend on its own
  # attachment -- which would cycle.
  volume_device = "/dev/disk/by-id/scsi-0DO_Volume_${var.name}-data"
}

resource "digitalocean_ssh_key" "admin" {
  name       = "${var.name}-admin"
  public_key = file(pathexpand(var.ssh_public_key_path))
}

# The worlds live here. The droplet is disposable; this is not.
resource "digitalocean_volume" "data" {
  name                    = "${var.name}-data"
  region                  = var.region
  size                    = var.world_volume_size
  initial_filesystem_type = "ext4"
  description             = "Docker data-root: world volumes and images"

  lifecycle {
    prevent_destroy = true
  }
}

resource "digitalocean_droplet" "host" {
  name     = var.name
  region   = var.region
  size     = var.droplet_size
  image    = "ubuntu-24-04-x64"
  ssh_keys = [digitalocean_ssh_key.admin.fingerprint]

  user_data = templatefile("${path.module}/cloud-init.yaml.tftpl", {
    volume_device = local.volume_device
  })
}

resource "digitalocean_volume_attachment" "data" {
  droplet_id = digitalocean_droplet.host.id
  volume_id  = digitalocean_volume.data.id
}

resource "digitalocean_firewall" "mc" {
  name        = "${var.name}-fw"
  droplet_ids = [digitalocean_droplet.host.id]

  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = var.ssh_allowed_ips
  }

  # The router's single port. Individual worlds are never published.
  inbound_rule {
    protocol         = "tcp"
    port_range       = "25565"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  inbound_rule {
    protocol         = "icmp"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "icmp"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}
