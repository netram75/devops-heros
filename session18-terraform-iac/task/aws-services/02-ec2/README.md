# Session 18 - AWS Services - EC2

- **Name:** Netram
- **Enrollment No:** 24BCS10329

> Category: **Compute**. EC2 rents virtual machines by the second, inside a VPC I control.

---

## What is EC2

EC2 (Elastic Compute Cloud) gives me virtual servers, called **instances**, that I can start in minutes and delete when I am done. I choose the operating system (through an AMI), the hardware shape (instance type), the disk (EBS), the network placement (VPC subnet) and the firewall (security groups). AWS runs the physical hosts and the hypervisor (the Nitro System); everything from the OS upwards is my job: patching, hardening, monitoring.

That split is the main reason to pick EC2 over Lambda or Fargate. I get full control of the machine, which suits long-running processes, custom kernels, GPUs or software that expects a normal Linux box. The price is that I own the operating system.

How I pay for it changes the bill a lot:

| Model | How it works | When I would use it |
|---|---|---|
| On-Demand | Per-second billing (Linux, 60 s minimum), no commitment | Dev, spiky or short-lived work |
| Savings Plans / Reserved | 1 or 3 year commitment, up to 72% cheaper | Steady 24x7 production |
| Spot | Spare capacity, up to 90% cheaper, 2-minute interruption notice | CI runners, batch, stateless workers |

## AMI

An **AMI (Amazon Machine Image)** is the template an instance boots from. It contains the root volume snapshot (OS plus anything pre-installed), the block device mapping (which volumes to create), the CPU architecture (x86_64 or arm64) and launch permissions (who may use it).

Key points:

- **AMIs are regional.** The same Amazon Linux release has a different AMI ID in `ap-south-1` and `us-east-1`. That is why I never hard-code an AMI ID in Terraform; I look it up.
- **Sources:** AWS-provided (Amazon Linux 2023, Ubuntu, Windows), AWS Marketplace, community AMIs (use with care), and my own.
- **Amazon Linux 2 reached end of support on 30 June 2026.** New work should use **Amazon Linux 2023** (supported to June 2029).
- **Golden AMIs:** baking the app and its dependencies into a custom AMI (Packer or EC2 Image Builder) makes instances boot ready to serve, which matters for Auto Scaling.

```bash
# Latest AL2023 AMI ID for the current region, from the public SSM parameter
aws ssm get-parameter \
  --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --query Parameter.Value --output text

# Bake a custom AMI from a configured instance (reboots it unless --no-reboot)
aws ec2 create-image --instance-id "$INSTANCE_ID" --name "web-golden-2026-10-07"
```

## Instance types

The instance type decides vCPU, memory, network and storage performance. The name is structured, so reading it tells me most of what I need:

```text
m7g.xlarge
| |   |
| |   +-- size: nano, micro, small, medium, large, xlarge, 2xlarge ... (each step roughly doubles)
| +------ attributes: g = Graviton (ARM), i = Intel, a = AMD, d = local NVMe, n = extra network
+-------- family "m", generation "7"
```

| Family | Category | Memory per vCPU (rough) | Typical workload |
|---|---|---|---|
| `t` (t3, t4g) | General purpose, burstable | varies | Low, spiky load: dev boxes, small sites |
| `m` (m7i, m7g, m8g) | General purpose | 4 GiB | App servers, balanced workloads |
| `c` (c7i, c7g, c8g) | Compute optimized | 2 GiB | CPU-bound: encoding, builds, batch |
| `r`, `x` (r7g, r8g, x2idn) | Memory optimized | 8 GiB or more | Databases, in-memory caches |
| `i`, `d` (i4i, d3) | Storage optimized | varies | Local NVMe, high IOPS, big data |
| `p`, `g`, `inf`, `trn` | Accelerated | varies | ML training and inference, graphics |

Two things I keep in mind:

- **Burstable `t` instances** earn CPU credits while idle and spend them when busy. `t3`/`t4g` launch in *unlimited* mode by default, so a pegged CPU does not throttle but quietly adds charges.
- **Graviton (`g`)** is usually the best price-performance, but every binary and Docker image must be built for arm64. Multi-arch images (from the Docker sessions) make that painless.

## Key pairs

A key pair is the SSH credential for Linux instances. AWS keeps the **public key** and injects it into `~/.ssh/authorized_keys` at first boot; the **private key** is shown to me exactly once. Lose it and there is no download button.

```bash
aws ec2 create-key-pair --key-name netram-key --key-type ed25519 \
  --query KeyMaterial --output text > netram-key.pem
chmod 400 netram-key.pem
ssh -i netram-key.pem ec2-user@<public-ip>
```

Key pairs are regional, and ED25519 keys do not work for Windows instances (RSA is needed to decrypt the Windows password). In practice I would rather not open port 22 at all:

- **SSM Session Manager:** shell access through IAM, no inbound ports, every session logged. Needs the SSM agent (preinstalled on AL2023) and the `AmazonSSMManagedInstanceCore` policy on the instance role.
- **EC2 Instance Connect:** pushes a one-time public key valid for 60 seconds, so there is no long-lived key to lose.

## Security Groups

A security group is a **virtual firewall attached to the instance's network interface (ENI)**, not to the subnet. Its behavior:

- **Stateful.** If inbound 443 is allowed, the reply traffic goes out automatically. I never write rules for return traffic.
- **Allow rules only.** There is no deny; anything not allowed is dropped.
- **New groups:** no inbound rules, all outbound allowed.
- **Rules can reference other security groups** instead of IP ranges.

That last point is the one that matters for real architectures. Instance IPs change with Auto Scaling, but "the DB accepts 5432 from anything in the web SG" stays true no matter how many web instances exist.

