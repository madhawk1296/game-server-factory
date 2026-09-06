terraform {
  required_version = ">= 1.6.0"

  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.40"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
  }
}

# Reads DIGITALOCEAN_TOKEN from the environment when do_token is null.
provider "digitalocean" {
  token = var.do_token
}
