variable "servers" {
  description = "Same shape as the local stack. See ../../modules/worlds/variables.tf."
  type = map(object({
    port       = optional(number)
    state      = optional(string, "running")
    memory_mb  = optional(number, 3072)
    cpu_shares = optional(number, 1024)
    type       = optional(string, "PAPER")
    version    = optional(string, "LATEST")
    motd       = optional(string, "A world")
    gamemode   = optional(string, "survival")
    difficulty = optional(string, "normal")
    ops        = optional(list(string), [])
  }))

  # A 4 vCPU / 8 GB droplet, minus room for the OS and the router.
  default = {
    smp = {
      memory_mb = 5120
      motd      = "Survival"
      ops       = ["madhawk1296"]
    }
  }
}

variable "world_domain" {
  description = "Suffix for routable hostnames. Becomes a real domain at v2.2."
  type        = string
  default     = "mc.example.com"
}

variable "backup_s3" {
  description = <<-EOT
    Required here, unlike the local stack. A cloud host with no backups is the
    exact failure this project is meant to avoid, and there is no MinIO
    stand-in on a real machine -- an object store sharing the host it protects
    is not a backup.

    Cloudflare R2 is free below 10 GB and has no egress fees, which is what you
    care about on the day you restore.
  EOT
  type = object({
    endpoint   = string
    bucket     = string
    access_key = string
    secret_key = string
  })
  sensitive = true
}

variable "jvm_overhead_mb" {
  type    = number
  default = 768
}

variable "backup_interval" {
  type    = string
  default = "2h"
}

variable "backup_prune_days" {
  type    = number
  default = 7
}

variable "backup_initial_delay" {
  type    = string
  default = "2m"
}
