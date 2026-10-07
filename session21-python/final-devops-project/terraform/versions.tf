# Terraform core and provider versions. The exact provider builds are recorded
# in .terraform.lock.hcl, which is committed so every machine (and CI) uses the
# same binaries.
terraform {
  required_version = ">= 1.9.0" # 1.9+ lets a validation block read another variable

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
