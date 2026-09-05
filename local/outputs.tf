output "direct" {
  description = "Connect straight to a world, no DNS needed."
  value       = { for k, v in var.servers : k => "localhost:${v.port}" }
}

output "via_router" {
  description = "Hostname routing through mc-router on 25565. Needs /etc/hosts entries locally."
  value       = { for host, backend in local.routes : host => backend }
}

output "etc_hosts_line" {
  description = "Paste into /etc/hosts so a real client can resolve these names."
  value       = "127.0.0.1 ${join(" ", keys(local.routes))}"
}

output "rcon_passwords" {
  value     = { for k, v in random_password.rcon : k => v.result }
  sensitive = true
}