```bash
aws ec2 authorize-security-group-ingress --group-id "$WEB_SG" \
  --protocol tcp --port 443 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id "$DB_SG" \
  --protocol tcp --port 5432 --source-group "$WEB_SG"
```

Changes apply immediately to running instances, and an ENI can carry up to five security groups by default. The subnet-level firewall (Network ACLs) and the full SG vs NACL comparison are in the [VPC notes](../04-vpc/README.md).

## EBS

**EBS (Elastic Block Store)** volumes are network-attached disks. They live independently of the instance, so I can stop an instance, detach a volume, or snapshot it. Each volume lives in **one Availability Zone** and can only attach to instances in that AZ; moving it means snapshot then restore elsewhere.

| Type | Media | Performance | Use |
|---|---|---|---|
| `gp3` | SSD | 3,000 IOPS and 125 MiB/s included at any size; up to 80,000 IOPS, 2,000 MiB/s, 64 TiB | Default choice: boot and most data volumes |
| `gp2` | SSD | 3 IOPS per GiB, burst credits | Legacy; migrate to gp3 |
| `io2` Block Express | SSD | Up to 256,000 IOPS, 99.999% durability | Large, latency-sensitive databases |
| `st1` | HDD | Throughput-optimized, cannot boot | Big sequential reads: logs, ETL |
| `sc1` | HDD | Cheapest, cold | Rarely read data |

Why gp3 over gp2: it is cheaper per GB and performance is no longer tied to size, so I do not have to buy a 1 TB disk just to get IOPS. Current Amazon Linux AMIs already use gp3 for the root volume, but the raw `CreateVolume` API still defaults to gp2, so I always set the type explicitly.

Other details:

- **Snapshots** are incremental, stored in S3 by AWS, and can be copied across regions for DR.
- **Encryption** uses KMS with no meaningful performance cost. "Encryption by default" is a per-region account setting I would switch on.
- **DeleteOnTermination:** the root volume is deleted with the instance by default; volumes attached later survive by default.
- **Instance store** (the `d` in `m7gd`) is fast local NVMe but **ephemeral**: data is lost on stop or terminate.

## Public vs private IP

| | Private IPv4 | Auto-assigned public IPv4 | Elastic IP |
|---|---|---|---|
| Comes from | The subnet's CIDR | Amazon's pool | Allocated to my account |
| Survives stop/start | Yes | **No**, a new one on every start | Yes |
| Visible inside the OS (`ip addr`) | Yes | No, the IGW does 1:1 NAT | No |
| Reachable from the internet | No | Yes, if route to IGW and SG allow it | Same |
| Cost | Free | $0.005 per hour | $0.005 per hour, attached or idle |

Every instance gets a private IP; it is how instances talk inside the VPC. A public IPv4 is only assigned if the subnet (or launch setting) asks for one. Since February 2024 every public IPv4 address is billed, which is one more reason to keep backends in private subnets behind a load balancer.

From inside the instance I read both through the metadata service using **IMDSv2**:

```bash
TOKEN=$(curl -sX PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4
curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4
```

Why IMDSv2 matters: the metadata service also hands out the instance role's temporary credentials. With IMDSv1 a simple SSRF bug (tricking the app into making a GET request) could fetch them. IMDSv2 requires a PUT to get a session token first, which typical SSRF cannot do. AL2023 AMIs require IMDSv2, and I enforce it in Terraform anyway.

## Instance lifecycle

```text
            launch
              |
              v
          [pending] -----------> [running] <---- reboot keeps host and IPs
              ^                   |      \
        start |              stop |       \ terminate
              |                   v        v
          [stopped] <------- [stopping]   [shutting-down] ---> [terminated]
```

| State | Compute billed? | Notes |
|---|---|---|
| pending | No | Booting, being placed on a host |
| running | Yes | Per second |
| stopping | No (yes if hibernating) | |
| stopped | No | EBS storage and Elastic IPs are still billed |
| shutting-down / terminated | No | Root volume deleted by default; termination is permanent |

The differences that actually bite:

- **Reboot** stays on the same host; public IP and instance store data are kept.
- **Stop/start** usually moves to new hardware: private IP and EBS data kept, **public IP changes**, instance store wiped.
- **Hibernate** saves RAM to the (encrypted) root volume so processes resume where they left off.
- **Terminate** is final. `disable_api_termination` (termination protection) guards important instances.

## Common use cases

- **Web and app servers** in an Auto Scaling group behind an Application Load Balancer, spread across AZs.
- **Self-hosted CI runners** (for example GitHub Actions) on Spot instances.
- **Kubernetes worker nodes** (EKS managed node groups are EC2 instances underneath).
- **Batch and data processing** on compute-optimized or Spot capacity.
- **ML training and inference** on GPU (`p`, `g`) or AWS silicon (`trn`, `inf`).
- **Lift-and-shift** of legacy apps that expect a full server.

## How this shows up in Terraform

Look up the AMI instead of hard-coding it, enforce IMDSv2, set the volume type explicitly and keep SSH closed:

```hcl
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

resource "aws_instance" "web" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public_a.id
  vpc_security_group_ids = [aws_security_group.web.id]
  iam_instance_profile   = aws_iam_instance_profile.app.name

  metadata_options {
    http_tokens = "required" # IMDSv2 only
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 20
    encrypted   = true
  }

  tags = { Name = "session18-web" }
}
```

The subnet and `aws_security_group.web` come from the [VPC notes](../04-vpc/README.md) and the instance profile from the [IAM notes](../01-iam/README.md). There is no `key_name` on purpose: with `AmazonSSMManagedInstanceCore` also attached to that role, access goes through Session Manager and there is no private key to manage.
