variable "project_name" { type = string }
variable "environment" { type = string }
variable "aws_region" { type = string }
variable "backend_repository_owner" { type = string }
variable "backend_repository_name" { type = string }
variable "github_environment_name" { type = string }

variable "availability_zones" {
  description = "Dos zonas de disponibilidad para el DB subnet group privado."
  type        = list(string)
}

variable "backend_instance_type" {
  description = "Instancia x86_64 pequeña para Docker."
  type        = string
  default     = "t3.micro"
}

variable "backend_port" {
  type    = number
  default = 8000
}

variable "db_name" {
  type    = string
  default = "aditsystem"
}

variable "db_username" {
  type    = string
  default = "aditsystem_admin"
}

variable "enable_alb" { default = false }
variable "enable_cloudfront" { default = false }
variable "enable_waf" { default = false }
variable "enable_custom_dns" { default = false }
variable "enable_multi_az" { default = false }
