# ==============================================================================
# VPC
#
# Dedicated VPC for the MGN target environment. DNS support and hostnames
# are enabled so MGN replication servers can resolve AWS service endpoints.
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
# Internet Gateway
#
# Required for replication servers and cutover instances to reach AWS MGN
# service endpoints and for operators to SSH into migrated instances.
# ==============================================================================

resource "aws_internet_gateway" "mgn" {
  vpc_id = aws_vpc.mgn.id

  tags = {
    Name = "${var.name_prefix}-igw"
  }
}

# ==============================================================================
# Public Subnet
#
# Receives test and cutover instances after migration. Public IPs are
# auto-assigned so instances are reachable for post-migration validation.
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
# Staging Subnet for MGN Replication Servers
#
# MGN launches replication servers into this subnet. Separating staging from
# the public subnet limits the blast radius if a replication server is
# compromised and allows tighter NACLs on replication traffic.
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
# Public Route Table
#
# Default route via the IGW allows both the public and staging subnets to
# reach internet-hosted AWS service endpoints needed by MGN replication.
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

# Associates the public subnet with the internet-routable route table.
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Staging subnet also needs internet access for MGN service API calls.
resource "aws_route_table_association" "staging" {
  subnet_id      = aws_subnet.staging.id
  route_table_id = aws_route_table.public.id
}
