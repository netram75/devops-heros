# Optional managed Kubernetes. Every resource here has count = 0 unless
# enable_eks = true, so with the default tfvars Terraform validates this file
# but plans nothing from it. Why it is off:
#   - LocalStack community has no EKS API (EKS is a LocalStack Pro feature).
#   - On real AWS the control plane alone is billed per hour, plus the nodes
#     and the NAT gateway they need, for a project that runs fine on one k3s VM.
# The variable validation in variables.tf stops enable_eks = true together
# with use_localstack = true before any API call is made.

locals {
  eks_count = var.enable_eks ? 1 : 0
}

data "aws_iam_policy_document" "eks_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_cluster" {
  count              = local.eks_count
  name               = "${local.name}-eks-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.eks_assume.json
}

resource "aws_iam_role_policy_attachment" "eks_cluster" {
  count      = local.eks_count
  role       = aws_iam_role.eks_cluster[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_eks_cluster" "main" {
  count    = local.eks_count
  name     = "${local.name}-eks"
  version  = var.eks_version
  role_arn = aws_iam_role.eks_cluster[0].arn

  vpc_config {
    subnet_ids              = concat(aws_subnet.private[*].id, aws_subnet.public[*].id)
    endpoint_public_access  = true
    endpoint_private_access = true
  }

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  depends_on = [aws_iam_role_policy_attachment.eks_cluster]
}

# Worker nodes reuse the EC2 assume-role document from iam.tf.
resource "aws_iam_role" "eks_node" {
  count              = local.eks_count
  name               = "${local.name}-eks-node-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "eks_node" {
  for_each = var.enable_eks ? toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
  ]) : toset([])

  role       = aws_iam_role.eks_node[0].name
  policy_arn = each.value
}

# Nodes go in the private subnets; they reach GHCR through the NAT gateway.
resource "aws_eks_node_group" "main" {
  count           = local.eks_count
  cluster_name    = aws_eks_cluster.main[0].name
  node_group_name = "${local.name}-ng"
  node_role_arn   = aws_iam_role.eks_node[0].arn
  subnet_ids      = aws_subnet.private[*].id
  instance_types  = ["t3.medium"]

  scaling_config {
    min_size     = 1
    desired_size = 2
    max_size     = 3
  }

  depends_on = [aws_iam_role_policy_attachment.eks_node]
}
