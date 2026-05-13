output "vpc_id" {
  description = "ID of the dev VPC."
  value       = module.network.vpc_id
}

output "public_subnet_ids" {
  description = "IDs of public subnets in the dev VPC."
  value       = module.network.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs of private subnets in the dev VPC."
  value       = module.network.private_subnet_ids
}
