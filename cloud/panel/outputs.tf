output "url" {
  value = "https://${var.hostname}"
}

output "installer" {
  description = "Finish setup here. Choose SQLite when asked for a database driver."
  value       = "https://${var.hostname}/installer"
}

output "node_hostname" {
  description = "Use this as the node FQDN in the panel, with port 443, SSL on, behind proxy."
  value       = data.terraform_remote_state.host.outputs.node_hostname
}
