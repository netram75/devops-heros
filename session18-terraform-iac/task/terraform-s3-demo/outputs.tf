output "bucket_name" {
  description = "Name (id) of the bucket."
  value       = aws_s3_bucket.demo.id
}

output "bucket_arn" {
  description = "ARN of the bucket, what I would paste into an IAM policy."
  value       = aws_s3_bucket.demo.arn
}

output "bucket_region" {
  description = "Region the bucket lives in."
  value       = aws_s3_bucket.demo.region
}

output "versioning_status" {
  description = "Enabled or Suspended."
  value       = aws_s3_bucket_versioning.demo.versioning_configuration[0].status
}

output "encryption_algorithm" {
  description = "Default server-side encryption algorithm."
  value       = one(aws_s3_bucket_server_side_encryption_configuration.demo.rule[*].apply_server_side_encryption_by_default[0].sse_algorithm)
}

output "all_tags" {
  description = "Bucket tags including the provider default_tags."
  value       = aws_s3_bucket.demo.tags_all
}

output "target" {
  description = "Where this run was applied."
  value       = var.use_localstack ? "LocalStack at ${var.localstack_endpoint}" : "real AWS"
}
