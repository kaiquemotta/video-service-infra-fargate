provider "aws" {
  region = "us-east-1"
}

# Criação do repositório ECR
resource "aws_ecr_repository" "video_service" {
  name                 = "video-service"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# IAM role para execução da task
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "fargate-vpc"
  }
}

# Subnet pública
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1a"

  tags = {
    Name = "fargate-subnet"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "fargate-gateway"
  }
}

# Route table
resource "aws_route_table" "rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "fargate-rt"
  }
}

# Route table association
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.rt.id
}

# Security group para liberar porta 8080
resource "aws_security_group" "fargate_sg" {
  name        = "fargate-sg"
  description = "Permitir acesso HTTP"
  vpc_id      = aws_vpc.main.id

  ingress {
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
}

# ECS Cluster
resource "aws_ecs_cluster" "app_cluster" {
  name = "springboot-cluster"
}

# Task Definition
resource "aws_ecs_task_definition" "app_task" {
  family                   = "springboot-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  container_definitions    = jsonencode([{
    name      = "springboot-app",
    image     = "${aws_ecr_repository.video_service.repository_url}:latest",
    portMappings = [{
      containerPort = 8080,
      hostPort      = 8080
    }]
  }])
}

# ECS Service
resource "aws_ecs_service" "app_service" {
  name            = "springboot-service"
  cluster         = aws_ecs_cluster.app_cluster.id
  task_definition = aws_ecs_task_definition.app_task.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  network_configuration {
    subnets         = [aws_subnet.public.id]
    assign_public_ip = true
    security_groups = [aws_security_group.fargate_sg.id]
  }

  depends_on = [aws_iam_role_policy_attachment.ecs_task_execution_policy]
}

# Output da URL do repositório ECR
output "ecr_repository_url" {
  value = aws_ecr_repository.video_service.repository_url
}