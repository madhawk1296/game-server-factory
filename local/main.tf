# Environment, not product. This root owns the things that differ between where
# you run it -- the Docker network and a local MinIO standing in for object
# storage. The worlds themselves live in ../modules/worlds and are identical
# whether the daemon is this Mac or a machine in Helsinki.

locals {
  s3 = var.backup_s3 != null ? var.backup_s3 : {
    endpoint   = "http://minio:9000"
    bucket     = "mc-backups"
    access_key = "mcbackup"
    secret_key = one(random_password.minio[*].result)
  }
}

resource "docker_network" "mc" {
  name = "mc"
}

resource "random_password" "minio" {
  count   = var.backup_s3 == null ? 1 : 0
  length  = 32
  special = false
}

resource "docker_image" "minio" {
  count = var.backup_s3 == null ? 1 : 0
  name  = "minio/minio:latest"
}

resource "docker_volume" "minio" {
  count = var.backup_s3 == null ? 1 : 0
  name  = "mc-minio-data"

  lifecycle {
    prevent_destroy = true
  }
}

resource "docker_container" "minio" {
  count   = var.backup_s3 == null ? 1 : 0
  name    = "mc-minio"
  image   = docker_image.minio[0].image_id
  restart = "unless-stopped"

  memory      = 512
  memory_swap = 512

  command = ["server", "/data", "--console-address", ":9001"]

  env = [
    "MINIO_ROOT_USER=${local.s3.access_key}",
    "MINIO_ROOT_PASSWORD=${local.s3.secret_key}",
  ]

  # Console only. The S3 API is reachable inside the network; nothing needs it
  # published, and publishing object storage holding world data would be silly.
  ports {
    internal = 9001
    external = 9001
  }

  volumes {
    volume_name    = docker_volume.minio[0].name
    container_path = "/data"
  }

  networks_advanced {
    name = docker_network.mc.name

    # Alias so the endpoint reads like an ordinary S3 host. Container names are
    # prefixed; the endpoint should not have to know that.
    aliases = ["minio"]
  }
}

resource "docker_image" "minio_client" {
  count = var.backup_s3 == null ? 1 : 0
  name  = "minio/mc:latest"
}

# Restic does not create buckets, so something has to. Against a real provider
# this would be an aws_s3_bucket / cloudflare_r2_bucket resource; MinIO has no
# provider here, so a run-once container stands in for that step.
resource "docker_container" "minio_bucket" {
  count      = var.backup_s3 == null ? 1 : 0
  name       = "mc-minio-init"
  image      = docker_image.minio_client[0].image_id
  must_run   = false
  attach     = false
  entrypoint = ["/bin/sh", "-c"]

  # depends_on gives start order, not readiness -- MinIO needs a moment to
  # listen, so retry rather than race it.
  command = [
    "until mc alias set local http://minio:9000 \"$MINIO_USER\" \"$MINIO_PASS\" >/dev/null 2>&1; do sleep 2; done; mc mb --ignore-existing local/${local.s3.bucket} && echo bucket-ready"
  ]

  env = [
    "MINIO_USER=${local.s3.access_key}",
    "MINIO_PASS=${local.s3.secret_key}",
  ]

  networks_advanced {
    name = docker_network.mc.name
  }

  depends_on = [docker_container.minio]
}

module "worlds" {
  source = "../modules/worlds"

  network_name    = docker_network.mc.name
  servers         = var.servers
  world_domain    = var.world_domain
  jvm_overhead_mb = var.jvm_overhead_mb
  backup_s3       = local.s3

  backup_interval      = var.backup_interval
  backup_prune_days    = var.backup_prune_days
  backup_initial_delay = var.backup_initial_delay

  # The bucket has to exist before restic tries to open a repository in it.
  depends_on = [docker_container.minio_bucket]
}

# The refactor relocated these; without these blocks Terraform would plan to
# destroy and recreate every world, which prevent_destroy would then refuse.
moved {
  from = random_password.rcon
  to   = module.worlds.random_password.rcon
}
moved {
  from = random_password.restic
  to   = module.worlds.random_password.restic
}
moved {
  from = docker_image.mc
  to   = module.worlds.docker_image.mc
}
moved {
  from = docker_image.backup
  to   = module.worlds.docker_image.backup
}
moved {
  from = docker_image.router
  to   = module.worlds.docker_image.router
}
moved {
  from = docker_volume.world
  to   = module.worlds.docker_volume.world
}
moved {
  from = docker_container.mc
  to   = module.worlds.docker_container.mc
}
moved {
  from = docker_container.backup
  to   = module.worlds.docker_container.backup
}
moved {
  from = docker_container.router
  to   = module.worlds.docker_container.router
}
