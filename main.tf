provider "aws" {
  region = var.region
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

# Variables
variable "region" {
  type    = string
  default = "us-east-1"
}

variable "create_instance" {
  description = "Flag to create the instance"
  type        = bool
  default     = false
}

variable "user_tags" {
  description = "User-provided tags for resources."
  type        = map(string)
  default     = {
    "Name"        = "default-name"
    "Environment" = "default-env"
  }
}

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
  description = "CIDR block range for private subnets for app"
}

variable "private-subnet-cidr-blocks-db" {
  type        = list(string)
  default     = ["10.0.5.0/24", "10.0.6.0/24"]
  description = "CIDR block range for private subnets for database"
}

variable "availability-zones" {
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
  description = "List of availability zones for selected region"
}

variable "instance_type" {
  type        = string
  default     = "t3.small"
  description = "Instance type for EC2 instances"
}

variable "ami_id" {
  type        = string
  description = "AMI ID for EC2 instances"
}

variable "key_name" {
  type        = string
  description = "Key pair name for SSH access to EC2 instances"
}

# VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc-cidr-block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge({
    Name = "k8s-vpc"
  }, var.user_tags)
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge({
    Name = "k8s-igw"
  }, var.user_tags)
}

# Elastic IP for NAT Gateway
resource "aws_eip" "terraform-eks-eip" {
  vpc = true

  tags = merge({
    Name = "k8s-eip"
  }, var.user_tags)
}

# NAT Gateway
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.terraform-eks-eip.id
  subnet_id     = aws_subnet.public[0].id

  tags = merge({
    Name = "k8s-nat"
  }, var.user_tags)

  depends_on = [aws_internet_gateway.main]
}

# Public Subnets
resource "aws_subnet" "public" {
  count                   = length(var.public-subnet-cidr-blocks)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = element(var.public-subnet-cidr-blocks, count.index)
  availability_zone       = element(var.availability-zones, count.index)
  map_public_ip_on_launch = true

  tags = merge({
    Name = "k8s-public-subnet-${count.index}"
  }, var.user_tags)
}

# Private Subnets (App)
resource "aws_subnet" "private_app" {
  count             = length(var.private-subnet-cidr-blocks-app)
  vpc_id            = aws_vpc.main.id
  cidr_block        = element(var.private-subnet-cidr-blocks-app, count.index)
  availability_zone = element(var.availability-zones, count.index)

  tags = merge({
    Name = "k8s-private-app-subnet-${count.index}"
  }, var.user_tags)
}

# Private Subnets (DB)
resource "aws_subnet" "private_db" {
  count             = length(var.private-subnet-cidr-blocks-db)
  vpc_id            = aws_vpc.main.id
  cidr_block        = element(var.private-subnet-cidr-blocks-db, count.index)
  availability_zone = element(var.availability-zones, count.index)

  tags = merge({
    Name = "k8s-private-db-subnet-${count.index}"
  }, var.user_tags)
}

# Route Tables and Associations
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge({
    Name = "k8s-public-rt"
  }, var.user_tags)
}

resource "aws_route_table_association" "public" {
  count          = length(var.public-subnet-cidr-blocks)
  subnet_id      = element(aws_subnet.public[*].id, count.index)
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = merge({
    Name = "k8s-private-rt"
  }, var.user_tags)
}

resource "aws_route_table_association" "private_app" {
  count          = length(var.private-subnet-cidr-blocks-app)
  subnet_id      = element(aws_subnet.private_app[*].id, count.index)
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_db" {
  count          = length(var.private-subnet-cidr-blocks-db)
  subnet_id      = element(aws_subnet.private_db[*].id, count.index)
  route_table_id = aws_route_table.private.id
}

# Security Groups
resource "aws_security_group" "public" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge({
    Name = "k8s-public-sg"
  }, var.user_tags)
}

resource "aws_security_group" "private" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge({
    Name = "k8s-private-sg"
  }, var.user_tags)
}

# EC2 Instances for Kubernetes Master
resource "aws_instance" "master" {
  count           = var.create_instance ? 1 : 0
  ami             = var.ami_id
  instance_type   = var.instance_type
  key_name        = var.key_name
  subnet_id       = element(aws_subnet.public[*].id, 0)
  security_groups = [aws_security_group.public.name]

  tags = merge({
    Name = "k8s-master"
  }, var.user_tags)

  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install -y docker.io
              systemctl enable docker.service
              systemctl start docker.service
              curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
              apt-add-repository "deb http://apt.kubernetes.io/ kubernetes-xenial main"
              apt-get update -y
              apt-get install -y kubelet kubeadm kubectl
              kubeadm init --pod-network-cidr=10.244.0.0/16
              mkdir -p /home/ubuntu/.kube
              cp -i /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
              chown ubuntu:ubuntu /home/ubuntu/.kube/config
              export KUBECONFIG=/home/ubuntu/.kube/config
              kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
              EOF
}

# EC2 Instances for Kubernetes Workers
resource "aws_instance" "worker" {
  count           = var.create_instance ? 1 : 0
  ami             = var.ami_id
  instance_type   = var.instance_type
  key_name        = var.key_name
  subnet_id       = element(aws_subnet.private_app[*].id, count.index)
  security_groups = [aws_security_group.private.name]

  tags = merge({
    Name = "k8s-worker-${count.index}"
  }, var.user_tags)

  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install -y docker.io
              systemctl enable docker.service
              systemctl start docker.service
              curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
              apt-add-repository "deb http://apt.kubernetes.io/ kubernetes-xenial main"
              apt-get update -y
              apt-get install -y kubelet kubeadm kubectl
              EOF
}
