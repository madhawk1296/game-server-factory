output "url" {
  value = "https://${var.hostname}"
}

output "installer" {
  description = "Finish setup here. Choose SQLite when asked for a database driver."
  value       = "https://${var.hostname}/installer"
}
