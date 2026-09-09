output "url" {
  value = "https://${var.hostname}"
}

output "installer" {
  description = "Finish setup here once DNS and TLS are live."
  value       = "https://${var.hostname}/install"
}
