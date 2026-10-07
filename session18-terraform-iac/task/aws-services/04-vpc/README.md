# Session 18 - AWS Services - VPC

- **Name:** Netram
- **Enrollment No:** 24BCS10329

> Category: **Networking**. A VPC is my own private network inside an AWS region: I choose the IP range, cut it into subnets and decide what can reach what.

---

## What is VPC

A VPC (Virtual Private Cloud) is a **logically isolated virtual network** in one region. Nothing gets in or out unless I add a path (a gateway plus a route) and the firewalls allow it. EC2 instances, RDS databases, load balancers and Lambda functions attached to a VPC all get their private IPs from it.

The layout I use as a reference for the rest of these notes, in `ap-south-1` (Mumbai):

```text
VPC 10.0.0.0/16 (ap-south-1)
|
+-- Internet Gateway (one per VPC)
|
+-- AZ ap-south-1a
|     +-- public-a   10.0.1.0/24   ALB, NAT Gateway        0.0.0.0/0 -> IGW
|     +-- private-a  10.0.11.0/24  app servers, RDS        0.0.0.0/0 -> NAT-a
|
+-- AZ ap-south-1b
      +-- public-b   10.0.2.0/24   ALB, NAT Gateway        0.0.0.0/0 -> IGW
      +-- private-b  10.0.12.0/24  app servers, RDS        0.0.0.0/0 -> NAT-b
```

A VPC spans every AZ in its region, but each **subnet lives in exactly one AZ**. That is why the layout repeats per AZ: if one AZ has an outage, the copy in the other keeps serving.

Every region also has a **default VPC** (`172.31.0.0/16`, a public `/20` subnet per AZ, an Internet Gateway attached). It is handy for quick tests, but every default subnet is public, so I would build my own VPC for anything real. The VPC itself is free; the costs come from NAT gateways, public IPv4 addresses, interface endpoints and data transfer.

## CIDR

CIDR notation describes an IP range as `base address / prefix length`. In `10.0.0.0/16`, the first 16 bits are fixed and the remaining 16 are free, so the range holds 2^16 = 65,536 addresses (`10.0.0.0` to `10.0.255.255`).

| CIDR | Addresses | Usable in an AWS subnet (minus 5 reserved) | Typical use |
|---|---|---|---|
| `/16` | 65,536 | n/a (VPC size) | Largest allowed VPC |
| `/20` | 4,096 | 4,091 | Default VPC subnets, large EKS subnets |
| `/24` | 256 | 251 | Normal subnet |
| `/28` | 16 | 11 | Smallest allowed subnet or VPC |

Rules and reasons:

