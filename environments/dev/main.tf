terraform {
  required_version = ">= 1.5.0"

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

# Recursos de infraestructura se añadirán en iteraciones posteriores.
# Ejemplos previstos: bucket S3 (frontend estático), RDS, IAM OIDC para GitHub Actions.

output "environment" {
  value = "dev"
}
