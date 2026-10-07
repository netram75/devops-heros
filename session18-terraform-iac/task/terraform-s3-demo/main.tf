locals {
  # Bucket-specific tags. The provider's default_tags are merged on top of these
  # automatically, so the bucket ends up with both sets.
  bucket_tags = merge(
    {
      Name        = var.bucket_name
      Environment = var.environment
      Student     = "Netram-24BCS10329"
    },
    var.extra_tags,
  )
}

# The bucket itself. Since AWS provider v4, versioning, encryption, policies and
# so on are separate resources instead of nested blocks, so each setting has its
# own lifecycle and shows up clearly in the plan.
resource "aws_s3_bucket" "demo" {
  bucket        = var.bucket_name
  force_destroy = var.force_destroy

  tags = local.bucket_tags
}

# Versioning: an overwrite or delete keeps the previous version, so a bad
# upload or an accidental "rm" can be undone.
resource "aws_s3_bucket_versioning" "demo" {
  bucket = aws_s3_bucket.demo.id

  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Suspended"
  }
}

# Default encryption at rest with S3-managed keys (SSE-S3, AES256).
# AWS already does this for new buckets, but writing it down makes the intent
# explicit and lets me switch to aws:kms later in one place.
resource "aws_s3_bucket_server_side_encryption_configuration" "demo" {
  bucket = aws_s3_bucket.demo.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Block every kind of public access: no public ACLs, no public bucket policy.
# This bucket is private, so there is no reason to leave any of these off.
resource "aws_s3_bucket_public_access_block" "demo" {
  bucket = aws_s3_bucket.demo.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
