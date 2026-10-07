locals {
  name = "${var.project_name}-${var.environment}"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Owner       = "netram75"
    Session     = "21"
  }

  azs    = slice(data.aws_availability_zones.available.names, 0, 2)
  ami_id = coalesce(var.ami_id, one(data.aws_ami.al2023[*].id))
}
