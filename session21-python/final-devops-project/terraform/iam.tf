# The k3s host gets an IAM role instead of access keys on disk. EC2 can only
# attach a role through an instance profile, so both are needed.

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${local.name}-k3s-node-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json

  tags = { Name = "${local.name}-k3s-node-role" }
}

# Least privilege: the node may list the artifacts bucket and read/write
# objects in it (backups of the k3s state, build artifacts), nothing else.
data "aws_iam_policy_document" "artifacts_rw" {
  statement {
    sid       = "ListArtifactsBucket"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.artifacts.arn]
  }

  statement {
    sid       = "ReadWriteArtifacts"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["${aws_s3_bucket.artifacts.arn}/*"]
  }
}

resource "aws_iam_role_policy" "artifacts_rw" {
  name   = "artifacts-bucket-rw"
  role   = aws_iam_role.node.id
  policy = data.aws_iam_policy_document.artifacts_rw.json
}

resource "aws_iam_instance_profile" "node" {
  name = "${local.name}-k3s-node-profile"
  role = aws_iam_role.node.name
}
