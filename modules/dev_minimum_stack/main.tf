data "aws_caller_identity" "current" {}

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-kernel-6.1-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

locals {
  name_prefix              = "${var.project_name}-${var.environment}"
  backend_repository_name  = "${local.name_prefix}-backend"
  media_bucket_name        = "${local.name_prefix}-${data.aws_caller_identity.current.account_id}-media"
  github_oidc_provider_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
}

resource "aws_vpc" "this" {
  cidr_block           = "10.40.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = { Name = "${local.name_prefix}-vpc" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${local.name_prefix}-igw" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = "10.40.0.0/24"
  availability_zone       = var.availability_zones[0]
  map_public_ip_on_launch = true
  tags                    = { Name = "${local.name_prefix}-public" }
}

resource "aws_subnet" "private_db" {
  count             = 2
  vpc_id            = aws_vpc.this.id
  cidr_block        = "10.40.${count.index + 10}.0/24"
  availability_zone = var.availability_zones[count.index]
  tags              = { Name = "${local.name_prefix}-db-${count.index + 1}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    gateway_id = aws_internet_gateway.this.id
    cidr_block = "0.0.0.0/0"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "backend" {
  name_prefix = "${local.name_prefix}-backend-"
  description = "Public API only; SSH is deliberately absent."
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "FastAPI development endpoint"
    from_port   = var.backend_port
    to_port     = var.backend_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "database" {
  name_prefix = "${local.name_prefix}-database-"
  description = "PostgreSQL only from the backend instance."
  vpc_id      = aws_vpc.this.id
  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.backend.id]
  }
}

resource "aws_db_subnet_group" "this" {
  name       = "${local.name_prefix}-postgres"
  subnet_ids = aws_subnet.private_db[*].id
}

resource "aws_kms_key" "rds" {
  description             = "RDS storage encryption for ${local.name_prefix}"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  tags                    = { Name = "${local.name_prefix}-rds" }
}

resource "aws_kms_alias" "rds" {
  name          = "alias/${local.name_prefix}-rds"
  target_key_id = aws_kms_key.rds.key_id
}

resource "aws_db_instance" "postgres" {
  identifier                      = "${local.name_prefix}-postgres"
  engine                          = "postgres"
  engine_version                  = "16"
  instance_class                  = "db.t3.micro"
  allocated_storage               = 20
  max_allocated_storage           = 25
  storage_type                    = "gp3"
  storage_encrypted               = true
  kms_key_id                      = aws_kms_key.rds.arn
  db_name                         = var.db_name
  username                        = var.db_username
  manage_master_user_password     = true
  multi_az                        = var.enable_multi_az
  publicly_accessible             = false
  deletion_protection             = false
  skip_final_snapshot             = true
  backup_retention_period         = 1
  copy_tags_to_snapshot           = true
  auto_minor_version_upgrade      = true
  db_subnet_group_name            = aws_db_subnet_group.this.name
  vpc_security_group_ids          = [aws_security_group.database.id]
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
}

resource "aws_ecr_repository" "backend" {
  name                 = local.backend_repository_name
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration { scan_on_push = true }
  encryption_configuration { encryption_type = "AES256" }
}

resource "aws_ecr_lifecycle_policy" "backend" {
  repository = aws_ecr_repository.backend.name
  policy = jsonencode({ rules = [{
    rulePriority = 1
    description  = "Retain the 20 most recent backend images."
    selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 20 }
    action       = { type = "expire" }
  }] })
}

