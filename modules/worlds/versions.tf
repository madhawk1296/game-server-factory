# Without this the module inherits a guess: Terraform assumes hashicorp/docker
# rather than the kreuzwerker provider the root uses.
terraform {
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
