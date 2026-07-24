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

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

module "frontend_deploy_target" {
  source = "../../modules/frontend_deploy_target"

  project_name              = "aditsystem"
  environment               = "dev"
  aws_region                = var.aws_region
  frontend_repository_owner = "Westfold-Advisory"
  frontend_repository_name  = "ADITSYSTEM"
  github_environment_name   = "production"
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
