output "direct" {
  description = "Connect straight to a world, no DNS needed."
  value       = { for k, v in var.servers : k => "localhost:${v.port}" }
}

output "via_router" {
  description = "Hostname routing through mc-router on 25565. Needs /etc/hosts entries."
  value       = { for k, v in var.servers : k => "${k}.mc.localhost" }
}

output "rcon_passwords" {
  value     = { for k, v in random_password.rcon : k => v.result }
  sensitive = true
}
