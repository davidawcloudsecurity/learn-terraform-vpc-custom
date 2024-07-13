#3 tier web architecture VPC
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

variable "create_instance_vm_linux" {
  description = "Flag to create the linux instance"
  type        = bool
  default     = false
}

variable "create_instance_vm_windows" {
  description = "Flag to create the windows instance"
  type        = bool
  default     = false
}

variable "create_instance_pod" {
  description = "Flag to create the pod instance"
  type        = bool
  default     = false
}

variable "user_tags" {
  description = "Please provide name for your project."
  type    = string 
}

variable "resource_tags" {
  description = "User-provided tags for resources."
  type        = map(string)
  default     = {
    "Key"        = "default-name"
    "Environment" = "default-env"
  }
}

variable "vpc-cidr-block" {
  description = "CIDR block range for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public-subnet-cidr-blocks" {
  description = "CIDR block range for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private-subnet-cidr-blocks-app" {
  description = "CIDR block range for private subnets for app"
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "private-subnet-cidr-blocks-db" {
  description = "CIDR block range for private subnets for database"
  type        = list(string)
  default     = ["10.0.5.0/24", "10.0.6.0/24"]
}

variable "availability-zones" {
  description = "List of availability zones for selected region"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "instance_type" {
  description = "Instance type for EC2 instances"
  type        = string
  default     = "t2.nano"
}

variable "ami_id_vm" {
  description = "AMI ID for EC2 instances"
  type        = string
}

variable "ami_id_pod" {
  description = "AMI ID for EC2 instances"
  type        = string
}

variable "key_name" {
  description = "Key pair name for SSH access to EC2 instances"
  type        = string
}

# VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc-cidr-block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.user_tags}-main-vpc"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.user_tags}-main-igw"
  }
}

# Elastic IP for NAT Gateway
resource "aws_eip" "nat_eip" {
  vpc = true

  tags = {
    Name = "${var.user_tags}-nat-eip"
  }
}

# NAT Gateway
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public[0].id

  tags = {
    Name = "${var.user_tags}-main-nat"
  }
  depends_on = [aws_internet_gateway.main]
}

# Public Subnets
resource "aws_subnet" "public" {
  count                   = length(var.public-subnet-cidr-blocks)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = element(var.public-subnet-cidr-blocks, count.index)
  availability_zone       = element(var.availability-zones, count.index)
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.user_tags}-public-subnet-${count.index}"
  }
}

# Private Subnets (App)
resource "aws_subnet" "private_app" {
  count             = length(var.private-subnet-cidr-blocks-app)
  vpc_id            = aws_vpc.main.id
  cidr_block        = element(var.private-subnet-cidr-blocks-app, count.index)
  availability_zone = element(var.availability-zones, count.index)

  tags = {
    Name = "${var.user_tags}-private-app-subnet-${count.index}"
  }
}

# Private Subnets (DB)
resource "aws_subnet" "private_db" {
  count             = length(var.private-subnet-cidr-blocks-db)
  vpc_id            = aws_vpc.main.id
  cidr_block        = element(var.private-subnet-cidr-blocks-db, count.index)
  availability_zone = element(var.availability-zones, count.index)

  tags = {
    Name = "${var.user_tags}-private-db-subnet-${count.index}"
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
    Name = "${var.user_tags}-public-rt"
  }
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

  tags = {
    Name = "${var.user_tags}-private-rt"
  }
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
    from_port   = 443
    to_port     = 443
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
    Name = "${var.user_tags}-public-sg"
  }
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

  tags = {
    Name = "${var.user_tags}-private-sg"
  }
}

# EC2 Instance for Web Server (Linux)
resource "aws_instance" "web" {
  count                  = var.create_instance_vm_linux ? 1 : 0
  ami                    = var.ami_id_vm_linux
  instance_type          = var.instance_type
  key_name               = var.key_name
  subnet_id              = element(aws_subnet.public[*].id, 0)  # Using the first public subnet
  security_groups        = [aws_security_group.public.name]
  associate_public_ip_address = true

  tags = {
    Name = "${var.user_tags}-web"
  }

  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install -y nginx
              systemctl start nginx
              EOF
}

# EC2 Instance for Windows Server
resource "aws_instance" "windows" {
  count                  = var.create_instance_vm_windows ? 1 : 0
  ami                    = var.ami_id_vm_windows
  instance_type          = var.instance_type
  key_name               = var.key_name
  subnet_id              = element(aws_subnet.public[*].id, 1)  # Using the second public subnet
  security_groups        = [aws_security_group.public.name]
  associate_public_ip_address = true

  tags = {
    Name = "${var.user_tags}-windows"
  }

  user_data = <<-EOF
              <powershell>
              Install-WindowsFeature -Name Web-Server
              </powershell>
              EOF
}

# Skip this as it is kubernetes
/*
# EC2 Instances for Kubernetes Master
resource "aws_instance" "master" {
  count           = var.create_instance_pod ? 1 : 0
  ami             = var.ami_id_pod
  instance_type   = var.instance_type
  key_name        = var.key_name
  subnet_id       = element(aws_subnet.public[*].id, 0)
  security_groups = [aws_security_group.public.name]

  tags = {
    Name = "${var.user_tags}-master"
  }

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
  count           = var.create_instance_pod ? 1 : 0
  ami             = var.ami_id_pod
  instance_type   = var.instance_type
  key_name        = var.key_name
  subnet_id       = element(aws_subnet.private_app[*].id, count.index)
  security_groups = [aws_security_group.private.name]

  tags = {
    Name = "${var.user_tags}-worker-${count.index}"
  }

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
*/
