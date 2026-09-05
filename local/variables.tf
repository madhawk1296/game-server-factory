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
    port = number

    # What the world is *sold*: the container's hard RAM ceiling, the way a real
    # host quotes it. The JVM heap is derived from this via var.heap_fraction.
    # Never set the two independently -- that is how you get OOM-killed.
    memory_mb = optional(number, 3072)

    # Relative CPU weight, not a cap. See the note in main.tf.
    cpu_shares = optional(number, 1024)

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
