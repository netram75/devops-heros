# Bucket names are global across all AWS accounts, so add 4 random bytes.
# The value is stored in state and stays the same on every later plan.
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "assets" {
  bucket        = "${local.name}-assets-${random_id.bucket_suffix.hex}"
  force_destroy = true # lab bucket: let destroy remove the objects too

  tags = { Name = "${local.name}-assets" }
}

resource "aws_s3_bucket_public_access_block" "assets" {
  bucket = aws_s3_bucket.assets.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "assets" {
  bucket = aws_s3_bucket.assets.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Static file uploaded from the repo. etag = MD5 of the file, so editing
# site/index.html shows up as a change in the next plan.
resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.assets.id
  key          = "site/index.html"
  source       = "${path.module}/site/index.html"
  etag         = filemd5("${path.module}/site/index.html")
  content_type = "text/html"
}

# A small JSON "deployment record" built from other resources' attributes.
# Because it references the instance, VPC and subnet, Terraform knows (with no
# depends_on) that it must be created last and destroyed first.
resource "aws_s3_object" "deployment_record" {
  bucket       = aws_s3_bucket.assets.id
  key          = "deployments/${var.environment}.json"
  content_type = "application/json"
  content = jsonencode({
    project     = var.project_name
    environment = var.environment
    region      = var.aws_region
    vpc_id      = aws_vpc.main.id
    subnet_id   = aws_subnet.public.id
    instance_id = aws_instance.web.id
    private_ip  = aws_instance.web.private_ip
    ami_id      = aws_instance.web.ami
  })
}
