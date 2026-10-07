output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.main.id
}

output "availability_zones" {
  description = "The two AZs the subnets are spread across."
  value       = local.azs
}

output "public_subnet_ids" {
  description = "Public subnet IDs (one per AZ)."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs (one per AZ)."
  value       = aws_subnet.private[*].id
}

output "nat_gateway_id" {
  description = "NAT gateway ID, or null when enable_nat_gateway = false."
  value       = one(aws_nat_gateway.nat[*].id)
}

output "security_group_ids" {
  description = "Security groups by role."
  value = {
    web  = aws_security_group.web.id
    node = aws_security_group.node.id
  }
}

output "k3s_instance_id" {
  description = "ID of the k3s host."
  value       = aws_instance.k3s.id
}

output "k3s_public_ip" {
  description = "Public IPv4 of the k3s host."
  value       = aws_instance.k3s.public_ip
}

output "app_url" {
  description = "Where the app answers through the k3s ingress on real AWS."
  value       = "http://${aws_instance.k3s.public_ip}/"
}

output "node_role_arn" {
  description = "IAM role the k3s host runs as."
  value       = aws_iam_role.node.arn
}

output "artifacts_bucket" {
  description = "Name of the artifacts bucket."
  value       = aws_s3_bucket.artifacts.bucket
}

output "container_registry" {
  description = "Where images live. GHCR, because LocalStack community has no ECR."
  value       = split("/", var.app_image)[0]
}

output "eks_cluster_name" {
  description = "EKS cluster name, or null while enable_eks = false."
  value       = one(aws_eks_cluster.main[*].name)
}
