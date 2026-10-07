# One provider block for both targets. Only use_localstack changes; none of the
# resource files know whether they talk to LocalStack or to real AWS.
provider "aws" {
  region = var.aws_region

  # LocalStack accepts any keys. On real AWS these stay null and the normal
  # credential chain (env vars, SSO profile, CI OIDC role) is used.
  access_key = var.use_localstack ? "test" : null
  secret_key = var.use_localstack ? "test" : null

  skip_credentials_validation = var.use_localstack
  skip_metadata_api_check     = var.use_localstack
  skip_requesting_account_id  = var.use_localstack
  s3_use_path_style           = var.use_localstack

  dynamic "endpoints" {
    for_each = var.use_localstack ? [var.localstack_endpoint] : []
    content {
      ec2 = endpoints.value
      iam = endpoints.value
      s3  = endpoints.value
      sts = endpoints.value
      eks = endpoints.value
    }
  }

  default_tags {
    tags = local.common_tags
  }
}

provider "random" {}
