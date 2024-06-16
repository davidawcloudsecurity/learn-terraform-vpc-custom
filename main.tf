provider "aws" {
  region = var.region
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.7.0"
    }
  }
}

# Variables
variable "vpc-cidr-block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block range for VPC"
}

variable "public-subnet-cidr-blocks" {
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
  description = "CIDR block range for public subnets"
}

variable "private-subnet-cidr-blocks-app" {
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
  description = "CIDR block range for private app subnets"
}

variable "private-subnet-cidr-blocks-db" {
  type        = list(string)
  default     = ["10.0.5.0/24", "10.0.6.0/24"]
  description = "CIDR block range for private DB subnets"
}

variable "availability-zones" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b"]
  description = "List of availability zones for selected region"
}

variable "instance_types" {
  type    = list(string)
  default = ["t3.small"]
  description = "Instance types for EC2 instances"
}

variable "ami_id" {
  description = "AMI ID for EC2 instances"
  type        = string
  default     = "ami-0abcdef1234567890" # Update this with a valid AMI ID
}

variable "disk_size" {
  description = "Disk size in GiB for nodes"
  type        = number
  default     = 8
}

variable "desired_size" {
  description = "Desired number of instances"
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Maximum number of instances"
  type        = number
  default     = 2
}

variable "min_size" {
  description = "Minimum number of instances"
  type        = number
  default     = 1
}

variable "cluster-name" {
  description = "Cluster name"
  type        = string
  default     = "terraform-cluster"
}

variable "region" {
  type    = string
  default = "us-east-1"
}

# VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc-cidr-block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.cluster-name}-vpc"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.cluster-name}-igw"
  }
}

# Subnets
resource "aws_subnet" "public" {
  count                   = length(var.public-subnet-cidr-blocks)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public-subnet-cidr-blocks[count.index]
  availability_zone       = var.availability-zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.cluster-name}-public-subnet"
  }
}

resource "aws_subnet" "private_app" {
  count             = length(var.private-subnet-cidr-blocks-app)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private-subnet-cidr-blocks-app[count.index]
  availability_zone = var.availability-zones[count.index]

  tags = {
    Name = "${var.cluster-name}-private-subnet-app"
  }
}

resource "aws_subnet" "private_db" {
  count             = length(var.private-subnet-cidr-blocks-db)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private-subnet-cidr-blocks-db[count.index]
  availability_zone = var.availability-zones[count.index]

  tags = {
    Name = "${var.cluster-name}-private-subnet-db"
  }
}

# Route Tables and Associations
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.cluster-name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(var.public-subnet-cidr-blocks)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  vpc = true

  tags = {
    Name = "${var.cluster-name}-eip"
  }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = {
    Name = "${var.cluster-name}-nat"
  }
}

resource "aws_route_table" "private_app" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name = "${var.cluster-name}-private-app-rt"
  }
}

resource "aws_route_table_association" "private_app" {
  count          = length(var.private-subnet-cidr-blocks-app)
  subnet_id      = aws_subnet.private_app[count.index].id
  route_table_id = aws_route_table.private_app.id
}

resource "aws_route_table" "private_db" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name = "${var.cluster-name}-private-db-rt"
  }
}

resource "aws_route_table_association" "private_db" {
  count          = length(var.private-subnet-cidr-blocks-db)
  subnet_id      = aws_subnet.private_db[count.index].id
  route_table_id = aws_route_table.private_db.id
}

# Security Groups
resource "aws_security_group" "public" {
  vpc_id = aws_vpc.main.id
  name   = "${var.cluster-name}-public-sg"

  ingress {
    from_port   = 0
    to_port     = 0
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
    Name = "${var.cluster-name}-public-sg"
  }
}

resource "aws_security_group" "private" {
  vpc_id = aws_vpc.main.id
  name   = "${var.cluster-name}-private-sg"

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "tcp"
    cidr_blocks = concat(var.private-subnet-cidr-blocks-app, var.private-subnet-cidr-blocks-db)
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster-name}-private-sg"
  }
}

# EC2 Instances
resource "aws_instance" "app" {
  count         = var.desired_size
  ami           = var.ami_id
  instance_type = var.instance_types[0]
  subnet_id     = aws_subnet.private_app[count.index % length(aws_subnet.private_app)].id
  key_name      = var.key_name # Assuming you have a key_name variable

  vpc_security_group_ids = [aws_security_group.private.id]

  root_block_device {
    volume_size = var.disk_size
    volume_type = "gp2"
  }

  tags = {
    Name = "${var.cluster-name}-app-instance"
  }
}

resource "aws_instance" "db" {
  count         = var.desired_size
  ami           = var.ami_id
  instance_type = var.instance_types[0]
  subnet_id     = aws_subnet.private_db[count.index % length(aws_subnet.private_db)].id
  key_name      = var.key_name # Assuming you have a key_name variable

  vpc_security_group_ids = [aws_security_group.private.id]

  root_block_device {
    volume_size = var.disk_size
    volume_type
