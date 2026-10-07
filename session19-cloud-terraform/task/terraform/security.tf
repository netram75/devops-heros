# Security group = stateful firewall attached to the instance's network card.
# Rules are separate resources (the style the AWS provider recommends since v5),
# so adding or removing one rule never rewrites the others.
resource "aws_security_group" "web" {
  name        = "${local.name}-web-sg"
  description = "HTTP and HTTPS from anywhere, SSH only from one admin range"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name}-web-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.web.id
  description       = "HTTP from anywhere"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  security_group_id = aws_security_group.web.id
  description       = "HTTPS from anywhere"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.web.id
  description       = "SSH from the admin range only"
  cidr_ipv4         = var.allowed_ssh_cidr
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
}

# Outbound: allow everything (needed for dnf updates). Security groups are
# stateful, so replies to allowed inbound traffic do not need an egress rule.
resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.web.id
  description       = "All outbound"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
