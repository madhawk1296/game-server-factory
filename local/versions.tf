terraform {
  required_version = ">= 1.6.0"

  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Docker Desktop on macOS keeps its socket under $HOME and only symlinks
# /var/run/docker.sock if you enable the privileged-helper setting. Default to
# the path that works out of the box; override for colima/OrbStack/Linux.
provider "docker" {
  host = coalesce(var.docker_host, "unix://${pathexpand("~/.docker/run/docker.sock")}")
}
