output "bucket_name" {
  description = "Nombre del bucket S3 del frontend"
  value       = aws_s3_bucket.frontend.bucket
}

output "deploy_role_arn" {
  description = "ARN del rol IAM para el workflow de frontend en GitHub Actions"
  value       = aws_iam_role.frontend_github.arn
}

output "cloudfront_distribution_id" {
  description = "Distribution ID que debe publicarse en GitHub Variables si existe"
  value       = var.cloudfront_distribution_id
}
