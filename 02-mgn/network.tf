# ==============================================================================
# VPC
# ==============================================================================

resource "aws_vpc" "mgn" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.name_prefix}-vpc"
  }
}

# ==============================================================================
# Internet gateway
# ==============================================================================

resource "aws_internet_gateway" "mgn" {
  vpc_id = aws_vpc.mgn.id

  tags = {
    Name = "${var.name_prefix}-igw"
  }
}

# ==============================================================================
# Public subnet
# ==============================================================================

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.mgn.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.name_prefix}-public-subnet"
  }
}

# ==============================================================================
# Staging subnet for MGN replication servers
# ==============================================================================

resource "aws_subnet" "staging" {
  vpc_id            = aws_vpc.mgn.id
  cidr_block        = var.staging_subnet_cidr
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "${var.name_prefix}-staging-subnet"
  }
}

# ==============================================================================
# Public route table
# ==============================================================================

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.mgn.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.mgn.id
  }

  tags = {
    Name = "${var.name_prefix}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "staging" {
  subnet_id      = aws_subnet.staging.id
  route_table_id = aws_route_table.public.id
}