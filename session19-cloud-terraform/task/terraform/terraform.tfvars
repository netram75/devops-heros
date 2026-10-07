# Values for the LocalStack run that is documented in the README.
# Nothing secret here, so it is committed (see .gitignore in this folder).
# For real AWS: set use_localstack = false and allowed_ssh_cidr to your own IP.
aws_region          = "ap-south-1"
use_localstack      = true
localstack_endpoint = "http://localhost:4577"

project_name       = "netram-web"
environment        = "dev"
vpc_cidr           = "10.20.0.0/16"
public_subnet_cidr = "10.20.1.0/24"
allowed_ssh_cidr   = "203.0.113.10/32"
instance_type      = "t3.micro"
