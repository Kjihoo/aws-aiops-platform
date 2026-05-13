variable "project_name" {
  description = "Project name used for resource naming and tagging."
  type        = string
  default     = "team4-aiops"
}

variable "environment" {
  description = "Deployment environment name."
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region for deployment."
  type        = string
  default     = "ap-northeast-2"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}
