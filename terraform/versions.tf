terraform {
  required_version = ">= 1.6.0"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.48"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # v0 uses local state. Move this to a remote backend before a second person
  # (or a second machine) ever runs apply.
}

# Token comes from the HCLOUD_TOKEN environment variable.
provider "hcloud" {}
