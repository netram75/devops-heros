# Which Terraform and which provider version this code expects.
# Pinning the major version (~> 6.0) means "terraform init" will never jump
# to a 7.x provider with breaking changes behind my back.
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# One provider block for both targets.
# use_localstack = true  -> every S3/STS call goes to LocalStack on my laptop
# use_localstack = false -> the same code talks to real AWS with my normal credentials
provider "aws" {
  region = var.aws_region

  # LocalStack accepts any credentials, "test"/"test" is its convention.
  # On real AWS these are null, so the normal credential chain is used.
  access_key = var.use_localstack ? "test" : null
  secret_key = var.use_localstack ? "test" : null

  # LocalStack has no EC2 metadata service and no real account,
  # so skip the checks that would otherwise fail or hang.
  skip_credentials_validation = var.use_localstack
  skip_metadata_api_check     = var.use_localstack
  skip_requesting_account_id  = var.use_localstack

  # Path-style URLs (http://host/bucket) avoid needing wildcard DNS for
  # bucket-name.localhost on my machine.
  s3_use_path_style = var.use_localstack

  # The endpoints block only exists when targeting LocalStack.
  dynamic "endpoints" {
    for_each = var.use_localstack ? [var.localstack_endpoint] : []
    content {
      s3  = endpoints.value
      sts = endpoints.value
    }
  }

  # Tags added to every resource that supports them.
  default_tags {
    tags = {
      ManagedBy = "Terraform"
      Project   = "session18-terraform-s3-demo"
      Owner     = "netram75"
    }
  }
}
