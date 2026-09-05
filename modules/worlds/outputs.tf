output "routes" {
  value = local.routes
}

output "running" {
  value = keys(local.running)
}

output "stopped" {
  value = [for k, v in var.servers : k if v.state != "running"]
}

output "rcon_passwords" {
  value     = { for k, v in random_password.rcon : k => v.result }
  sensitive = true
}

output "restic_password" {
  value     = random_password.restic.result
  sensitive = true
}

output "backups_enabled" {
  value = local.backups_enabled
}
