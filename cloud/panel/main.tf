data "terraform_remote_state" "host" {
  backend = "local"
  config = {
    path = "../host/terraform.tfstate"
  }
}

resource "docker_image" "panel" {
  name = "ghcr.io/pelican/panel:latest"
}

# Panel state: SQLite database, the encryption key, and plugins. This volume is
# the panel -- losing it loses every server record and the key that decrypts
# them, with the game data still sitting on disk and no way to address it.
resource "docker_volume" "data" {
  name = "pelican-data"

  lifecycle {
    prevent_destroy = true
  }
}

resource "docker_volume" "logs" {
  name = "pelican-logs"
}

resource "docker_container" "panel" {
  name    = "pelican-panel"
  image   = docker_image.panel.image_id
  restart = "unless-stopped"

  memory      = var.memory_mb
  memory_swap = var.memory_mb

  log_driver = "json-file"
  log_opts = {
    "max-size" = "10m"
    "max-file" = "3"
  }

  env = [
    # https:// makes the bundled Caddy request a certificate and 308 port 80.
    "APP_URL=https://${var.hostname}",
    "LE_EMAIL=${var.le_email}",
    "ADMIN_EMAIL=${var.le_email}",
    "APP_ENV=production",
    "APP_DEBUG=false",
    "XDG_DATA_HOME=/pelican-data",
    "MAIL_DRIVER=log",
  ]

  ports {
    internal = 80
    external = 80
  }

  ports {
    internal = 443
    external = 443
  }

  # Lets the panel reach Wings on the host once v3.2 lands, without Wings
  # needing a publicly routable port.
  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }

  volumes {
    volume_name    = docker_volume.data.name
    container_path = "/pelican-data"
  }

  volumes {
    volume_name    = docker_volume.logs.name
    container_path = "/var/www/html/storage/logs"
  }
}
