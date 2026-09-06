output "ipv4_address" {
  description = "Stable address for this node. Survives droplet replacement."
  value       = digitalocean_reserved_ip.host.ip_address
}

output "droplet_ipv4" {
  description = "The droplet's own address. Changes when the droplet is replaced."
  value       = digitalocean_droplet.host.ipv4_address
}

output "world_domain" {
  description = "Suffix ../worlds uses for routable hostnames."
  value       = var.domain == null ? "mc.example.com" : (var.dns_prefix == null ? var.domain : "${var.dns_prefix}.${var.domain}")
}

output "dns" {
  value = var.domain == null ? "no domain set -- using /etc/hosts" : "*.${var.dns_prefix == null ? "" : "${var.dns_prefix}."}${var.domain} -> ${digitalocean_reserved_ip.host.ip_address}"
}

output "docker_host" {
  description = "Docker daemon endpoint over SSH."
  value       = "ssh://root@${digitalocean_reserved_ip.host.ip_address}"
}

output "ssh" {
  value = "ssh root@${digitalocean_reserved_ip.host.ip_address}"
}
