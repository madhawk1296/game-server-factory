output "connect" {
  description = "Hostnames players use. All resolve to the droplet, all on 25565."
  value       = keys(module.worlds.routes)
}

output "etc_hosts_line" {
  description = "Until v2.2 gives this real DNS, paste into /etc/hosts."
  value       = "${data.terraform_remote_state.host.outputs.ipv4_address} ${join(" ", keys(module.worlds.routes))}"
}

output "backups" {
  description = "Whether anything is protecting these worlds."
  value       = module.worlds.backups_enabled ? "enabled" : "DISABLED - no backups exist for these worlds"
}

output "stopped" {
  value = module.worlds.stopped
}

output "restic_password" {
  description = "Losing this makes every backup permanently unreadable."
  value       = module.worlds.restic_password
  sensitive   = true
}
