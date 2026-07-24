data "aws_caller_identity" "current" {}

locals {
  bucket_name = coalesce(
    var.bucket_name_override,
    "${var.project_name}-${var.environment}-${data.aws_caller_identity.current.account_id}-frontend"
  )

  github_oidc_provider_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
}

resource "aws_s3_bucket" "frontend" {
  bucket = local.bucket_name
}

resource "aws_s3_bucket_website_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "index.html"
  }
}

resource "aws_s3_bucket_versioning" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = true
  block_public_policy     = false
  ignore_public_acls      = true
  restrict_public_buckets = false
}

resource "aws_s3_bucket_ownership_controls" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

data "aws_iam_policy_document" "frontend_public_read" {
  statement {
    sid    = "PublicReadForWebsite"
    effect = "Allow"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = [
      "s3:GetObject",
    ]

    resources = [
      "${aws_s3_bucket.frontend.arn}/*",
    ]
  }
}

resource "aws_s3_bucket_policy" "frontend_public_read" {
  bucket = aws_s3_bucket.frontend.id
  policy = data.aws_iam_policy_document.frontend_public_read.json

  depends_on = [
    aws_s3_bucket_public_access_block.frontend,
  ]
}

data "aws_iam_policy_document" "github_actions_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.frontend_repository_owner}/${var.frontend_repository_name}:environment:${var.github_environment_name}"
      ]
    }
  }
}

resource "aws_iam_role" "frontend_github" {
  name               = "${var.project_name}-${var.environment}-frontend-github-actions"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume.json
  description        = "Rol asumido por GitHub Actions para desplegar el frontend ${var.environment}"
}

data "aws_iam_policy_document" "frontend_deploy" {
  statement {
    sid = "ListBucket"
    actions = [
      "s3:ListBucket",
    ]
    resources = [
      aws_s3_bucket.frontend.arn,
    ]
  }

  statement {
    sid = "ManageObjects"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = [
      "${aws_s3_bucket.frontend.arn}/*",
    ]
  }

  dynamic "statement" {
    for_each = var.cloudfront_distribution_id != "" ? [1] : []
    content {
      sid = "InvalidateCloudFront"
      actions = [
        "cloudfront:CreateInvalidation",
      ]
      resources = ["*"]
    }
  }
}

resource "aws_iam_policy" "frontend_deploy" {
  name        = "${var.project_name}-${var.environment}-frontend-deploy"
  description = "Permisos para desplegar el frontend ${var.environment} en S3"
  policy      = data.aws_iam_policy_document.frontend_deploy.json
}

resource "aws_iam_role_policy_attachment" "frontend_deploy" {
  role       = aws_iam_role.frontend_github.name
  policy_arn = aws_iam_policy.frontend_deploy.arn
}
