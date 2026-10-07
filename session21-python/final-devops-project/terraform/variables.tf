# ------------------------------------------------------------------ target

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

  validation {
    condition     = can(regex("^https?://[^/]+$", var.localstack_endpoint))
    error_message = "localstack_endpoint must be a URL like http://localhost:4566 with no path."
  }
}

# ------------------------------------------------------------------ naming

variable "project_name" {
  description = "Short prefix for every resource name (also ends up in the S3 bucket name)."
  type        = string
  default     = "netram-final"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,20}$", var.project_name))
    error_message = "project_name must be 3-21 chars: lowercase letters, digits, hyphens, starting with a letter."
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

# ------------------------------------------------------------------ network

variable "vpc_cidr" {
  description = "Address range of the whole VPC."
  type        = string
  default     = "10.21.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr)) && tonumber(split("/", var.vpc_cidr)[1]) >= 16 && tonumber(split("/", var.vpc_cidr)[1]) <= 24
    error_message = "vpc_cidr must be a valid IPv4 CIDR between /16 and /24 (room for four subnets)."
  }
}

variable "public_subnet_cidrs" {
  description = "Exactly two public subnet ranges, one per AZ, inside vpc_cidr."
  type        = list(string)
  default     = ["10.21.1.0/24", "10.21.2.0/24"]

  validation {
    condition = length(var.public_subnet_cidrs) == 2 && alltrue([
      for c in var.public_subnet_cidrs :
      can(cidrnetmask(c)) &&
      tonumber(split("/", c)[1]) > tonumber(split("/", var.vpc_cidr)[1]) &&
      cidrsubnet("${cidrhost(c, 0)}/${split("/", var.vpc_cidr)[1]}", 0, 0) == cidrsubnet(var.vpc_cidr, 0, 0)
    ])
    error_message = "public_subnet_cidrs must hold exactly two CIDRs, each a smaller range inside vpc_cidr."
  }
}

variable "private_subnet_cidrs" {
  description = "Exactly two private subnet ranges, one per AZ, inside vpc_cidr."
  type        = list(string)
  default     = ["10.21.101.0/24", "10.21.102.0/24"]

  validation {
    condition = length(var.private_subnet_cidrs) == 2 && alltrue([
      for c in var.private_subnet_cidrs :
      can(cidrnetmask(c)) &&
      tonumber(split("/", c)[1]) > tonumber(split("/", var.vpc_cidr)[1]) &&
      cidrsubnet("${cidrhost(c, 0)}/${split("/", var.vpc_cidr)[1]}", 0, 0) == cidrsubnet(var.vpc_cidr, 0, 0)
    ])
    error_message = "private_subnet_cidrs must hold exactly two CIDRs, each a smaller range inside vpc_cidr."
  }
}

variable "enable_nat_gateway" {
  description = "Create one NAT gateway (in the first public subnet) so private subnets can reach the internet."
  type        = bool
  default     = true
}

variable "admin_cidr" {
  description = "Only this range may reach SSH (22) and the k3s API (6443). Use your own IP as x.x.x.x/32."
  type        = string
  default     = "203.0.113.10/32"

  validation {
    condition     = can(cidrnetmask(var.admin_cidr)) && var.admin_cidr != "0.0.0.0/0"
    error_message = "admin_cidr must be a valid CIDR and must not be 0.0.0.0/0."
  }
}

# ------------------------------------------------------------------ compute

variable "instance_type" {
  description = "Size of the single-node k3s host. k3s wants about 2 GB RAM, so micro sizes are not allowed."
  type        = string
  default     = "t3.small"

  validation {
    condition     = contains(["t3.small", "t3.medium", "t3a.small", "t3a.medium"], var.instance_type)
    error_message = "instance_type must be t3.small, t3.medium, t3a.small or t3a.medium."
  }
}

variable "ami_id" {
  description = "Pin an exact AMI. Leave null to look up the latest Amazon Linux 2023."
  type        = string
  default     = null

  validation {
    condition     = var.ami_id == null || can(regex("^ami-[0-9a-f]{8,17}$", var.ami_id))
    error_message = "ami_id must look like ami-0123456789abcdef0, or be null."
  }
}

variable "k3s_version" {
  description = "k3s release installed by user_data (pinned so a reboot never upgrades the cluster)."
  type        = string
  default     = "v1.31.4+k3s1"

  validation {
    condition     = can(regex("^v1\\.[0-9]+\\.[0-9]+\\+k3s[0-9]+$", var.k3s_version))
    error_message = "k3s_version must look like v1.31.4+k3s1."
  }
}

variable "app_image" {
  description = "Container image the k3s host pulls. The registry is GHCR (filled by the CI pipeline)."
  type        = string
  default     = "ghcr.io/netram75/devops-heros-final:latest"

  validation {
    condition     = can(regex("^[a-z0-9.-]+/[a-z0-9._/-]+:[A-Za-z0-9._-]+$", var.app_image))
    error_message = "app_image must be registry/name:tag."
  }
}

# ------------------------------------------------------------------ EKS (optional)

variable "enable_eks" {
  description = "Create the EKS cluster + managed node group. Off by default: EKS is a LocalStack Pro feature and costs money on AWS."
  type        = bool
  default     = false

  validation {
    condition     = !(var.enable_eks && var.use_localstack)
    error_message = "enable_eks = true needs real AWS or LocalStack Pro. LocalStack community 4.x has no EKS API, so keep it false when use_localstack = true."
  }
}

variable "eks_version" {
  description = "Kubernetes version for EKS (only used when enable_eks = true)."
  type        = string
  default     = "1.31"

  validation {
    condition     = can(regex("^1\\.[0-9]{2}$", var.eks_version))
    error_message = "eks_version must look like 1.31."
  }
}
