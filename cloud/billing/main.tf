data "terraform_remote_state" "host" {
  backend = "local"
  config = {
    path = "../host/terraform.tfstate"
  }
}

resource "random_password" "db" {
  length  = 32
  special = false
}

resource "random_password" "db_root" {
  length  = 32
  special = false
}

resource "docker_network" "billing" {
  name = "billing"
}

resource "docker_image" "paymenter" {
  name = "ghcr.io/paymenter/paymenter:latest"
}

resource "docker_image" "mariadb" {
  name = "mariadb:lts"
}

resource "docker_image" "redis" {
  name = "redis:alpine"
}

# Every one of these lands on the block volume via Docker's data-root, so the
# shop's database and its uploaded assets survive a droplet rebuild the same way
# the game worlds do.
resource "docker_volume" "db" {
  name = "paymenter-db"

  lifecycle {
    prevent_destroy = true
  }
}

resource "docker_volume" "app" {
  name = "paymenter-app"
}

resource "docker_volume" "var" {
  name = "paymenter-var"
}

resource "docker_volume" "logs" {
  name = "paymenter-logs"
}

resource "docker_volume" "public" {
  name = "paymenter-public"
}

resource "docker_volume" "themes" {
  name = "paymenter-themes"
}

resource "docker_volume" "extensions" {
  name = "paymenter-extensions"
}

resource "docker_container" "database" {
  name    = "paymenter-db"
  image   = docker_image.mariadb.image_id
  restart = "unless-stopped"

  memory      = var.db_memory_mb
  memory_swap = var.db_memory_mb

  log_driver = "json-file"
  log_opts = {
    "max-size" = "10m"
    "max-file" = "3"
  }

  env = [
    "MARIADB_DATABASE=paymenter",
    "MARIADB_USER=paymenter",
    "MARIADB_PASSWORD=${random_password.db.result}",
    "MARIADB_ROOT_PASSWORD=${random_password.db_root.result}",
  ]

  volumes {
    volume_name    = docker_volume.db.name
    container_path = "/var/lib/mysql"
  }

  networks_advanced {
    name    = docker_network.billing.name
    aliases = ["database"]
  }
}

resource "docker_container" "cache" {
  name    = "paymenter-cache"
  image   = docker_image.redis.image_id
  restart = "unless-stopped"

  memory      = 128
  memory_swap = 128

  log_driver = "json-file"
  log_opts = {
    "max-size" = "10m"
    "max-file" = "3"
  }

  networks_advanced {
    name    = docker_network.billing.name
    aliases = ["cache"]
  }
}

resource "docker_container" "paymenter" {
  name    = "paymenter"
  image   = docker_image.paymenter.image_id
  restart = "unless-stopped"

  memory      = var.memory_mb
  memory_swap = var.memory_mb

  log_driver = "json-file"
  log_opts = {
    "max-size" = "10m"
    "max-file" = "3"
  }

  env = [
    "APP_URL=https://${var.hostname}",
    "APP_ENV=production",
    "APP_DEBUG=false",
    "DB_CONNECTION=mariadb",
    "DB_HOST=database",
    "DB_PORT=3306",
    "DB_DATABASE=paymenter",
    "DB_USERNAME=paymenter",
    "DB_PASSWORD=${random_password.db.result}",
    "CACHE_STORE=redis",
    "QUEUE_CONNECTION=redis",
    "REDIS_HOST=cache",
    "PAYMENTER_SKIP_DEFAULT=false",
  ]

  ports {
    internal = 80
    external = var.http_port
  }

  volumes {
    volume_name    = docker_volume.app.name
    container_path = "/app"
  }

  volumes {
    volume_name    = docker_volume.var.name
    container_path = "/app/var"
  }

  volumes {
    volume_name    = docker_volume.logs.name
    container_path = "/app/storage/logs"
  }

  volumes {
    volume_name    = docker_volume.public.name
    container_path = "/app/storage/app/public"
  }

  volumes {
    volume_name    = docker_volume.themes.name
    container_path = "/app/themes"
  }

  volumes {
    volume_name    = docker_volume.extensions.name
    container_path = "/app/extensions"
  }

  networks_advanced {
    name = docker_network.billing.name
  }

  depends_on = [docker_container.database, docker_container.cache]
}
