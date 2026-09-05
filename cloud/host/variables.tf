variable "do_token" {
  description = <<-EOT
    DigitalOcean API token. Leave null to use the DIGITALOCEAN_TOKEN
    environment variable instead; set it in terraform.tfvars (gitignored) if
    you would rather not keep a credential in your shell profile.
  EOT
  type        = string
  default     = null
  sensitive   = true
}

variable "name" {
  description = "Name prefix for the droplet, volume, and firewall."
  type        = string
  default     = "mc-node-1"
}

variable "region" {
  description = <<-EOT
    DigitalOcean region. nyc1/nyc3 = New York, sfo3 = San Francisco,
    tor1 = Toronto, ams3/fra1 = Europe. Measured from this machine, both US
    coasts were ~60 ms, so either coast is fine.
  EOT
  type        = string
  default     = "nyc3"
}

variable "droplet_size" {
  description = <<-EOT
    s-4vcpu-8gb  = 4 vCPU / 8 GB / 160 GB  -- $48/mo, fits two worlds
    s-8vcpu-16gb = 8 vCPU / 16 GB / 320 GB -- $96/mo
  EOT
  type        = string
  default     = "s-4vcpu-8gb"
}

variable "world_volume_size" {
  description = "GB of durable storage for Docker's data-root. $0.10/GiB/month."
  type        = number
  default     = 20
}

variable "ssh_public_key_path" {
  type    = string
  default = "~/.ssh/id_ed25519.pub"
}

variable "ssh_allowed_ips" {
  description = "CIDRs allowed to reach port 22. Narrow this once things work."
  type        = list(string)
  default     = ["0.0.0.0/0", "::/0"]
}
