variable "hostname" {
  description = <<-EOT
    Where the storefront is served. The apex, deliberately: a customer typing
    the bare domain into a browser should land on the shop, while the same name
    in a Minecraft client reaches the flagship server on 25565. Different ports,
    no conflict.
  EOT
  type        = string
  default     = "cheapminecraftservers.com"
}

variable "http_port" {
  description = <<-EOT
    Host port Paymenter listens on. Not 80 -- the panel's Caddy owns that and
    terminates TLS for every hostname. Not in the firewall either, so this is
    reachable only from the host and its containers.
  EOT
  type        = number
  default     = 8081
}

variable "memory_mb" {
  type    = number
  default = 512
}

variable "db_memory_mb" {
  type    = number
  default = 512
}
