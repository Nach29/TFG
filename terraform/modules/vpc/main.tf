# =============================================================================
# VPC MODULE — main.tf
#
# Creates:
#   - 1 VPC
#   - 1 Internet Gateway
#   - 3 Public subnets (one per AZ)
#   - 3 Private subnets (one per AZ)
#   - 1 Elastic IP + 1 NAT Gateway (cost optimisation: single NAT shared by all AZs)
#   - 1 Public route table  + associations
#   - 1 Private route table + associations (all AZs route through the single NAT GW)
# =============================================================================

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = var.enable_dns_hostnames
  enable_dns_support   = var.enable_dns_support

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# ---------------------------------------------------------------------------
# Internet Gateway — provides internet access for public subnets
# ---------------------------------------------------------------------------
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# ---------------------------------------------------------------------------
# Public subnets — one per AZ, instances here get public IPs
# ---------------------------------------------------------------------------
resource "aws_subnet" "public" {
  count = length(var.availability_zones)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-subnet-${count.index + 1}"
    Tier = "Public"
    AZ   = var.availability_zones[count.index]
  }
}

# ---------------------------------------------------------------------------
# Private subnets — one per AZ, no public IPs assigned
# ---------------------------------------------------------------------------
resource "aws_subnet" "private" {
  count = length(var.availability_zones)

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "${var.project_name}-private-subnet-${count.index + 1}"
    Tier = "Private"
    AZ   = var.availability_zones[count.index]
  }
}

# ---------------------------------------------------------------------------
# Single NAT Gateway — COST OPTIMISATION
# One NAT GW deployed in public-subnet-1 (AZ-a).
# All three private subnets share it via a single private route table.
# Trade-off: if AZ-a fails, private instances in AZ-b/c lose internet
# (SSM connectivity breaks). Acceptable for this TFG cost constraint.
# ---------------------------------------------------------------------------
resource "aws_eip" "nat" {
  domain = "vpc"

  # EIPs require IGW to be attached first
  depends_on = [aws_internet_gateway.this]

  tags = {
    Name = "${var.project_name}-nat-eip"
  }
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id # Placed in AZ-a public subnet

  depends_on = [aws_internet_gateway.this]

  tags = {
    Name = "${var.project_name}-nat-gw"
  }
}

# ---------------------------------------------------------------------------
# Route table — Public (0.0.0.0/0 → IGW)
# ---------------------------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ---------------------------------------------------------------------------
# Route table — Private (0.0.0.0/0 → single NAT GW, shared by all AZs)
# ---------------------------------------------------------------------------
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this.id
  }

  tags = {
    Name = "${var.project_name}-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
