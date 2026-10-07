output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.main.id
}

output "public_subnet_id" {
  description = "ID of the public subnet."
  value       = aws_subnet.public.id
}

output "availability_zone" {
  description = "AZ chosen by the data source."
  value       = aws_subnet.public.availability_zone
}

output "internet_gateway_id" {
  description = "ID of the internet gateway."
  value       = aws_internet_gateway.igw.id
}

output "security_group_id" {
  description = "ID of the web security group."
  value       = aws_security_group.web.id
}

output "ami_id" {
  description = "AMI the instance was launched from."
  value       = aws_instance.web.ami
}

output "instance_id" {
  description = "ID of the EC2 instance."
  value       = aws_instance.web.id
}

output "instance_public_ip" {
  description = "Public IPv4 of the instance."
  value       = aws_instance.web.public_ip
}

output "web_url" {
  description = "Where nginx would answer on real AWS."
  value       = "http://${aws_instance.web.public_ip}/"
}

output "assets_bucket" {
  description = "Name of the S3 bucket."
  value       = aws_s3_bucket.assets.bucket
}

output "uploaded_objects" {
  description = "S3 URIs of the uploaded objects."
  value = [
    "s3://${aws_s3_bucket.assets.bucket}/${aws_s3_object.index.key}",
    "s3://${aws_s3_bucket.assets.bucket}/${aws_s3_object.deployment_record.key}",
  ]
}
