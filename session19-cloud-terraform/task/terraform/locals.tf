locals {
  name = "${var.project_name}-${var.environment}"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Owner       = "netram75"
    Session     = "19"
  }

  # If the caller pinned an AMI use it, otherwise use the data source result.
  ami_id = coalesce(var.ami_id, one(data.aws_ami.al2023[*].id))

  az = data.aws_availability_zones.available.names[0]
}
