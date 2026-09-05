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
    # Optional, and normally omitted. A world only needs a published host port
    # if you want to reach it without going through the router -- debugging, or
    # a client that cannot resolve the routed hostname. Leaving it null means
    # the world is reachable only via <name>.<world_domain> on the router's
    # single port, which is the production posture: one exposed port total.
    port = optional(number)

    # What the world is *sold*: the container's hard RAM ceiling, the way a real
    # host quotes it. The JVM heap is derived from this via var.heap_fraction.
    # Never set the two independently -- that is how you get OOM-killed.
    memory_mb = optional(number, 3072)

    # Relative CPU weight, not a cap. See the note in main.tf.
    cpu_shares = optional(number, 1024)

    type       = optional(string, "PAPER")
    version    = optional(string, "LATEST")
    motd       = optional(string, "Local dev world")
    gamemode   = optional(string, "survival")
    difficulty = optional(string, "normal")
    ops        = optional(list(string), [])
  }))

  validation {
    condition = length([for v in var.servers : v.port if v.port != null]) == length(
      distinct([for v in var.servers : v.port if v.port != null])
    )
    error_message = "Two worlds share a published host port. Ports are an allocation, not a derived value -- assign each one explicitly and uniquely."
  }

  validation {
    condition     = alltrue([for v in var.servers : v.port == null || (try(v.port, 0) >= 1024 && try(v.port, 0) <= 65535)])
    error_message = "Published ports must be between 1024 and 65535."
  }

  validation {
    condition     = alltrue([for v in var.servers : v.port != 25565])
    error_message = "25565 belongs to mc-router. A world published there would collide with the router and break every other world."
  }

  # Budget check before adding a world: the Docker VM has ~7.6 GB, and each
  # world costs memory_mb plus 256 MB for its backup sidecar.
  default = {
    smp = {
      port      = 25566 # kept published as the escape hatch; creative is router-only
      memory_mb = 3072
      motd      = "Survival"
      ops       = ["madhawk1296"]
    }

    creative = {
      memory_mb  = 2048
      motd       = "Creative build server"
      gamemode   = "creative"
      difficulty = "peaceful"
      ops        = ["madhawk1296"]
    }
  }
}

variable "world_domain" {
  description = <<-EOT
    Suffix for each world's routable hostname: <world>.<world_domain>.

    Locally this needs matching /etc/hosts entries, since nothing resolves
    *.mc.localhost. At v2 this becomes a real domain with a wildcard A record
    and the routing stops needing any client-side setup.
  EOT
  type        = string
  default     = "mc.localhost"
}

variable "jvm_overhead_mb" {
  description = <<-EOT
    RAM reserved above the heap, per world. Heap = memory_mb - this.

    Measured on this workload, non-heap RSS was ~440 MB at BOTH a 4096 MB heap
    and a 2457 MB heap -- metaspace, thread stacks, code cache, and Netty direct
    buffers are largely fixed costs, not a percentage of heap. An earlier
    fraction-based model under-reserved on small heaps for exactly that reason.

    768 leaves ~330 MB of real slack for direct buffers to grow under player
    load. Lower it only if you have measured your own workload.
  EOT
  type        = number
  default     = 768
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
