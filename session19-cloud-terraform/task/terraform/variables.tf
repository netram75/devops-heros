# ---------------------------------------------------------------- where to deploy

variable "aws_region" {
  description = "AWS region for every resource."
  type        = string
  default     = "ap-south-1"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a region code such as ap-south-1."
  }
}

variable "use_localstack" {
  description = "true = LocalStack on this machine, false = real AWS."
  type        = bool
  default     = false
}

variable "localstack_endpoint" {
  description = "LocalStack edge URL, only used when use_localstack is true."
  type        = string
  default     = "http://localhost:4566"
}

# ---------------------------------------------------------------- naming

variable "project_name" {
  description = "Short name used as a prefix for every resource name."
  type        = string
  default     = "netram-web"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,20}$", var.project_name))
    error_message = "project_name must be 3-21 chars, lowercase letters, digits and hyphens, starting with a letter (it ends up in an S3 bucket name)."
  }
}

variable "environment" {
  description = "Environment label."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging or prod."
  }
}

# ---------------------------------------------------------------- network

variable "vpc_cidr" {
  description = "Address range of the whole VPC."
  type        = string
  default     = "10.20.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr)) && tonumber(split("/", var.vpc_cidr)[1]) >= 16 && tonumber(split("/", var.vpc_cidr)[1]) <= 28
    error_message = "vpc_cidr must be a valid IPv4 CIDR between /16 and /28 (the sizes AWS allows for a VPC)."
  }
}

variable "public_subnet_cidr" {
  description = "Address range of the public subnet. Must sit inside vpc_cidr."
  type        = string
  default     = "10.20.1.0/24"

  # Cross-variable check (Terraform 1.9+): the subnet has to be smaller than the
  # VPC and its network address, masked to the VPC prefix, must equal the VPC.
  # Without this, a typo like 10.30.1.0/24 only fails at apply time inside AWS.
  validation {
    condition = (
      can(cidrnetmask(var.public_subnet_cidr)) &&
      tonumber(split("/", var.public_subnet_cidr)[1]) > tonumber(split("/", var.vpc_cidr)[1]) &&
      cidrsubnet("${cidrhost(var.public_subnet_cidr, 0)}/${split("/", var.vpc_cidr)[1]}", 0, 0) == cidrsubnet(var.vpc_cidr, 0, 0)
    )
    error_message = "public_subnet_cidr must be a smaller range inside vpc_cidr."
  }
}

variable "allowed_ssh_cidr" {
  description = "Only this range may reach port 22. Use your own public IP as x.x.x.x/32."
  type        = string
  default     = "203.0.113.10/32"

  validation {
    condition     = can(cidrnetmask(var.allowed_ssh_cidr)) && var.allowed_ssh_cidr != "0.0.0.0/0"
    error_message = "allowed_ssh_cidr must be a valid CIDR and must not be 0.0.0.0/0 (SSH open to the whole internet)."
  }
}

# ---------------------------------------------------------------- compute

variable "instance_type" {
  description = "EC2 instance size. Restricted to small x86_64 types to keep cost low."
  type        = string
  default     = "t3.micro"

  validation {
    condition     = contains(["t3.micro", "t3.small", "t3a.micro", "t3a.small"], var.instance_type)
    error_message = "instance_type must be one of t3.micro, t3.small, t3a.micro, t3a.small."
  }
}

variable "ami_id" {
  description = "Pin an exact AMI. Leave null to look up the latest Amazon Linux 2023 image."
  type        = string
  default     = null

  validation {
    condition     = var.ami_id == null || can(regex("^ami-[0-9a-f]{8,17}$", var.ami_id))
    error_message = "ami_id must look like ami-0123456789abcdef0, or be null."
  }
}
