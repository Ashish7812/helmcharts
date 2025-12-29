# FILE: main.tf

terraform {
  required_version = ">= 1.3"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# -----------------------------------------------------------------------------
# VPC (Virtual Private Cloud)
# This creates the main network boundary for the EKS cluster.
# -----------------------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.cluster_name}-vpc"
    # This tag is REQUIRED for EKS to manage resources (like Load Balancers) in this VPC.
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

# -----------------------------------------------------------------------------
# Subnets
# We create public subnets (for internet-facing resources like LBs and NAT Gateways)
# and private subnets (for your worker nodes, for security).
# -----------------------------------------------------------------------------

# Create one public subnet in each specified Availability Zone.
resource "aws_subnet" "public" {
  # `for_each` creates a resource for each AZ, making the configuration resilient.
  for_each = toset(var.availability_zones)

  vpc_id                  = aws_vpc.main.id
  availability_zone       = each.key
  map_public_ip_on_launch = true # Instances in public subnets can get a public IP.

  # Calculate a unique /19 CIDR block for each public subnet.
  cidr_block = cidrsubnet(var.vpc_cidr_block, 8, index(var.availability_zones, each.key))

  tags = {
    Name = "${var.cluster_name}-public-${each.key}"
    # This tag is REQUIRED for EKS to discover these subnets for public-facing load balancers.
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                    = "1"
  }
}

# Create one private subnet in each specified Availability Zone for the worker nodes.
resource "aws_subnet" "private" {
  for_each = toset(var.availability_zones)

  vpc_id            = aws_vpc.main.id
  availability_zone = each.key

  # Calculate a unique /19 CIDR block for each private subnet.
  # We offset the `newbits` from the public subnets to ensure there is no CIDR overlap.
  cidr_block = cidrsubnet(var.vpc_cidr_block, 8, index(var.availability_zones, each.key) + length(var.availability_zones))

  tags = {
    Name = "${var.cluster_name}-private-${each.key}"
    # This tag is REQUIRED for EKS to discover these subnets for internal load balancers and node communication.
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"           = "1"
  }
}

# -----------------------------------------------------------------------------
# Internet Connectivity: IGW, NAT Gateways, and Elastic IPs
# -----------------------------------------------------------------------------

# Create a single Internet Gateway for the VPC.
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "${var.cluster_name}-igw"
  }
}

# Create a persistent Elastic IP for each NAT Gateway (one per AZ).
resource "aws_eip" "nat" {
  for_each   = aws_subnet.public
  domain     = "vpc"
  depends_on = [aws_internet_gateway.main]
  tags = {
    Name = "${var.cluster_name}-nat-eip-${each.key}"
  }
}

# Create a NAT Gateway in each public subnet for high availability.
# This allows nodes in private subnets to access the internet for outbound traffic.
resource "aws_nat_gateway" "main" {
  for_each = aws_subnet.public

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = each.value.id
  tags = {
    Name = "${var.cluster_name}-nat-${each.key}"
  }
}

# -----------------------------------------------------------------------------
# Routing
# We need separate route tables for public and private subnets.
# -----------------------------------------------------------------------------

# Create a single route table for all public subnets.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  # Route all internet-bound traffic (0.0.0.0/0) to the Internet Gateway.
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.cluster_name}-public-rt"
  }
}

# Associate the public route table with each public subnet.
resource "aws_route_table_association" "public" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# Create a dedicated private route table for each AZ for high availability.
resource "aws_route_table" "private" {
  for_each = aws_subnet.private
  vpc_id   = aws_vpc.main.id

  # Route all internet-bound traffic from this private subnet to its corresponding NAT Gateway in the same AZ.
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[each.key].id
  }

  tags = {
    Name = "${var.cluster_name}-private-rt-${each.key}"
  }
}

# Associate each private route table with its corresponding private subnet.
resource "aws_route_table_association" "private" {
  for_each       = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}
