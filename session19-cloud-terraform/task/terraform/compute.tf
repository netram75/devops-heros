resource "aws_instance" "web" {
  ami                    = local.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.web.id]

  # Boot script: install nginx and serve a page that says where it runs.
  user_data = templatefile("${path.module}/templates/user_data.sh.tftpl", {
    project     = var.project_name
    environment = var.environment
    bucket      = aws_s3_bucket.assets.bucket
  })
  user_data_replace_on_change = true # a new boot script means a new instance

  # IMDSv2 only: blocks the classic SSRF trick of reading instance credentials
  # through a plain GET to 169.254.169.254.
  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 8
    encrypted   = true
  }

  # Explicit dependency. Nothing in this block references the route table
  # association, so Terraform would happily start the instance in parallel with
  # it. But user_data runs "dnf install nginx" on first boot, which needs a
  # working route to the internet at that moment. depends_on makes Terraform
  # wait until the subnet is really public.
  depends_on = [aws_route_table_association.public]

  tags = { Name = "${local.name}-web" }
}
