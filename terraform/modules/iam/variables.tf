variable "name"                       { type = string }
variable "github_org"                  { type = string }
variable "github_repo"                 { type = string }
variable "ecr_repository_arn"          { type = string }
variable "ecs_task_execution_role_arn" { type = string }
variable "tags"                        { type = map(string); default = {} }
