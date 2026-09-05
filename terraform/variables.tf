variable "name" {
  description = "Name prefix for all resources. Also the container name."
  type        = string
  default     = "mc-01"
}

variable "location" {
  description = <<-EOT
    Hetzner location. fsn1/nbg1/hel1 = EU, ash = Ashburn VA, hil = Hillsboro OR.
    The cheap CX and CAX lines are EU-only; US locations offer only CPX and CCX,
    which cost roughly 4x as much for the same RAM.
  EOT
  type        = string
  default     = "hel1"
}

variable "server_type" {
  description = <<-EOT
    Hetzner server type. Since the 15 June 2026 price change, CX (x86, EU-only)
    is the best value: CX33 = 4 vCPU / 8 GB, CX43 = 8 vCPU / 16 GB.
    CAX (ARM) now costs more for identical specs, so there is no reason to take
    on arm64 mod-compatibility risk. US regions have neither line -- see the
    cost table in the README before picking a US location.
  EOT
  type        = string
  default     = "cx33"
}

variable "ssh_public_key_path" {
  description = "Path to the public key that gets root SSH access."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "ssh_allowed_ips" {
  description = "CIDRs allowed to reach port 22. Narrow this to your own IP once things work."
  type        = list(string)
  default     = ["0.0.0.0/0", "::/0"]
}

variable "world_volume_size" {
  description = "Size of the persistent world volume in GB. Hetzner minimum is 10."
  type        = number
  default     = 20
}

# ---- Minecraft ----

variable "mc_version" {
  description = "Minecraft version, or LATEST."
  type        = string
  default     = "LATEST"
}

variable "mc_type" {
  description = "Server flavour: PAPER, FABRIC, FORGE, NEOFORGE, VANILLA."
  type        = string
  default     = "PAPER"
}

variable "mc_memory" {
  description = "Java heap size. Leave ~2 GB of headroom below the box's RAM for the OS and JVM overhead."
  type        = string
  default     = "6G"
}

variable "mc_motd" {
  description = "Server list message."
  type        = string
  default     = "A Terraform-provisioned world"
}

variable "mc_difficulty" {
  description = "peaceful, easy, normal, or hard."
  type        = string
  default     = "normal"
}

variable "mc_max_players" {
  type    = number
  default = 20
}

variable "mc_ops" {
  description = "Minecraft usernames granted operator status."
  type        = list(string)
  default     = []
}

variable "mc_whitelist" {
  description = "Minecraft usernames allowed to join. Empty list disables the whitelist."
  type        = list(string)
  default     = []
}

# ---- Backups ----

variable "backup_interval" {
  description = "How often to snapshot the world. Uses mc-backup duration syntax (e.g. 2h, 30m)."
  type        = string
  default     = "2h"
}

variable "backup_prune_days" {
  description = "Delete local backups older than this many days."
  type        = number
  default     = 7
}
