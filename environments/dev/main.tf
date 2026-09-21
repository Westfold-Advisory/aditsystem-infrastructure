terraform {
  required_version = ">= 1.5.0"

  backend "s3" {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

variable "aws_region" {
  type    = string
  default = "mx-central-1"
}

variable "availability_zones" {
  description = "Dos AZs de la región elegida; se requieren para el subnet group de RDS."
  type        = list(string)
  default     = ["mx-central-1a", "mx-central-1b"]
}

variable "enable_alb" { default = true }
variable "enable_cloudfront" { default = true }
variable "enable_waf" { default = false }
variable "enable_custom_dns" { default = true }
variable "enable_multi_az" { default = false }
variable "route53_zone_name" {
  type    = string
  default = "aditsystem-dev.ervic.pro"
}
variable "frontend_domain_name" {
  type    = string
  default = "aditsystem-dev.ervic.pro"
}
variable "api_domain_name" {
  type    = string
  default = "api.aditsystem-dev.ervic.pro"
}

module "frontend_deploy_target" {
  source = "../../modules/frontend_deploy_target"

  project_name              = "aditsystem"
  environment               = "dev"
  aws_region                = var.aws_region
  frontend_repository_owner = "Westfold-Advisory"
  frontend_repository_name  = "ADITSYSTEM"
  github_environment_name   = "development"
}

module "dev_minimum_stack" {
  source = "../../modules/dev_minimum_stack"

  project_name              = "aditsystem"
  environment               = "dev"
  aws_region                = var.aws_region
  availability_zones        = var.availability_zones
  backend_repository_owner  = "Westfold-Advisory"
  backend_repository_name   = "aditsystem-backend"
  github_environment_name   = "development"
  enable_alb                = var.enable_alb
  enable_cloudfront         = var.enable_cloudfront
  enable_waf                = var.enable_waf
  enable_custom_dns         = var.enable_custom_dns
  enable_multi_az           = var.enable_multi_az
  route53_zone_name         = var.route53_zone_name
  frontend_domain_name      = var.frontend_domain_name
  api_domain_name           = var.api_domain_name
  frontend_website_endpoint = module.frontend_deploy_target.website_endpoint
  providers                 = { aws = aws, aws.us_east_1 = aws.us_east_1 }
}

output "environment" {
  value = "dev"
}

output "frontend_bucket_name" {
  value = module.frontend_deploy_target.bucket_name
}

output "frontend_deploy_role_arn" {
  value = module.frontend_deploy_target.deploy_role_arn
}

output "frontend_github_variables" {
  value = {
    AWS_REGION                 = var.aws_region
    S3_BUCKET                  = module.frontend_deploy_target.bucket_name
    CLOUDFRONT_DISTRIBUTION_ID = module.frontend_deploy_target.cloudfront_distribution_id
  }
}

output "frontend_website_url" {
  value = module.frontend_deploy_target.website_url
}

output "backend_ecr_repository" { value = module.dev_minimum_stack.backend_ecr_repository }
output "backend_github_deploy_role_arn" { value = module.dev_minimum_stack.backend_github_deploy_role_arn }
output "backend_runtime_secret_arn" { value = module.dev_minimum_stack.backend_runtime_secret_arn }
output "database_master_secret_arn" {
  sensitive = true
  value     = module.dev_minimum_stack.database_master_secret_arn
}
output "database_kms_key_arn" { value = module.dev_minimum_stack.database_kms_key_arn }
output "media_bucket_name" { value = module.dev_minimum_stack.media_bucket_name }
output "backend_instance_id" { value = module.dev_minimum_stack.backend_instance_id }
output "backend_public_ip" { value = module.dev_minimum_stack.backend_public_ip }
output "backend_github_variables" {
  value = {
    AWS_REGION            = var.aws_region
    AWS_ECR_REPOSITORY    = module.dev_minimum_stack.backend_ecr_repository
    AWS_DEPLOY_ROLE_ARN   = module.dev_minimum_stack.backend_github_deploy_role_arn
    AWS_DB_HOST           = module.dev_minimum_stack.database_endpoint
    AWS_DB_PORT           = module.dev_minimum_stack.database_port
    AWS_MEDIA_BUCKET_NAME = module.dev_minimum_stack.media_bucket_name
  }
}
output "frontend_domain_name" { value = var.enable_cloudfront && var.enable_custom_dns ? var.frontend_domain_name : null }
output "api_domain_name" { value = var.enable_alb && var.enable_custom_dns ? var.api_domain_name : null }
