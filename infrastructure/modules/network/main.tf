data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  # Project, Environment, ManagedBy are applied via provider default_tags at the environment root.
  # Module-level tags add only what the module owns (Service) and per-resource Name/Tier.
  common_tags = {
    Service = "network"
  }

  public_subnets = {
    public_a = {
      cidr     = "10.0.1.0/24"
      az_index = 0
      name     = "public-1"
    }
    public_b = {
      cidr     = "10.0.2.0/24"
      az_index = 1
      name     = "public-2"
    }
  }

  private_subnets = {
    private_a = {
      cidr     = "10.0.10.0/24"
      az_index = 0
      name     = "private-1"
    }
    private_b = {
      cidr     = "10.0.11.0/24"
      az_index = 1
      name     = "private-2"
    }
  }
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-vpc"
  })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-igw"
  })
}

resource "aws_subnet" "public" {
  for_each = local.public_subnets

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value.cidr
  availability_zone       = data.aws_availability_zones.available.names[each.value.az_index]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name     = "${var.project_name}-${var.environment}-${each.value.name}"
    Tier     = "public"
    Subnet   = each.value.name
  })
}

resource "aws_subnet" "private" {
  for_each = local.private_subnets

  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value.cidr
  availability_zone = data.aws_availability_zones.available.names[each.value.az_index]

  tags = merge(local.common_tags, {
    Name     = "${var.project_name}-${var.environment}-${each.value.name}"
    Tier     = "private"
    Subnet   = each.value.name
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-nat-eip"
  })
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public["public_a"].id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-nat"
  })

  depends_on = [aws_internet_gateway.main]
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-private-rt"
  })
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}
