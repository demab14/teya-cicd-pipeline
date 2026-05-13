variable "aws_region" {
  type    = string
  default = "eu-west-2"
}

variable "aws_account_id" {
  type        = string
  description = "Your AWS account ID"
}

variable "github_org" {
  type        = string
  description = "Your GitHub username or organisation"
}

variable "github_repo" {
  type        = string
  description = "Your GitHub repository name"
}

variable "certificate_arn" {
  type        = string
  description = "ACM certificate ARN for HTTPS listener"
  default     = ""
}
