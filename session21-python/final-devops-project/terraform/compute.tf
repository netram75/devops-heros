# Single-node Kubernetes host. k3s is a full, CNCF-certified Kubernetes in one
# binary, so the same manifests and Helm chart used on minikube run here
# without an EKS control plane bill. It sits in a public subnet so the k3s
# Traefik ingress can answer on 80/443 directly.
resource "aws_instance" "k3s" {
  ami                    = local.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.web.id, aws_security_group.node.id]
  iam_instance_profile   = aws_iam_instance_profile.node.name

  user_data = templatefile("${path.module}/templates/k3s-user-data.sh.tftpl", {
    k3s_version = var.k3s_version
    app_image   = var.app_image
    bucket      = aws_s3_bucket.artifacts.bucket
    environment = var.environment
  })
  user_data_replace_on_change = true

  # IMDSv2 only, so a plain GET to 169.254.169.254 cannot read the role's keys.
  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 20 # container images need room
    encrypted   = true
  }

  # Nothing above references the route table association, but user_data
  # downloads k3s on first boot, so the subnet must already route to the IGW.
  depends_on = [aws_route_table_association.public]

  tags = { Name = "${local.name}-k3s" }
}