- A VPC's IPv4 block must be between `/16` and `/28`. More blocks (secondary CIDRs) and an IPv6 `/56` can be added later.
- Use **private RFC 1918 ranges** (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`).
- **Never overlap** with other VPCs, the office network or anything I might connect later. Peering, Transit Gateway and VPN cannot route between overlapping ranges, and renumbering a live VPC is painful.
- One gotcha from the Docker sessions: Docker's default bridge is `172.17.0.0/16`. A VPC in that range causes confusing routing on Docker hosts, which is one more reason I stick to `10.x`.

## Subnets

A subnet is a **slice of the VPC's CIDR placed in one AZ**. Resources launch into subnets, not into the VPC directly.

AWS reserves **five addresses in every subnet**. For `10.0.1.0/24` these are `.0` (network address), `.1` (VPC router), `.2` (Amazon DNS resolver), `.3` (reserved for future use) and `.255` (broadcast, which VPCs do not support but still reserve). So a `/24` gives 251 usable IPs, and a `/28` only 11. EKS pods and Lambda functions in a VPC consume IPs fast, so I size subnets generously; a subnet cannot be resized after creation.

Many services require subnets in **at least two AZs**: an Application Load Balancer and an RDS DB subnet group both refuse a single-AZ setup. Planning two (or three) AZs from day one avoids rebuilding later.

## Route tables

A route table is a list of **destination CIDR -> target** rules that decide where packets leaving a subnet go.

- Every subnet is associated with **exactly one** route table. Without an explicit association it uses the VPC's **main** route table.
- Every table has a **local route** for the VPC CIDR that cannot be removed, so all subnets in a VPC can always reach each other (firewalls permitting).
- When several routes match, the **most specific prefix wins**.

| Public route table | | Private route table (AZ a) | |
|---|---|---|---|
| **Destination** | **Target** | **Destination** | **Target** |
| `10.0.0.0/16` | `local` | `10.0.0.0/16` | `local` |
| `0.0.0.0/0` | Internet Gateway | `0.0.0.0/0` | NAT Gateway in AZ a |
| | | S3 prefix list (`pl-...`) | S3 gateway endpoint |

```bash
aws ec2 create-route --route-table-id "$PUBLIC_RT" \
  --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW_ID"
aws ec2 associate-route-table --route-table-id "$PUBLIC_RT" --subnet-id "$PUBLIC_A"
```

I keep the main route table private (local route only) and explicitly associate public subnets with the public table. That way a newly created subnet that someone forgot to associate is private by default, not accidentally exposed.

## Internet Gateway

An Internet Gateway (IGW) is the **VPC's door to the internet**. It is attached to one VPC (one IGW per VPC), is horizontally scaled and redundant by AWS, has no bandwidth limit of its own and no hourly charge.

It does two jobs: it is the target for `0.0.0.0/0` in public route tables, and it performs **1:1 NAT** between an instance's private IP and its public IPv4. For an instance to be reachable from the internet, **all** of these must be true:

1. The instance has a public IPv4 or Elastic IP.
2. Its subnet's route table sends `0.0.0.0/0` to the IGW.
3. The security group and Network ACL allow the traffic.

For IPv6, where addresses are already public, an **egress-only internet gateway** gives private subnets outbound access while blocking inbound connections.

## NAT Gateway

A NAT Gateway lets instances in **private subnets start outbound connections** (OS updates, package installs, calling external APIs) while nothing on the internet can start a connection to them. It translates their private source IPs to its own Elastic IP.

How the standard (zonal) NAT gateway works and why it is set up the way it is:

- It is created in a **public subnet** with an **Elastic IP**, and private route tables send `0.0.0.0/0` to it.
- It lives in **one AZ**. For high availability I create **one per AZ** and point each private subnet at the NAT in its own AZ. Sharing one NAT across AZs means an AZ outage cuts egress for everyone, and adds cross-AZ data charges.
- It is **billed per hour and per GB processed** (in `us-east-1` about $0.045 for each), on top of normal data transfer. A NAT gateway left running in a lab account is one of the classic surprise bills.
- It scales automatically from 5 Gbps up to 100 Gbps.

Since November 2025 there is also a **regional NAT gateway** mode: one NAT gateway that expands across AZs automatically and does not need a public subnet. It removes the per-AZ wiring, but the per-AZ design above is still what most existing setups and tutorials use.

To cut NAT cost, traffic to S3 and DynamoDB should go through **gateway VPC endpoints**, which are free and keep that traffic off the NAT entirely.

## Security Groups

Security groups are **stateful, allow-only firewalls attached to network interfaces** (details and CLI examples in the [EC2 notes](../02-ec2/README.md)). In VPC design their real power is **referencing each other**, which builds tiers without hard-coding a single IP:

| Security group | Inbound rule | Source |
|---|---|---|
| `alb-sg` | TCP 443 | `0.0.0.0/0` |
| `web-sg` | TCP 8080 | `alb-sg` |
| `db-sg` | TCP 5432 | `web-sg` |

The database is reachable only from web servers, and web servers only from the load balancer, no matter how many instances Auto Scaling adds.

## Network ACLs

A Network ACL (NACL) is a **stateless firewall at the subnet boundary**. Every packet entering or leaving the subnet is checked, and because it is stateless, **return traffic needs its own rule**.

- Rules are **numbered** and evaluated **lowest number first**; the first match wins. A final `*` rule denies everything else.
- Rules can **allow or deny**. This is the one place I can block a specific bad IP range, which security groups cannot do.
- The **default** NACL allows all traffic in and out. A **custom** NACL denies everything until rules are added.
- Each subnet has exactly one NACL; one NACL can serve many subnets.

Inbound rules for a public web subnet that also blocks one abusive range:

| Rule # | Type | Port range | Source | Action |
|---|---|---|---|---|
| 90 | All traffic | All | `203.0.113.0/24` (abusive range) | DENY |
| 100 | HTTPS | 443 | `0.0.0.0/0` | ALLOW |
| 120 | Custom TCP | 1024-65535 | `0.0.0.0/0` | ALLOW |
| `*` | All | All | `0.0.0.0/0` | DENY |

Why the numbers matter: if the deny were rule 110 instead of 90, rule 100 would match HTTPS from that range first and the deny would never fire. Rule 120 exists only because NACLs are stateless: replies to the instances' own outbound requests (package downloads, API calls) come back on ephemeral ports. The outbound rules need the mirror image, including ephemeral ports so responses can reach clients.

| | Security Group | Network ACL |
|---|---|---|
| Applies to | Network interface (instance level) | Subnet (every resource in it) |
| State | **Stateful**: replies allowed automatically | **Stateless**: replies need explicit rules |
| Rule types | Allow only | Allow and deny |
| Evaluation | All rules considered together | In number order, first match wins |
| Default | New SG: no inbound, all outbound | Default NACL: allow all; custom NACL: deny all |
| Can reference | Other security groups | CIDR ranges only |
| Typical role | Main, fine-grained firewall | Coarse guardrail, explicit IP blocks |

In practice I do almost everything with security groups and leave NACLs at the default, adding NACL denies only for specific blocks or compliance boundaries.

## Public vs private subnet

There is no "public" checkbox on a subnet. A subnet is **public because its route table has a route to an Internet Gateway**, and private because it does not.

| | Public subnet | Private subnet |
|---|---|---|
| Route for `0.0.0.0/0` | Internet Gateway | NAT Gateway, or none at all |
| Instances get public IPs | Usually (`map_public_ip_on_launch`) | No |
| Inbound from the internet | Possible, if SG/NACL allow | Not possible |
| Outbound to the internet | Directly through the IGW | Through NAT, or not at all (isolated) |
| What goes here | Load balancers, NAT gateways, bastions if any | App servers, databases, caches, internal services |

The rule I follow: only things that **must** accept connections from the internet go public, which is usually just the load balancer. Everything else stays private, so even a wrong security group rule cannot expose it directly.

## How this shows up in Terraform

The public half of the layout above, plus the `web` security group that the [EC2 notes](../02-ec2/README.md) refer to:

```hcl
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags                 = { Name = "session18-vpc" }
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-south-1a"
  map_public_ip_on_launch = true
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "web" {
  name   = "session18-web"
  vpc_id = aws_vpc.main.id
}

resource "aws_vpc_security_group_ingress_rule" "web_https" {
  security_group_id = aws_security_group.web.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_egress_rule" "web_all_out" {
  security_group_id = aws_security_group.web.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
```

The egress rule is not optional: when Terraform creates a security group it **removes AWS's default allow-all outbound rule**, so without it the instance could not reach anything. The private side follows the same pattern with `aws_eip` (`domain = "vpc"`), `aws_nat_gateway` in `public_a`, and a second route table whose `0.0.0.0/0` route uses `nat_gateway_id`.
