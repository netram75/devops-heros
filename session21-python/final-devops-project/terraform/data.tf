# Data sources only READ information; they never create anything.

# The first two available AZs of the region. Two AZs is the minimum EKS accepts
# for a cluster and the minimum for anything that should survive one AZ failing.
data "aws_availability_zones" "available" {
  state = "available"
}

# Latest Amazon Linux 2023 x86_64 image published by Amazon. Skipped (count = 0)
# when ami_id is pinned in tfvars.
data "aws_ami" "al2023" {
  count       = var.ami_id == null ? 1 : 0
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-kernel-6.1-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}
