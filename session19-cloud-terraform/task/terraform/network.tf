# VPC: my private address space in the region.
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true # instances get public DNS names

  tags = { Name = "${local.name}-vpc" }
}

# Public subnet in one AZ. map_public_ip_on_launch gives every instance here a
# public IPv4 address automatically.
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id # implicit dependency on the VPC
  cidr_block              = var.public_subnet_cidr
  availability_zone       = local.az
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name}-public-${local.az}"
    Tier = "public"
  }
}

# Internet gateway: the VPC's door to the internet.
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "${local.name}-igw" }
}

# Route table: "anything not local goes to the internet gateway".
# The 10.20.0.0/16 local route is added by AWS automatically.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = { Name = "${local.name}-public-rt" }
}

# The association is what actually makes the subnet "public".
# An IGW alone does nothing until a subnet's route table points at it.
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}
