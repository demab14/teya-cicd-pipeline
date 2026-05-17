terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
  backend "s3" {
    bucket         = "teya-demo-tfstate"
    key            = "prod/terraform.tfstate"
    region         = "eu-west-2"
    dynamodb_table = "teya-demo-tfstate-lock"
    encrypt        = true
  }
}

provider "aws" { region = var.aws_region }

locals {
  name = "teya-demo"
  tags = {
    Project     = "teya-demo"
    Environment = "prod"
    ManagedBy   = "terraform"
  }
}

module "vpc" {
  source               = "../../modules/vpc"
  name                 = local.name
  vpc_cidr             = "10.0.0.0/16"
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]
  availability_zones   = ["eu-west-2a", "eu-west-2b"]
  tags                 = local.tags
}

module "ecr" {
  source          = "../../modules/ecr"
  repository_name = "${local.name}-app"
  tags            = local.tags
}

module "ecs" {
  source                = "../../modules/ecs"
  name                  = local.name
  cluster_name          = "${local.name}-cluster"
  container_name        = "${local.name}-app"
  container_image       = "${module.ecr.repository_url}:latest"
  container_port        = 5000
  vpc_id                = module.vpc.vpc_id
  private_subnet_ids    = module.vpc.private_subnet_ids
  alb_security_group_id = aws_security_group.alb.id
  target_group_arn      = aws_lb_target_group.app.arn
  alb_listener_arn      = aws_lb_listener.app.arn
  aws_region            = var.aws_region
  tags                  = local.tags
}

module "iam" {
  source                      = "../../modules/iam"
  name                        = local.name
  github_org                  = var.github_org
  github_repo                 = var.github_repo
  ecr_repository_arn          = module.ecr.repository_arn
  ecs_task_execution_role_arn = module.ecs.task_execution_role_arn
  ecs_cluster_arn             = module.ecs.cluster_arn
  tags                        = local.tags
}

resource "aws_s3_bucket" "alb_logs" {
  bucket        = "${local.name}-alb-logs-${var.aws_account_id}"
  force_destroy = true
  tags          = local.tags
}

resource "aws_s3_bucket_server_side_encryption_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_versioning" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_wafv2_web_acl" "alb" {
  name  = "${local.name}-waf"
  scope = "REGIONAL"

  default_action { allow {} }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1
    override_action { none {} }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "CommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.name}-waf"
    sampled_requests_enabled   = true
  }

  tags = local.tags
}

resource "aws_security_group" "alb" {
  name        = "${local.name}-alb-sg"
  description = "ALB security group — allow HTTP inbound"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "Allow HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow outbound to ECS tasks"
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  tags = local.tags
}

resource "aws_lb" "app" {
  name                       = "${local.name}-alb"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.alb.id]
  subnets                    = module.vpc.public_subnet_ids
  enable_deletion_protection = true
  drop_invalid_header_fields = true

  access_logs {
    bucket  = aws_s3_bucket.alb_logs.bucket
    enabled = true
  }

  tags = local.tags
}

resource "aws_wafv2_web_acl_association" "alb" {
  resource_arn = aws_lb.app.arn
  web_acl_arn  = aws_wafv2_web_acl.alb.arn
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
  port              = 80
  protocol          = "HTTP" # nosemgrep: terraform.aws.security.insecure-load-balancer-tls-version.insecure-load-balancer-tls-version

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
