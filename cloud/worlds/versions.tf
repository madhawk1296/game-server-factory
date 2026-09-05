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

# Why this is a separate root from ../host:
#
# Terraform configures providers before it creates resources, so a provider
# cannot depend on a value that only exists after an apply -- and the droplet's
# IP is exactly that. Splitting host provisioning from world deployment is the
# honest way around it, and it happens to match how real platforms are layered:
# infrastructure below, workloads above.
#
# The daemon is remote, but nothing else changes. modules/worlds is the same
# code that runs against Docker Desktop on the Mac.
provider "docker" {
  host = data.terraform_remote_state.host.outputs.docker_host
}
