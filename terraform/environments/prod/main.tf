terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "teya-demo-tfstate"
    key            = "prod/terraform.tfstate"
    region         = "eu-west-2"
    dynamodb_table = "teya-demo-tfstate-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
}

locals {
  name = "teya-demo"
  tags = {
    Project     = "teya-demo"
    Environment = "prod"
    ManagedBy   = "terraform"
  }
}

module "vpc" {
  source = "../../modules/vpc"

  name                 = local.name
  vpc_cidr             = "10.0.0.0/16"
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]
  availability_zones   = ["eu-west-2a", "eu-west-2b"]
  tags                 = local.tags
}

module "ecr" {
  source = "../../modules/ecr"

  repository_name = "${local.name}-app"
  tags            = local.tags
}

module "ecs" {
  source = "../../modules/ecs"

  name                  = local.name
  cluster_name          = "${local.name}-cluster"
  container_name        = "${local.name}-app"
  container_image       = "${module.ecr.repository_url}:latest"
  container_port        = 5000
  vpc_id                = module.vpc.vpc_id
  private_subnet_ids    = module.vpc.private_subnet_ids
  alb_security_group_id = aws_security_group.alb.id
  target_group_arn      = aws_lb_target_group.app.arn
  aws_region            = var.aws_region
  tags                  = local.tags
}

module "iam" {
  source = "../../modules/iam"

  name                        = local.name
  github_org                  = var.github_org
  github_repo                 = var.github_repo
  ecr_repository_arn          = module.ecr.repository_arn
  ecs_task_execution_role_arn = module.ecs.task_execution_role_arn
  tags                        = local.tags
}

resource "aws_security_group" "alb" {
  name        = "${local.name}-alb-sg"
  description = "ALB security group"
  vpc_id      = module.vpc.vpc_id

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

  tags = local.tags
}

resource "aws_lb" "app" {
  name               = "${local.name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = module.vpc.public_subnet_ids

  tags = local.tags
}

resource "aws_lb_target_group" "app" {
  name        = "${local.name}-tg"
  port        = 5000
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"

  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
  }

  tags = local.tags
}

resource "aws_lb_listener" "app" {
  load_balancer_arn = aws_lb.app.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

output "github_actions_role_arn" {
  value       = module.iam.github_actions_role_arn
  description = "Add this as AWS_OIDC_ROLE_ARN in GitHub repository secrets"
}

output "alb_dns_name" {
  value = aws_lb.app.dns_name
}
