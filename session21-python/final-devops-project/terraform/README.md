# Terraform: AWS infrastructure for the final project

The full write-up with real output and screenshots is in
[../docs/terraform.md](../docs/terraform.md). This file is the quick reference.

## What it creates (default tfvars, 32 resources)

| File | Resources |
|------|-----------|
| `network.tf` | VPC 10.21.0.0/16, 2 public + 2 private subnets in 2 AZs, internet gateway, 1 Elastic IP + NAT gateway, public and private route tables + 4 associations |
| `security.tf` | `web` SG (80, 443 from anywhere), `node` SG (22 and 6443 from `admin_cidr`, all traffic from itself, all egress) |
| `iam.tf` | IAM role for the k3s host, inline policy limited to the artifacts bucket, instance profile |
| `compute.tf` | one EC2 instance (t3.small, Amazon Linux 2023, IMDSv2 only, encrypted gp3) whose user_data installs k3s |
| `storage.tf` | S3 artifacts bucket: versioning, AES256 encryption, all four public access blocks, plus a deployment record object |
| `eks.tf` | EKS cluster + managed node group + their IAM roles, all `count = 0` unless `enable_eks = true` |

There is no ECR repository: LocalStack community has no ECR API, so the images stay in
GHCR (`ghcr.io/netram75/devops-heros-final`), which is where the CI pipeline pushes them.

## Run it against LocalStack

```bash
# keep the AWS CLI away from any real profile on this machine
export AWS_CONFIG_FILE=/dev/null AWS_SHARED_CREDENTIALS_FILE=/dev/null
export AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=ap-south-1

docker run -d --name netram-s21-localstack -p 4578:4566 localstack/localstack:4.14.0

terraform init
terraform fmt -check -recursive
terraform validate
terraform plan -out=s21.tfplan
terraform apply -auto-approve s21.tfplan
terraform output
terraform destroy -auto-approve

docker rm -f netram-s21-localstack
```

## Run it against real AWS

Set `use_localstack = false` and `admin_cidr = "<your IP>/32"` in `terraform.tfvars`, log in
with your normal AWS credentials, and run the same commands. Set `enable_eks = true` only if you
want (and are willing to pay for) the EKS cluster; the validation in `variables.tf` refuses
`enable_eks = true` together with `use_localstack = true`.

## Inputs worth knowing

| Variable | Default | Checked by validation |
|----------|---------|-----------------------|
| `use_localstack` | `false` (tfvars: `true`) | |
| `localstack_endpoint` | `http://localhost:4566` (tfvars: `:4578`) | must be a URL with no path |
| `project_name` | `netram-final` | 3-21 chars, lowercase, hyphens |
| `environment` | `dev` | dev, staging or prod |
| `vpc_cidr` | `10.21.0.0/16` | /16 to /24 |
| `public_subnet_cidrs`, `private_subnet_cidrs` | two /24s each | exactly two, each inside `vpc_cidr` |
| `enable_nat_gateway` | `true` | |
| `admin_cidr` | `203.0.113.10/32` | not `0.0.0.0/0` |
| `instance_type` | `t3.small` | t3/t3a small or medium (k3s needs ~2 GB) |
| `k3s_version` | `v1.31.4+k3s1` | `vX.Y.Z+k3sN` |
| `app_image` | `ghcr.io/netram75/devops-heros-final:latest` | `registry/name:tag` |
| `enable_eks` | `false` | cannot be true with LocalStack |

## Committed vs ignored

Committed: `*.tf`, `templates/`, `terraform.tfvars` (no secrets), `.terraform.lock.hcl`,
`README.md`, `.gitignore`. Ignored: `.terraform/`, `*.tfstate*`, `*.tfplan`.
