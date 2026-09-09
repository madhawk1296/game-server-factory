# CI-sized stack. GitHub runners have ~7 GB, so the worlds are the smallest the
# precondition allows plus headroom: memory_mb must exceed jvm_overhead_mb by at
# least 512, and 1536 leaves a 768 MB heap, which boots Paper with no players.
docker_host = "unix:///var/run/docker.sock"

backup_initial_delay = "10s"

servers = {
  smp = {
    port      = 25566
    memory_mb = 1536
    motd      = "Survival"
    ops       = ["madhawk1296"]
  }

  creative = {
    memory_mb  = 1536
    motd       = "Creative build server"
    gamemode   = "creative"
    difficulty = "peaceful"
    ops        = ["madhawk1296"]
  }
}
