locals {
  # A resource can't be named after the workspace that creates it before
  # that workspace exists, so this only ever produces "default" until
  # Terraform workspaces are actually in use.
  env_label = terraform.workspace
}

# data "aws_vpc" "main" {
#   id = var.existing_vpc_id
# }
# data "aws_subnet" "public" {
#   id = var.existing_subnet_id
# }


# resource "aws_internet_gateway" "main" {
#   vpc_id = var.existing_vpc_id

#   tags = {
#     Name        = "kente-igw-${local.env_label}"
#     Project     = var.project_tag
#     Environment = local.env_label
#   }
# }


# resource "aws_subnet" "public" {
#   vpc_id                  = aws_vpc.main.id
#   cidr_block              = cidrsubnet(var.vpc_cidr, 4, 0)
#   map_public_ip_on_launch = true

#   tags = {
#     Name        = "kente-public-subnet-${local.env_label}"
#     Project     = var.project_tag
#     Environment = local.env_label
#   }
# }

# resource "aws_route_table" "public" {
#   vpc_id = var.existing_vpc_id

#   route {
#     cidr_block = "0.0.0.0/0"
#     gateway_id = aws_internet_gateway.main.id
#   }

#   tags = {
#     Name        = "kente-public-rt-${local.env_label}"
#     Project     = var.project_tag
#     Environment = local.env_label
#   }
# }

# resource "aws_route_table_association" "public" {
#   subnet_id      = var.existing_subnet_id
#   route_table_id = aws_route_table.public.id
# }

resource "aws_security_group" "web" {
  name        = "kente-web-sg-${local.env_label}"
  description = "Allows SSH (for Ansible) and the app12s HTTP port."
  vpc_id      = var.existing_vpc_id

  ingress {
    description = "SSH for Ansible configuration"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # tighten to your admin CIDR in a real deployment
  }

  ingress {
    description = "Kente Retail order-service"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "kente-web-sg-${local.env_label}"
    Project     = var.project_tag
    Environment = local.env_label
  }
}
