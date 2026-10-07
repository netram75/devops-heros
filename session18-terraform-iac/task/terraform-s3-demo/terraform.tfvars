# Values for this run. Nothing secret lives here, which is why this file is
# committed (the parent folder's .gitignore ignores terraform.tfvars by default,
# this folder's .gitignore re-includes it).
aws_region          = "ap-south-1"
use_localstack      = true
localstack_endpoint = "http://localhost:4577"

bucket_name       = "netram-24bcs10329-tf-demo"
environment       = "dev"
enable_versioning = true
force_destroy     = true # demo bucket, OK to delete with objects inside

extra_tags = {
  Course  = "DevOps-Heros"
  Session = "18"
}
