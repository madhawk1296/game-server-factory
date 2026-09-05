variable "docker_host" {
  description = <<-EOT
    Docker daemon endpoint. Leave null for Docker Desktop on macOS.
    Find yours with: docker context inspect --format '{{.Endpoints.docker.Host}}'
  EOT
  type        = string
  default     = null
}

variable "servers" {
  description = <<-EOT
    The worlds to run. Map key becomes the container name and the mc-router
    hostname, so `smp` is reachable at smp.mc.localhost.

    This map is the whole point of the local stack: adding a world is one entry,
    and it is the same shape the cloud module will take at v1.
  EOT

  type = map(object({
    port       = number
    memory     = optional(string, "4G")
    type       = optional(string, "PAPER")
    version    = optional(string, "LATEST")
    motd       = optional(string, "Local dev world")
    difficulty = optional(string, "normal")
    ops        = optional(list(string), [])
  }))

  default = {
    # Docker Desktop's VM has less RAM than the Mac does. Check what it actually
    # has before adding a second world; 4G each plus overhead adds up fast.
    smp = { port = 25566, ops = ["madhawk1296"] }
  }
}

variable "backup_interval" {
  description = "How often to snapshot each world. mc-backup duration syntax."
  type        = string
  default     = "2h"
}

variable "backup_prune_days" {
  type    = number
  default = 3
}
