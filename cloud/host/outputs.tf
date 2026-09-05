output "ipv4_address" {
  description = "Consumed by ../worlds to point the Docker provider at this host."
  value       = digitalocean_droplet.host.ipv4_address
}

output "docker_host" {
  description = "Docker daemon endpoint over SSH."
  value       = "ssh://root@${digitalocean_droplet.host.ipv4_address}"
}

output "ssh" {
  value = "ssh root@${digitalocean_droplet.host.ipv4_address}"
}
