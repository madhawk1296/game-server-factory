output "direct" {
  description = "Worlds with a published host port. Others are router-only."
  value       = { for k, v in local.running : k => "localhost:${v.port}" if v.port != null }
}

output "via_router" {
  description = "Hostname routing through mc-router on 25565. Needs /etc/hosts entries locally."
  value       = { for host, backend in local.routes : host => backend }
}

output "etc_hosts_line" {
  description = "Paste into /etc/hosts so a real client can resolve these names."
  value       = "127.0.0.1 ${join(" ", keys(local.routes))}"
}

output "stopped" {
  description = "Worlds that exist but are not running. Data retained, memory freed."
  value       = [for k, v in var.servers : k if v.state != "running"]
}

output "rcon_passwords" {
  value     = { for k, v in random_password.rcon : k => v.result }
  sensitive = true
}

output "restic_password" {
  description = "Losing this makes every backup permanently unreadable. Save it outside Terraform state."
  value       = random_password.restic.result
  sensitive   = true
}
