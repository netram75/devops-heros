# Two security groups, each with one job.
#   web  - what the public internet may reach: HTTP and HTTPS only.
#   node - what a Kubernetes node needs: SSH and the k3s API from the admin
#          range only, plus all traffic between members of the same group
#          (node to node, for when a second node or EKS workers are added).
# The k3s host carries both.

resource "aws_security_group" "web" {
  name        = "${local.name}-web-sg"
  description = "HTTP and HTTPS from the internet"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name}-web-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "web_http" {
  security_group_id = aws_security_group.web.id
  description       = "HTTP from anywhere"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_ingress_rule" "web_https" {
  security_group_id = aws_security_group.web.id
  description       = "HTTPS from anywhere"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_security_group" "node" {
  name        = "${local.name}-node-sg"
  description = "Kubernetes node: admin access and node-to-node traffic"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name}-node-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "node_ssh" {
  security_group_id = aws_security_group.node.id
  description       = "SSH from the admin range only"
  cidr_ipv4         = var.admin_cidr
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
}

resource "aws_vpc_security_group_ingress_rule" "node_k8s_api" {
  security_group_id = aws_security_group.node.id
  description       = "k3s API server from the admin range only"
  cidr_ipv4         = var.admin_cidr
  ip_protocol       = "tcp"
  from_port         = 6443
  to_port           = 6443
}

resource "aws_vpc_security_group_ingress_rule" "node_self" {
  security_group_id            = aws_security_group.node.id
  description                  = "All traffic between nodes in this group"
  referenced_security_group_id = aws_security_group.node.id
  ip_protocol                  = "-1"
}

# Egress lives on the node group only. Security groups are stateful, so replies
# to allowed inbound traffic leave without needing an egress rule on web.
resource "aws_vpc_security_group_egress_rule" "node_all" {
  security_group_id = aws_security_group.node.id
  description       = "All outbound (image pulls from GHCR, OS updates, k3s install)"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
