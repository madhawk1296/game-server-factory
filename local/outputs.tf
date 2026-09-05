output "direct" {
  description = "Worlds with a published host port. Others are router-only."
  value       = { for k, v in var.servers : k => "localhost:${v.port}" if v.port != null && v.state == "running" }
}

output "via_router" {
  description = "Hostname routing through mc-router on 25565."
  value       = module.worlds.routes
}

output "etc_hosts_line" {
  description = "Paste into /etc/hosts so a real client can resolve these names."
  value       = "127.0.0.1 ${join(" ", keys(module.worlds.routes))}"
}

output "stopped" {
  description = "Worlds that exist but are not running. Data retained, memory freed."
  value       = module.worlds.stopped
}

output "rcon_passwords" {
  value     = module.worlds.rcon_passwords
  sensitive = true
}

output "restic_password" {
  description = "Losing this makes every backup permanently unreadable. Save it outside Terraform state."
  value       = module.worlds.restic_password
  sensitive   = true
}
