output "tfstate_bucket" {
  description = "S3 bucket created for Terraform state."
  value       = aws_s3_bucket.tfstate.id
}

output "lock_table_name" {
  description = "DynamoDB table created for Terraform state locking."
  value       = aws_dynamodb_table.lock.name
}
