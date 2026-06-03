# Remote state — habilitar tras bootstrap del bucket S3 y tabla DynamoDB (ver TRA-47).
#
# terraform {
#   backend "s3" {
#     bucket         = "aditsystem-terraform-state"
#     key            = "prod/terraform.tfstate"
#     region         = "us-east-1"
#     dynamodb_table = "aditsystem-terraform-locks"
#     encrypt        = true
#   }
# }
