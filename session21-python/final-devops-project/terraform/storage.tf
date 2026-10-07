# Bucket names are global across every AWS account, so add a random suffix.
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "artifacts" {
  bucket        = "${local.name}-artifacts-${random_id.bucket_suffix.hex}"
  force_destroy = true # lab bucket: destroy may delete the objects and versions

  tags = { Name = "${local.name}-artifacts" }
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# A small record of what this apply built, written into the bucket. It
# references the instance and subnets, so Terraform creates it last.
resource "aws_s3_object" "deployment_record" {
  bucket       = aws_s3_bucket.artifacts.id
  key          = "deployments/${var.environment}.json"
  content_type = "application/json"
  content = jsonencode({
    project         = var.project_name
    environment     = var.environment
    region          = var.aws_region
    vpc_id          = aws_vpc.main.id
    public_subnets  = aws_subnet.public[*].id
    private_subnets = aws_subnet.private[*].id
    k3s_instance_id = aws_instance.k3s.id
    app_image       = var.app_image
  })
}
