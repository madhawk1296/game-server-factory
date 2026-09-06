data "terraform_remote_state" "host" {
  backend = "local"
  config = {
    path = "../host/terraform.tfstate"
  }
}

resource "docker_network" "mc" {
  name = "mc"
}

module "worlds" {
  source = "../../modules/worlds"

  network_name    = docker_network.mc.name
  servers         = var.servers
  world_domain    = coalesce(var.world_domain, data.terraform_remote_state.host.outputs.world_domain)
  jvm_overhead_mb = var.jvm_overhead_mb
  backup_s3       = var.backup_s3

  backup_interval      = var.backup_interval
  backup_prune_days    = var.backup_prune_days
  backup_initial_delay = var.backup_initial_delay
}
