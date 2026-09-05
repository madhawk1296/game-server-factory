output "server_ip" {
  description = "Connect to this address in the Minecraft client."
  value       = hcloud_server.mc.ipv4_address
}

output "ssh" {
  value = "ssh root@${hcloud_server.mc.ipv4_address}"
}

output "rcon_password" {
  description = "Read with: terraform output -raw rcon_password"
  value       = random_password.rcon.result
  sensitive   = true
}
