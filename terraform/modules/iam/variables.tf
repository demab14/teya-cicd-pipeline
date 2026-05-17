variable "name" {
  type = string
}

variable "github_org" {
  type = string
}

variable "github_repo" {
  type = string
}

variable "ecr_repository_arn" {
  type = string
}

variable "ecs_task_execution_role_arn" {
  type = string
}

variable "ecs_cluster_arn" {
  type        = string
  description = "ECS cluster ARN to scope deployment permissions"
}

variable "tags" {
  type    = map(string)
  default = {}
}
