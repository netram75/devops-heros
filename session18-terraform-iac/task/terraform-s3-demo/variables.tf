variable "aws_region" {
  description = "AWS region to create the bucket in."
  type        = string
  default     = "ap-south-1"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.aws_region))
    error_message = "aws_region must look like a real region code, for example ap-south-1."
  }
}

variable "use_localstack" {
  description = "true = send API calls to LocalStack, false = real AWS."
  type        = bool
  default     = true
}

variable "localstack_endpoint" {
  description = "Base URL of the LocalStack edge port. Only used when use_localstack is true."
  type        = string
  default     = "http://localhost:4566"
}

variable "bucket_name" {
  description = "Globally unique S3 bucket name."
  type        = string

  # S3 naming rules: 3-63 chars, lowercase letters, digits, dots and hyphens,
  # must start and end with a letter or digit. Catching this at plan time is
  # much nicer than an API error halfway through an apply.
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "bucket_name must be 3-63 characters of lowercase letters, digits, dots or hyphens, starting and ending with a letter or digit."
  }
}

variable "environment" {
  description = "Environment name, used in tags."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "enable_versioning" {
  description = "Keep old versions of objects when they are overwritten or deleted."
  type        = bool
  default     = true
}

variable "force_destroy" {
  description = "Allow terraform destroy to delete the bucket even if it still has objects. Fine for a demo, dangerous for real data."
  type        = bool
  default     = false
}

variable "extra_tags" {
  description = "Additional tags merged into the bucket tags."
  type        = map(string)
  default     = {}
}
