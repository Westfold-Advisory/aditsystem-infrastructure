output "backend_ecr_repository" { value = aws_ecr_repository.backend.name }
output "backend_ecr_repository_url" { value = aws_ecr_repository.backend.repository_url }
output "backend_github_deploy_role_arn" { value = aws_iam_role.backend_github.arn }
output "backend_instance_id" { value = aws_instance.backend.id }
output "backend_public_ip" { value = aws_instance.backend.public_ip }
output "backend_runtime_secret_arn" { value = aws_secretsmanager_secret.backend_runtime.arn }
output "database_master_secret_arn" {
  sensitive = true
  value     = aws_db_instance.postgres.master_user_secret[0].secret_arn
}
output "media_bucket_name" { value = aws_s3_bucket.media.bucket }
