terraform {
  required_version = ">= 1.6.0"

  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

# Same remote daemon as cloud/worlds, same reason for being its own root: a
# provider cannot depend on an IP that does not exist until apply.
provider "docker" {
  host = data.terraform_remote_state.host.outputs.docker_host
}
