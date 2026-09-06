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
  description = <<-EOT
    Suffix for routable hostnames. Normally left null: the host root already
    knows it, derived from whether a domain is configured there. Set it only to
    override.
  EOT
  type        = string
  default     = null
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
  description = <<-EOT
    RAM reserved above the heap, per world. Heap = memory_mb - this.

    Higher here than the local default of 768, and the difference is a real
    finding rather than caution. v1.1 measured ~440 MB of non-heap RSS at both a
    4096 MB and a 2457 MB heap and concluded the cost was fixed. With uptime and
    a 4352 MB heap it reached 693 MB -- so part of it does scale with heap (G1's
    remembered sets and card table), it was just small enough to hide at the
    sizes originally tested.

    768 left this world at 98.5% of its ceiling, roughly 75 MB from an OOM kill
    -- which is a hard kill, so no flush and up to an autosave interval lost.
    Large heaps need the bigger reserve; small ones do not.
  EOT
  type        = number
  default     = 1024
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
