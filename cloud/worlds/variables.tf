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
    Leave null to deploy without backups -- fine for proving the host works,
    wrong once anyone builds something they would miss. There is deliberately no
    MinIO stand-in here: an object store sharing the machine it protects is not
    a backup, and a fake one is worse than an obvious absence.

    Cloudflare R2 is free below 10 GB with no egress fees, which is what you
    care about on the day you actually restore. That is the v2.3 step.
  EOT
  type = object({
    endpoint   = string
    bucket     = string
    access_key = string
    secret_key = string
  })
  default   = null
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
