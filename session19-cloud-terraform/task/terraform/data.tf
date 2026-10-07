# Data sources READ existing information, they never create anything.

# Pick the first available AZ in the region instead of hard-coding "ap-south-1a".
data "aws_availability_zones" "available" {
  state = "available"
}

# Latest Amazon Linux 2023 (x86_64, standard not minimal) published by Amazon.
# count = 0 when an AMI is pinned, so the lookup is skipped entirely.
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
