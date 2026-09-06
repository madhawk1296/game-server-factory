data "http" "my_ip" {
  count = var.ssh_allowed_ips == null ? 1 : 0
  url   = "https://api.ipify.org"
}

locals {
  ssh_allowed = var.ssh_allowed_ips != null ? var.ssh_allowed_ips : ["${chomp(data.http.my_ip[0].response_body)}/32"]

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

  # Installs do-agent, which is what publishes the metrics the alerts below
  # read. Alerts without it are decorative.
  monitoring = true

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
    source_addresses = local.ssh_allowed
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

# A reserved IP belongs to the account, not the droplet. Replacing the droplet
# reassigns it rather than handing out a new address -- so DNS never has to
# change and nobody's saved server entry breaks. Free while assigned.
# droplet_id is set here rather than via a separate
# digitalocean_reserved_ip_assignment: creating an unassigned reserved IP first
# trips a provider bug ("Root object was present, but now absent") that leaks an
# orphaned, billing IP outside of state. Allocate and assign in one call.
resource "digitalocean_reserved_ip" "host" {
  region     = var.region
  droplet_id = digitalocean_droplet.host.id
}

# Terraform can manage the records, but only once the registrar delegates the
# zone to DigitalOcean's nameservers. That part is yours.
resource "digitalocean_domain" "zone" {
  count = var.domain == null ? 0 : 1
  name  = var.domain
}

# One wildcard covers every world that will ever exist, so adding a world never
# touches DNS. The routing decision belongs to mc-router, not to the resolver.
resource "digitalocean_record" "worlds" {
  count  = var.domain == null ? 0 : 1
  domain = digitalocean_domain.zone[0].name
  type   = "A"
  name   = var.dns_prefix == null ? "*" : "*.${var.dns_prefix}"
  value  = digitalocean_reserved_ip.host.ip_address
  ttl    = 60
}

# Memory is the constraint that decides how many worlds fit, so this is the one
# that actually tells you something actionable.
resource "digitalocean_monitor_alert" "memory" {
  count = var.alert_email == null ? 0 : 1
  alerts { email = [var.alert_email] }
  window      = "5m"
  type        = "v1/insights/droplet/memory_utilization_percent"
  compare     = "GreaterThan"
  value       = 90
  enabled     = true
  entities    = [digitalocean_droplet.host.id]
  description = "${var.name}: memory above 90%"
}

resource "digitalocean_monitor_alert" "disk" {
  count = var.alert_email == null ? 0 : 1
  alerts { email = [var.alert_email] }
  window      = "5m"
  type        = "v1/insights/droplet/disk_utilization_percent"
  compare     = "GreaterThan"
  value       = 80
  enabled     = true
  entities    = [digitalocean_droplet.host.id]
  description = "${var.name}: disk above 80%"
}

# A ten minute window rather than five: chunk generation spikes CPU hard and
# briefly, and an alert that cries wolf during normal play gets muted.
resource "digitalocean_monitor_alert" "cpu" {
  count = var.alert_email == null ? 0 : 1
  alerts { email = [var.alert_email] }
  window      = "10m"
  type        = "v1/insights/droplet/cpu"
  compare     = "GreaterThan"
  value       = 90
  enabled     = true
  entities    = [digitalocean_droplet.host.id]
  description = "${var.name}: CPU above 90% sustained"
}
