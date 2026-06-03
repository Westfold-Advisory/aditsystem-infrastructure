# Bootstrap: crea bucket S3 + tabla DynamoDB para el remote state de Terraform,
# proveedor OIDC de GitHub y rol IAM para que GitHub Actions asuma Terraform.
# Ejecutar UNA vez con credenciales AWS de administrador (estado local).

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

# ── Variables ────────────────────────────────────────────────────────────────

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "aditsystem"
}

variable "state_bucket_name" {
  type        = string
  description = "Nombre globalmente único del bucket de state (ej. aditsystem-tf-state-123456789012)"
}

variable "github_org" {
  type        = string
  description = "Organización o usuario de GitHub (ej. ervicperezdev)"
}

variable "github_repo" {
  type        = string
  description = "Nombre del repositorio de infraestructura (ej. aditsystem-infrastructure)"
}

# ── S3 bucket para remote state ──────────────────────────────────────────────

resource "aws_s3_bucket" "tf_state" {
  bucket = var.state_bucket_name
}

resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ── DynamoDB para state locking ───────────────────────────────────────────────

resource "aws_dynamodb_table" "tf_lock" {
  name         = "${var.project_name}-tf-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

# ── OIDC provider de GitHub Actions ──────────────────────────────────────────

data "aws_caller_identity" "current" {}

resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  # Thumbprint de GitHub Actions OIDC (estable, actualizar si GitHub lo cambia)
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1", "1c58a3a8518e8759bf075b76b750d4f2df264fcd"]
}

# ── Rol IAM para Terraform via OIDC ──────────────────────────────────────────

data "aws_iam_policy_document" "github_actions_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/${var.github_repo}:*"]
    }
  }
}

resource "aws_iam_role" "terraform_github" {
  name               = "${var.project_name}-terraform-github-actions"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume.json
  description        = "Rol asumido por GitHub Actions para ejecutar Terraform"
}

# Política con permisos de Terraform sobre el state
data "aws_iam_policy_document" "terraform_state" {
  statement {
    sid     = "S3StateAccess"
    actions = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
    resources = [
      aws_s3_bucket.tf_state.arn,
      "${aws_s3_bucket.tf_state.arn}/*",
    ]
  }

  statement {
    sid       = "DynamoDBLock"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem", "dynamodb:DescribeTable"]
    resources = [aws_dynamodb_table.tf_lock.arn]
  }
}

resource "aws_iam_policy" "terraform_state" {
  name        = "${var.project_name}-terraform-state-access"
  description = "Acceso al bucket S3 de state y DynamoDB lock"
  policy      = data.aws_iam_policy_document.terraform_state.json
}

resource "aws_iam_role_policy_attachment" "terraform_state" {
  role       = aws_iam_role.terraform_github.name
  policy_arn = aws_iam_policy.terraform_state.arn
}

# PowerUserAccess para dev — restringe en prod adjuntando una policy acotada en su lugar
resource "aws_iam_role_policy_attachment" "power_user" {
  role       = aws_iam_role.terraform_github.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

# ── Outputs ───────────────────────────────────────────────────────────────────

output "state_bucket" {
  value = aws_s3_bucket.tf_state.bucket
}

output "dynamodb_table" {
  value = aws_dynamodb_table.tf_lock.name
}

output "github_actions_role_arn" {
  description = "Valor para el secret AWS_ROLE_ARN en GitHub"
  value       = aws_iam_role.terraform_github.arn
}

output "backend_config_dev" {
  description = "Contenido para config/backend-dev.hcl"
  value = <<-HCL
    bucket         = "${aws_s3_bucket.tf_state.bucket}"
    key            = "dev/terraform.tfstate"
    region         = "${var.aws_region}"
    dynamodb_table = "${aws_dynamodb_table.tf_lock.name}"
    encrypt        = true
  HCL
}

output "backend_config_prod" {
  description = "Contenido para config/backend-prod.hcl"
  value = <<-HCL
    bucket         = "${aws_s3_bucket.tf_state.bucket}"
    key            = "prod/terraform.tfstate"
    region         = "${var.aws_region}"
    dynamodb_table = "${aws_dynamodb_table.tf_lock.name}"
    encrypt        = true
  HCL
}
