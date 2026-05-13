variable "project_name" {
  description = "Project name used for bootstrap resource naming and tagging."
  type        = string
  default     = "team4-aiops"
}

variable "environment" {
  description = "Bootstrap environment name."
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region for the bootstrap resources."
  type        = string
  default     = "ap-northeast-2"
}

variable "tfstate_bucket" {
  description = "S3 bucket name used for Terraform state storage. Must be globally unique."
  type        = string
  default     = "team4-aiops-tfstate-089955620282"
}

variable "lock_table" {
  description = "DynamoDB table name used for Terraform state locking."
  type        = string
  default     = "team4-aiops-tflock"
}
