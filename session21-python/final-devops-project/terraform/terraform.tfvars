# Values for the LocalStack run documented in docs/terraform.md.
# Nothing secret here, so it is committed.
# For real AWS: use_localstack = false and admin_cidr = your own IP/32.
aws_region          = "ap-south-1"
use_localstack      = true
localstack_endpoint = "http://localhost:4578"

project_name = "netram-final"
environment  = "dev"

vpc_cidr             = "10.21.0.0/16"
public_subnet_cidrs  = ["10.21.1.0/24", "10.21.2.0/24"]
private_subnet_cidrs = ["10.21.101.0/24", "10.21.102.0/24"]
enable_nat_gateway   = true
admin_cidr           = "203.0.113.10/32"

instance_type = "t3.small"
k3s_version   = "v1.31.4+k3s1"
app_image     = "ghcr.io/netram75/devops-heros-final:latest"

enable_eks = false
