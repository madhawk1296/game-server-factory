variable "hostname" {
  description = <<-EOT
    Where the panel is served. Needs no DNS record of its own -- the wildcard
    from cloud/host already resolves every name under the domain to this host,
    and the panel answers on 443 while mc-router answers on 25565.
  EOT
  type        = string
  default     = "panel.cheapminecraftservers.com"
}

variable "le_email" {
  description = "Address Let's Encrypt registers the certificate against."
  type        = string
}

variable "memory_mb" {
  description = "Panel is PHP-FPM plus Caddy plus SQLite; modest, but give it room to breathe."
  type        = number
  default     = 768
}