resource "aws_s3_bucket" "media" { bucket = local.media_bucket_name }
resource "aws_s3_bucket_public_access_block" "media" {
  bucket                  = aws_s3_bucket.media.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_ownership_controls" "media" {
  bucket = aws_s3_bucket.media.id
  rule { object_ownership = "BucketOwnerEnforced" }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "media" {
  bucket = aws_s3_bucket.media.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
resource "aws_s3_bucket_versioning" "media" {
  bucket = aws_s3_bucket.media.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_secretsmanager_secret" "backend_runtime" {
  name                    = "${local.name_prefix}/backend-runtime"
  description             = "Runtime-only backend configuration (JWT PEM keys, CORS). Populate outside version control."
  recovery_window_in_days = 7
}

resource "aws_cloudwatch_log_group" "backend" {
  name              = "/${var.project_name}/${var.environment}/backend"
  retention_in_days = 7
}

data "aws_iam_policy_document" "backend_github_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      identifiers = [local.github_oidc_provider_arn]
      type        = "Federated"
    }
    condition {
      values   = ["sts.amazonaws.com"]
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.backend_repository_owner}/${var.backend_repository_name}:environment:${var.github_environment_name}"]
    }
  }
}

resource "aws_iam_role" "backend_github" {
  name               = "${local.name_prefix}-backend-github-actions"
  assume_role_policy = data.aws_iam_policy_document.backend_github_assume.json
}

data "aws_iam_policy_document" "backend_github" {
  statement {
    resources = ["*"]
    sid       = "EcrAuthorization"
    actions   = ["ecr:GetAuthorizationToken"]
  }
  statement {
    sid       = "PushOnlyToBackendRepository"
    actions   = ["ecr:BatchCheckLayerAvailability", "ecr:CompleteLayerUpload", "ecr:InitiateLayerUpload", "ecr:PutImage", "ecr:UploadLayerPart"]
    resources = [aws_ecr_repository.backend.arn]
  }
  statement {
    sid     = "DeployOnlyToBackendInstance"
    actions = ["ssm:SendCommand"]
    resources = [
      "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:instance/${aws_instance.backend.id}",
      "arn:aws:ssm:${var.aws_region}::document/AWS-RunShellScript",
    ]
  }
  statement {
    sid       = "ReadOwnDeploymentCommand"
    actions   = ["ssm:GetCommandInvocation"]
    resources = ["*"]
  }
}
resource "aws_iam_role_policy" "backend_github" {
  name   = "ecr-push"
  role   = aws_iam_role.backend_github.id
  policy = data.aws_iam_policy_document.backend_github.json
}

resource "aws_iam_role" "backend_instance" {
  name               = "${local.name_prefix}-backend-instance"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }] })
}
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.backend_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
data "aws_iam_policy_document" "backend_instance" {
  statement {
    resources = ["*"]
    actions   = ["ecr:GetAuthorizationToken"]
  }
  statement {
    resources = [aws_ecr_repository.backend.arn]
    actions   = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:BatchCheckLayerAvailability"]
  }
  statement {
    resources = [aws_secretsmanager_secret.backend_runtime.arn, aws_db_instance.postgres.master_user_secret[0].secret_arn]
    actions   = ["secretsmanager:GetSecretValue"]
  }
  statement {
    resources = ["${aws_cloudwatch_log_group.backend.arn}:*"]
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
  }
}
resource "aws_iam_role_policy" "backend_instance" {
  name   = "runtime-access"
  role   = aws_iam_role.backend_instance.id
  policy = data.aws_iam_policy_document.backend_instance.json
}
resource "aws_iam_instance_profile" "backend" {
  role = aws_iam_role.backend_instance.name
  name = "${local.name_prefix}-backend"
}

resource "aws_instance" "backend" {
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = var.backend_instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.backend.id]
  iam_instance_profile        = aws_iam_instance_profile.backend.name
  associate_public_ip_address = true
  # Detailed EC2 monitoring is not needed for the development MVP; the
  # application still writes its logs to the dedicated CloudWatch log group.
  monitoring                  = false
  user_data_replace_on_change = true
  user_data                   = <<-USERDATA
    #!/bin/bash
    set -euxo pipefail
    dnf install -y docker amazon-ssm-agent
    systemctl enable --now docker amazon-ssm-agent
    usermod -aG docker ssm-user || true
  USERDATA
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }
  root_block_device {
    volume_size = 20
    encrypted   = true
    volume_type = "gp3"
  }
  tags = { Name = "${local.name_prefix}-backend" }
}
