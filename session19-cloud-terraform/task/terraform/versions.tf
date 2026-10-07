# Terraform core version and the two providers this project uses.
#   hashicorp/aws    - talks to the AWS (or LocalStack) API
#   hashicorp/random - generates a random suffix so the bucket name is unique
# Both are pinned to a major version; the exact build is recorded in
# .terraform.lock.hcl, which is committed.
terraform {
  required_version = ">= 1.9.0" # 1.9+ lets one variable's validation look at another variable

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
